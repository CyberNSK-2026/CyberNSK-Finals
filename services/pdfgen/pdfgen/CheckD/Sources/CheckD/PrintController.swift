//
//  PrintController.swift
//  CheckD
//
//  Запрос PDF по записи ответа (checklist_answers.id); клиенту — путь `/pdf-files/<имя файла>`.
//

import AsyncHTTPClient
import Foundation
import NIO
import FastCGI2

// MARK: - Конфиг из ENV

private enum PrintServiceEnv {
    /// DNS/имя сервиса checkd-print (docker-compose).
    static var host: String {
        let raw = ProcessInfo.processInfo.environment["CHECKD_PRINT_SERVICE_HOST"] ?? ""
        return raw.isEmpty ? "checkd-print" : raw
    }

    static var port: String {
        let raw = ProcessInfo.processInfo.environment["CHECKD_PRINT_SERVICE_PORT"] ?? ""
        return raw.isEmpty ? "8080" : raw
    }

    static var printServiceURL: String {
        "http://\(host):\(port)/print-service/print-page"
    }

    /// Хост CheckD для страницы печати (с контейнера принтера по DNS). ENV: **`CHECKD_EXPORT_ANSWER_HOST`**, иначе **`checkd`**.
    static var exportAnswerPageHost: String {
        let raw = ProcessInfo.processInfo.environment["CHECKD_EXPORT_ANSWER_HOST"] ?? ""
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "checkd" : t
    }

    /// Порт внутреннего vhost только для экспорта (см. nginx `8084`). ENV: **`CHECKD_EXPORT_ANSWER_PORT`**, иначе **`8084`**.
    static var exportAnswerPagePort: String {
        let raw = ProcessInfo.processInfo.environment["CHECKD_EXPORT_ANSWER_PORT"] ?? ""
        return raw.isEmpty ? "8084" : raw
    }
}

// MARK: - Контракт с микросервисом печати (JSON)

private struct RemotePrintPageRequest: Codable {
    let url: URL
    let fileTTL: TimeInterval?
}

private struct RemotePrintPageResponse: Codable {
    let ok: Bool
    let pdfurl: String?
    let error: String?
}

// MARK: - Ответ API CheckD

struct AnswerPrintExportRequest: Codable {
    let answer_id: Int
}

struct AnswerPrintExportResponse: Codable {
    let ok: Bool
    /// Путь без хоста, например `/pdf-files/uuid.pdf`.
    let path: String?
    let error: String?
}

// MARK: - Права

/// Админ, автор ответа или автор чеклиста (как у списка экспорта / модерации ответов).
private func canUserPrintAnswer(session: SessionData, record: ChecklistAnswerRecord, checklist: Checklist) -> Bool {
    if session.userRole == 1 {
        return true
    }
    if record.user_id == session.userID {
        return true
    }
    if checklist.author_id == session.userID {
        return true
    }
    return false
}

private func buildExportPageURL(answerId: Int) throws -> URL {
    let host = PrintServiceEnv.exportAnswerPageHost
    let rendered = "http://\(host):\(PrintServiceEnv.exportAnswerPagePort)/export-answer.html?id=\(answerId)"
    guard let url = URL(string: rendered) else {
        throw PrintControllerError.invalidExportURL
    }
    return url
}

private enum PrintControllerError: Error {
    case invalidExportURL
}

private let printExportJSONEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.withoutEscapingSlashes]
    return e
}()

private func jsonBuffer<T: Encodable>(_ value: T) throws -> ByteBuffer {
    let data = try printExportJSONEncoder.encode(value)
    return ByteBuffer(bytes: [UInt8](data))
}

private func requestRemotePrint(url: URL, fileTTL: TimeInterval?) async throws -> RemotePrintPageResponse {
    let body = try JSONEncoder().encode(RemotePrintPageRequest(url: url, fileTTL: fileTTL))
    var httpReq = HTTPClientRequest(url: PrintServiceEnv.printServiceURL)
    httpReq.method = .POST
    httpReq.headers.add(name: "Content-Type", value: "application/json")
    httpReq.body = .bytes(body)

    let response = try await HTTPClient.shared.execute(httpReq, timeout: .seconds(120))
    var collected = try await response.body.collect(upTo: 4 * 1024 * 1024)
    let data = collected.readBytes(length: collected.readableBytes).map { Data($0) } ?? Data()
    guard (200..<300).contains(response.status.code) else {
        let text = String(data: data, encoding: .utf8) ?? ""
        throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "print service HTTP \(response.status.code): \(text)"])
    }
    return try JSONDecoder().decode(RemotePrintPageResponse.self, from: data)
}

/// Путь для клиента: только имя файла из print-service → `/pdf-files/<name>`.
private func clientPdfPath(fromPrintServiceFilename name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains("..") {
        return nil
    }
    return "/pdf-files/\(trimmed)"
}

public func InitPrintRoutes() async {
    await server.on(path: "/api/checklists/print-export", method: "POST") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }

        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BodyTooLarge)
        }

        let payload: AnswerPrintExportRequest
        do {
            payload = try JSONDecoder().decode(AnswerPrintExportRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }

        guard payload.answer_id > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }

        guard let record = await DatabaseHelpers.getChecklistAnswer(recordId: payload.answer_id) else {
            return Response(statusCode: 404, contentType: "application/json", data: try! jsonBuffer(AnswerPrintExportResponse(
                ok: false,
                path: nil,
                error: "Answer not found"
            )))
        }

        guard let checklist = await DatabaseHelpers.getChecklist(id: record.checklist_id) else {
            return Response(statusCode: 404, contentType: "application/json", data: try! jsonBuffer(AnswerPrintExportResponse(
                ok: false,
                path: nil,
                error: "Checklist not found"
            )))
        }

        guard canUserPrintAnswer(session: sessionData, record: record, checklist: checklist) else {
            return Response(statusCode: 403, contentType: "application/json", data: StaticAnswers.Forbidden)
        }

        let sourceURL: URL
        do {
            sourceURL = try buildExportPageURL(answerId: payload.answer_id)
        } catch PrintControllerError.invalidExportURL {
            return Response(statusCode: 500, contentType: "application/json", data: try! jsonBuffer(AnswerPrintExportResponse(
                ok: false,
                path: nil,
                error: "Invalid export URL template"
            )))
        }

        do {
            let remote = try await requestRemotePrint(url: sourceURL, fileTTL: nil)
            guard remote.ok, let name = remote.pdfurl, let path = clientPdfPath(fromPrintServiceFilename: name) else {
                let msg = remote.error ?? "print service failed"
                return Response(statusCode: 502, contentType: "application/json", data: try! jsonBuffer(AnswerPrintExportResponse(
                    ok: false,
                    path: nil,
                    error: msg
                )))
            }
            return Response(statusCode: 200, contentType: "application/json", data: try! jsonBuffer(AnswerPrintExportResponse(
                ok: true,
                path: path,
                error: nil
            )))
        } catch {
            return Response(statusCode: 502, contentType: "application/json", data: try! jsonBuffer(AnswerPrintExportResponse(
                ok: false,
                path: nil,
                error: "print service unreachable: \(error.localizedDescription)"
            )))
        }
    }
}
