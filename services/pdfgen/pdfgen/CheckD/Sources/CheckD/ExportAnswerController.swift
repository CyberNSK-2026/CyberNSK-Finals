//
//  ExportAnswerController.swift
//  CheckD
//
//  Сервисный снимок ответа для печати / export-answer.html — без сессии (защита снаружи, например whitelist).
//

import Foundation
import NIO
import FastCGI2

private struct ExportAnswerSnapshot: Codable {
    let id: Int
    let completed_at: String
}

private struct ExportAnswerChecklistPayload: Codable {
    let id: Int
    let name: String
    let description: String
}

private struct ExportAnswerAPISuccess: Codable {
    let ok: Bool
    let answer: ExportAnswerSnapshot
    let answered_by: ChecklistExportAnswerUser
    let checklist_author: ChecklistExportChecklistBy
    let checklist: ExportAnswerChecklistPayload
    let questions: [ChecklistGetQuestionResponse]
    let answers: [ChecklistAnswerEntry]
}

private struct ExportAnswerAPIError: Codable {
    let ok: Bool
    let error: String
}

private func exportAnswerUserBlock(userID: Int) async -> ChecklistExportAnswerUser {
    if let u = await DatabaseHelpers.getUser(id: userID) {
        return ChecklistExportAnswerUser(user_id: u.id, username: u.name)
    }
    return ChecklistExportAnswerUser(user_id: -1, username: "Unknown user")
}

private func exportChecklistAuthorBlock(authorID: Int) async -> ChecklistExportChecklistBy {
    if let u = await DatabaseHelpers.getUser(id: authorID) {
        return ChecklistExportChecklistBy(user_id: u.id, user_name: u.name)
    }
    return ChecklistExportChecklistBy(user_id: -1, user_name: "Unknown user")
}


public func InitExportRoutes() async {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]

    await server.on(path: "/api/export/answer", method: "GET") { req in
        guard let idRaw = getQueryParam(req, key: "id"),
              let answerId = Int(idRaw), answerId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ExportAnswerAPIError(
                ok: false,
                error: "Missing or invalid id"
            ))))
        }

        guard let record = await DatabaseHelpers.getChecklistAnswer(recordId: answerId) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ExportAnswerAPIError(
                ok: false,
                error: "Answer not found"
            ))))
        }

        guard let checklist = await DatabaseHelpers.getChecklist(id: record.checklist_id) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ExportAnswerAPIError(
                ok: false,
                error: "Checklist not found"
            ))))
        }

        guard let questions = await DatabaseHelpers.getChecklistQuestions(checklistID: checklist.id) else {
            return Response(statusCode: 500, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ExportAnswerAPIError(
                ok: false,
                error: "Failed to load questions"
            ))))
        }

        let mappedQuestions = questions.map { question in
            ChecklistGetQuestionResponse(
                id: question.id,
                q_name: question.name,
                title: question.title,
                description: question.description,
                q_type: question.type.apiValue,
                q_values: question.possible_answers
            )
        }

        let answeredBy = await exportAnswerUserBlock(userID: record.user_id)
        let checklistAuthor = await exportChecklistAuthorBlock(authorID: checklist.author_id)

        let body = ExportAnswerAPISuccess(
            ok: true,
            answer: ExportAnswerSnapshot(
                id: record.id,
                completed_at: userFriendlyDateString(record.created_at)
            ),
            answered_by: answeredBy,
            checklist_author: checklistAuthor,
            checklist: ExportAnswerChecklistPayload(
                id: checklist.id,
                name: checklist.title,
                description: checklist.description
            ),
            questions: mappedQuestions,
            answers: record.answers
        )

        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! encoder.encode(body)))
    }
}
