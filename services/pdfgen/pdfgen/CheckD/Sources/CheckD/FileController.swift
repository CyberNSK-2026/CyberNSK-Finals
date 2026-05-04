//
//  FileController.swift
//  CheckD
//
//  Файлы на диске (CHECKD_USER_FILES_PATH / {user_id}/{id}), в Postgres только метаданные.
//  Список / загрузка / скачивание / удаление — только для своих файлов (сессия).
//

import Foundation
import NIO
import FastCGI2
import ServiceStdio

private let userFileMaxRawBytes = 25 * 1024 * 1024
private let userFileNewBodyMaxBytes = 36 * 1024 * 1024

private struct FilesListItemJSON: Codable {
    let id: Int
    let name: String
    let size: Int
    let created_at: String
}

private struct FilesListResponse: Codable {
    let ok: Bool
    let files: [FilesListItemJSON]?
    let error: String?
}

private struct FilesNewRequest: Codable {
    let filename: String
    let filedata: String
}

private struct FilesOkErrorResponse: Codable {
    let ok: Bool
    let error: String?
}

private struct FilesGetResponse: Codable {
    let ok: Bool
    let filedata: String?
    let error: String?
}

private func userFilesRootDirectory() -> URL {
    if let raw = ProcessInfo.processInfo.environment["CHECKD_USER_FILES_PATH"], !raw.isEmpty {
        return URL(fileURLWithPath: raw, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent("user-files", isDirectory: true)
}

private func storageFileURL(userId: Int, fileId: Int, filename: String? = nil) -> URL {
    userFilesRootDirectory().appendingPathComponent(String(userId), isDirectory: true).appendingPathComponent(String(fileId) + "_" + (filename ?? ""), isDirectory: false)
}

private func ensureUserFilesRootExists() throws {
    let root = userFilesRootDirectory()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
}

private func normalizeLogicalFilename(_ raw: String) -> String? {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t.count <= 255 else { return nil }
    if t.contains("/") || t.contains("\\") || t.contains("\0") { return nil }
    if t == "." || t == ".." { return nil }
    return t
}

private func filterFilename(_ raw: String) -> String? {
    guard !raw.contains(".key") else {
        return nil
    }
    guard !raw.contains("passwd") else {
        return nil
    }
    guard !raw.contains("hosts") else {
        return nil
    }
    return raw
}

private func jsonBuffer<T: Encodable>(_ value: T) throws -> ByteBuffer {
    ByteBuffer(data: try JSONEncoder().encode(value))
}

public func InitFileRoutes() async {
    do {
        try ensureUserFilesRootExists()
    } catch {
        await ServiceStdio.shared.log("FileController: failed to create user files root: \(error)")
    }

    await server.on(path: "/api/files/list", method: "GET") { req in
        guard let session = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let rows = await DatabaseHelpers.listUserFiles(userID: session.userID) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        let items = rows.map {
            FilesListItemJSON(
                id: $0.id,
                name: $0.filename,
                size: $0.size_bytes,
                created_at: userFriendlyDateString($0.created_at)
            )
        }
        return Response(statusCode: 200, contentType: "application/json", data: try! jsonBuffer(FilesListResponse(ok: true, files: items, error: nil)))
    }

    await server.on(path: "/api/files/new", method: "POST") { req in
        guard let session = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: userFileNewBodyMaxBytes)
        if bodyLen == userFileNewBodyMaxBytes && req.readableBytes > 0 {
            return Response(statusCode: 400, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Body too large")))
        }
        let payload: FilesNewRequest
        do {
            payload = try JSONDecoder().decode(FilesNewRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        // let prefiltred = normalizeLogicalFilename(payload.filename), 
        guard let logicalName = filterFilename(payload.filename) else {
            return Response(statusCode: 400, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Invalid filename")))
        }
        let b64 = payload.filedata.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b64.isEmpty else {
            return Response(statusCode: 400, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Empty filedata")))
        }
        guard let raw = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]), !raw.isEmpty else {
            return Response(statusCode: 400, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Invalid base64")))
        }
        guard raw.count <= userFileMaxRawBytes else {
            return Response(statusCode: 400, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "File too large")))
        }

        if await DatabaseHelpers.userFileNameExists(userID: session.userID, filename: logicalName) {
            return Response(statusCode: 409, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Filename already exists")))
        }

        guard let fileId = await DatabaseHelpers.insertUserFile(userID: session.userID, filename: logicalName, sizeBytes: raw.count) else {
            if await DatabaseHelpers.userFileNameExists(userID: session.userID, filename: logicalName) {
                return Response(statusCode: 409, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Filename already exists")))
            }
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }

        let url = storageFileURL(userId: session.userID, fileId: fileId, filename: logicalName)
        let userDir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
            try raw.write(to: url, options: .atomic)
        } catch {
            _ = await DatabaseHelpers.deleteUserFileRow(fileId: fileId, userID: session.userID)
            try? FileManager.default.removeItem(at: url)
            return Response(statusCode: 500, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Failed to store file")))
        }

        return Response(statusCode: 200, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: true, error: nil)))
    }

    await server.on(path: "/api/files/get", method: "GET") { req in
        guard let session = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let idRaw = getQueryParam(req, key: "id"),
              let fileId = Int(idRaw), fileId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard let row = await DatabaseHelpers.getUserFileRow(fileId: fileId, userID: session.userID) else {
            return Response(statusCode: 404, contentType: "application/json", data: try! jsonBuffer(FilesGetResponse(ok: false, filedata: nil, error: "Not found")))
        }
        let url = storageFileURL(userId: session.userID, fileId: row.id, filename: row.filename)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return Response(statusCode: 404, contentType: "application/json", data: try! jsonBuffer(FilesGetResponse(ok: false, filedata: nil, error: "File missing on disk")))
        }
        let b64 = data.base64EncodedString()
        return Response(statusCode: 200, contentType: "application/json", data: try! jsonBuffer(FilesGetResponse(ok: true, filedata: b64, error: nil)))
    }

    await server.on(path: "/api/files/delete", method: "DELETE") { req in
        guard let session = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let idRaw = getQueryParam(req, key: "id"),
              let fileId = Int(idRaw), fileId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard let row = await DatabaseHelpers.getUserFileRow(fileId: fileId, userID: session.userID) else {
            return Response(statusCode: 404, contentType: "application/json", data: try! jsonBuffer(FilesGetResponse(ok: false, filedata: nil, error: "Not found")))
        }
        
        let url = storageFileURL(userId: session.userID, fileId: row.id, filename: row.filename)
        let deleted = await DatabaseHelpers.deleteUserFileRow(fileId: fileId, userID: session.userID)
        guard deleted else {
            return Response(statusCode: 404, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: false, error: "Not found")))
        }
        try? FileManager.default.removeItem(at: url)
        return Response(statusCode: 200, contentType: "application/json", data: try! jsonBuffer(FilesOkErrorResponse(ok: true, error: nil)))
    }
}
