//
//  ListsController.swift
//  CheckD
//
//  Created by NeKoChan on 4/23/26.
//

import NIO
import Foundation
import FastCGI2

struct ChecklistQuestionRequest: Codable {
    let q_name: String
    let title: String
    let description: String
    let q_type: String
    let q_values: [String]?
}

struct CreateChecklistRequest: Codable {
    let name: String
    let description: String
    let is_public: Bool
    let is_hidden: Bool
    let questions: [ChecklistQuestionRequest]
}

struct UpdateChecklistQuestionsRequest: Codable {
    let id: Int
    let questions: [ChecklistQuestionRequest]
}

struct ListsActionResponse: Codable {
    let ok: Bool
    let checklist_id: Int?
    let error: String?
}

struct ChecklistGetQuestionResponse: Codable {
    let id: Int
    let q_name: String
    let title: String
    let description: String
    let q_type: String
    let q_values: [String]?
}

struct ChecklistOwnerResponse: Codable {
    let id: Int
    let username: String
}

struct ChecklistGetResponse: Codable {
    let id: Int
    let owner: ChecklistOwnerResponse
    let name: String
    let description: String
    let is_public: Bool
    let is_hidden: Bool
    let questions: [ChecklistGetQuestionResponse]
}

struct ChecklistGetEnvelopeResponse: Codable {
    let ok: Bool
    let checklist: ChecklistGetResponse?
}

struct CompleteChecklistRequest: Codable {
    let checklist_id: Int
    let answers: [ChecklistAnswerEntry]
}

struct ChecklistCompleteResponse: Codable {
    let ok: Bool
    let error: String?
}

struct ChecklistListItemResponse: Codable {
    let id: Int
    let owner: ChecklistOwnerResponse
    let name: String
    let description: String
    let is_public: Bool
    let is_hidden: Bool
    let created_at: String
    let questions: Int
    let times_completed: Int
}

struct ChecklistListPaginationResponse: Codable {
    let pages: Int
    let current: Int
}

struct ChecklistListResponse: Codable {
    let results: [ChecklistListItemResponse]
    let pagination: ChecklistListPaginationResponse
}

struct ChecklistExportAnswerUser: Codable {
    let user_id: Int
    let username: String
}

struct ChecklistExportChecklistBy: Codable {
    let user_id: Int
    let user_name: String
}

struct ChecklistExportChecklistBlock: Codable {
    let checklist_id: Int
    let checklist_name: String
    let checklist_by: ChecklistExportChecklistBy
}

struct ChecklistExportAnswerItem: Codable {
    let id: Int
    let user: ChecklistExportAnswerUser
    let checklist: ChecklistExportChecklistBlock
    let completed_at: String
}

struct ChecklistExportListResponse: Codable {
    let ok: Bool
    let answers: [ChecklistExportAnswerItem]
    let pagination: ChecklistListPaginationResponse
}

private func parseUserPage(_ req: Request) -> Int {
    guard let pageRaw = getQueryParam(req, key: "page"),
          let page = Int(pageRaw), page > 0 else {
        return 1
    }
    return page
}

private func canUserReadChecklist(session: SessionData, checklist: Checklist) -> Bool {
    if session.userRole == 1 {
        return true
    }
    return checklist.author_id == session.userID || checklist.is_public
}

private func validateCompleteAnswers(questions: [ChecklistQuestion], entries: [ChecklistAnswerEntry]) -> String? {
    let dbIds = Set(questions.map(\.id))
    let submittedIds = entries.map(\.question_id)
    if submittedIds.count != Set(submittedIds).count {
        return "duplicate question_id in answers"
    }
    if Set(submittedIds) != dbIds {
        let foreign = Set(submittedIds).subtracting(dbIds)
        if !foreign.isEmpty {
            return "unknown question_id for this checklist"
        }
        return "not all questions answered"
    }
    let byId = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
    for entry in entries {
        guard let question = byId[entry.question_id] else {
            return "unknown question_id for this checklist"
        }
        if let err = validateAnswersForQuestion(question, answers: entry.answers) {
            return err
        }
    }
    return nil
}

private func validateAnswersForQuestion(_ question: ChecklistQuestion, answers: [String]) -> String? {
    guard !answers.isEmpty else {
        return "empty answers for question"
    }
    let allowed = question.possible_answers
    let hasAllowedList = !(allowed?.isEmpty ?? true)
    
    switch question.type {
    case .bool:
        if hasAllowedList, let opts = allowed {
            for a in answers where !opts.contains(a) {
                return "invalid answer for question type"
            }
        } else {
            let norm = Set(["yes", "no", "true", "false"])
            for a in answers where !norm.contains(a.lowercased()) {
                return "invalid answer for question type"
            }
        }
    case .text:
        for a in answers where a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "empty text answer"
        }
    case .single:
        guard answers.count == 1 else {
            return "single choice requires exactly one answer"
        }
        if hasAllowedList, let opts = allowed {
            guard opts.contains(answers[0]) else {
                return "answer not in allowed options"
            }
        }
    case .multi:
        if hasAllowedList, let opts = allowed {
            let set = Set(opts)
            for a in answers where !set.contains(a) {
                return "answer not in allowed options"
            }
        }
    }
    return nil
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

private func resolveOwnerResponse(_ ownerID: Int) async -> ChecklistOwnerResponse {
    if let ownerUser = await DatabaseHelpers.getUser(id: ownerID) {
        return ChecklistOwnerResponse(id: ownerUser.id, username: ownerUser.name)
    }
    return ChecklistOwnerResponse(id: -1, username: "Unknown user")
}

private func buildQuestions(_ questions: [ChecklistQuestionRequest], checklistID: Int) -> [ChecklistQuestion]? {
    var output: [ChecklistQuestion] = []
    for question in questions {
        guard let qType = ChecklistQuestionType(apiValue: question.q_type) else {
            return nil
        }
        output.append(ChecklistQuestion(
            id: 0,
            name: question.q_name,
            title: escapeHTML(question.title),
            description: escapeHTML(question.description),
            type: qType,
            possible_answers: question.q_values,
            checklist_id: checklistID
        ))
    }
    return output
}

public func InitListsRoutes() async {
    await server.on(path: "/api/user/checklists", method: "POST") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BodyTooLarge)
        }
        
        let reqData: CreateChecklistRequest
        do {
            reqData = try JSONDecoder().decode(CreateChecklistRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        
        guard var questions = buildQuestions(reqData.questions, checklistID: 0) else {
            return Response(statusCode: 400, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ListsActionResponse(
                ok: false,
                checklist_id: nil,
                error: "Unknown question type"
            ))))
        }
        
        var checklist = Checklist(
            id: 0,
            title: escapeHTML(reqData.name),
            description: escapeHTML(reqData.description),
            author_id: sessionData.userID,
            is_hidden: reqData.is_hidden,
            is_public: reqData.is_public,
            created_at: Date(timeIntervalSince1970: 0)
        )
        
        guard let created = await DatabaseHelpers.createChecklist(checklist: &checklist) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        guard created else {
            return Response(statusCode: 409, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ListsActionResponse(
                ok: false,
                checklist_id: nil,
                error: "Checklist with this name already exists"
            ))))
        }
        
        for idx in questions.indices {
            questions[idx] = ChecklistQuestion(
                id: 0,
                name: questions[idx].name,
                title: questions[idx].title,
                description: questions[idx].description,
                type: questions[idx].type,
                possible_answers: questions[idx].possible_answers,
                checklist_id: checklist.id
            )
        }
        
        let createdQuestions = await DatabaseHelpers.createChecklistQuestions(questions: &questions, checklistID: checklist.id)
        guard createdQuestions else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ListsActionResponse(
            ok: true,
            checklist_id: checklist.id,
            error: nil
        ))))
    }
    
    await server.on(path: "/api/user/checklists", method: "PUT") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BodyTooLarge)
        }
        
        let reqData: UpdateChecklistQuestionsRequest
        do {
            reqData = try JSONDecoder().decode(UpdateChecklistQuestionsRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        
        guard let checklist = await DatabaseHelpers.getChecklist(id: reqData.id) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ListsActionResponse(
                ok: false,
                checklist_id: nil,
                error: "Checklist not found"
            ))))
        }
        
        guard sessionData.userRole == 1 || checklist.author_id == sessionData.userID else {
            return Response(statusCode: 403, contentType: "application/json", data: StaticAnswers.Forbidden)
        }
        
        guard var questions = buildQuestions(reqData.questions, checklistID: checklist.id) else {
            return Response(statusCode: 400, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ListsActionResponse(
                ok: false,
                checklist_id: nil,
                error: "Unknown question type"
            ))))
        }
        
        let updated = await DatabaseHelpers.updateChecklistQuestions(checklistID: checklist.id, questions: &questions)
        guard updated else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ListsActionResponse(
            ok: true,
            checklist_id: checklist.id,
            error: nil
        ))))
    }
    
    await server.on(path: "/api/checklists/get", method: "GET") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let idRaw = getQueryParam(req, key: "id"),
              let checklistID = Int(idRaw), checklistID > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        
        guard let checklist = await DatabaseHelpers.getChecklist(id: checklistID) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistGetEnvelopeResponse(
                ok: false,
                checklist: nil
            ))))
        }
        
        guard canUserReadChecklist(session: sessionData, checklist: checklist) else {
            return Response(statusCode: 403, contentType: "application/json", data: StaticAnswers.Forbidden)
        }
        
        guard let questions = await DatabaseHelpers.getChecklistQuestions(checklistID: checklistID) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
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
        let ownerResponse = await resolveOwnerResponse(checklist.author_id)
        
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistGetEnvelopeResponse(
            ok: true,
            checklist: ChecklistGetResponse(
                id: checklist.id,
                owner: ownerResponse,
                name: checklist.title,
                description: checklist.description,
                is_public: checklist.is_public,
                is_hidden: checklist.is_hidden,
                questions: mappedQuestions
            )
        ))))
    }
    
    await server.on(path: "/api/checklists/complete", method: "POST") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BodyTooLarge)
        }
        let reqData: CompleteChecklistRequest
        do {
            reqData = try JSONDecoder().decode(CompleteChecklistRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard reqData.checklist_id > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard let checklist = await DatabaseHelpers.getChecklist(id: reqData.checklist_id) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "Checklist not found"
            ))))
        }
        guard canUserReadChecklist(session: sessionData, checklist: checklist) else {
            return Response(statusCode: 403, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "Forbidden"
            ))))
        }
        guard let questions = await DatabaseHelpers.getChecklistQuestions(checklistID: reqData.checklist_id) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        if let err = validateCompleteAnswers(questions: questions, entries: reqData.answers) {
            return Response(statusCode: 400, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: err
            ))))
        }
        let saved = await DatabaseHelpers.saveChecklistAnswers(
            userID: sessionData.userID,
            checklistID: reqData.checklist_id,
            entries: reqData.answers
        )
        guard saved else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
            ok: true,
            error: nil
        ))))
    }
    
    await server.on(path: "/api/checklists/export-list", method: "GET") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        let page = parseUserPage(req)
        let pageSize = 50
        let offset = (page - 1) * pageSize
        let isAdmin = sessionData.userRole == 1
        guard let dataPage = await DatabaseHelpers.listChecklistAnswers(
            isAdmin: isAdmin,
            authorUserID: sessionData.userID,
            pageSize: pageSize,
            offset: offset
        ) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        var answers: [ChecklistExportAnswerItem] = []
        for row in dataPage.items {
            let userBlock = await exportAnswerUserBlock(userID: row.user_id)
            if let cl = await DatabaseHelpers.getChecklist(id: row.checklist_id) {
                let authorBlock = await exportChecklistAuthorBlock(authorID: cl.author_id)
                answers.append(ChecklistExportAnswerItem(
                    id: row.id,
                    user: userBlock,
                    checklist: ChecklistExportChecklistBlock(
                        checklist_id: cl.id,
                        checklist_name: cl.title,
                        checklist_by: authorBlock
                    ),
                    completed_at: userFriendlyDateString(row.created_at)
                ))
            } else {
                answers.append(ChecklistExportAnswerItem(
                    id: row.id,
                    user: userBlock,
                    checklist: ChecklistExportChecklistBlock(
                        checklist_id: row.checklist_id,
                        checklist_name: "Unknown checklist",
                        checklist_by: ChecklistExportChecklistBy(user_id: -1, user_name: "Unknown user")
                    ),
                    completed_at: userFriendlyDateString(row.created_at)
                ))
            }
        }
        let totalPages = max(1, (dataPage.total + pageSize - 1) / pageSize)
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistExportListResponse(
            ok: true,
            answers: answers,
            pagination: ChecklistListPaginationResponse(pages: totalPages, current: page)
        ))))
    }
    
    await server.on(path: "/api/checklists/delete-answer", method: "DELETE") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let idRaw = getQueryParam(req, key: "id"),
              let recordId = Int(idRaw), recordId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard let record = await DatabaseHelpers.getChecklistAnswer(recordId: recordId) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "Answer not found"
            ))))
        }
        guard sessionData.userRole == 1 || record.user_id == sessionData.userID else {
            return Response(statusCode: 403, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "Forbidden"
            ))))
        }
        guard await DatabaseHelpers.deleteChecklistAnswer(recordId: recordId) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
            ok: true,
            error: nil
        ))))
    }
    
    await server.on(path: "/api/checklists/delete", method: "DELETE") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let idRaw = getQueryParam(req, key: "id"),
              let checklistId = Int(idRaw), checklistId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard let checklist = await DatabaseHelpers.getChecklist(id: checklistId) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "Checklist not found"
            ))))
        }
        guard sessionData.userRole == 1 || checklist.author_id == sessionData.userID else {
            return Response(statusCode: 403, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "Forbidden"
            ))))
        }
        guard await DatabaseHelpers.deleteChecklist(id: checklistId) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
            ok: true,
            error: nil
        ))))
    }
    
    await server.on(path: "/api/checklists/list", method: "GET") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        
        let page = parseUserPage(req)
        let pageSize = 50
        let offset = (page - 1) * pageSize
        
        let dataPage: ChecklistListPage?
        if sessionData.userRole == 1 {
            dataPage = await DatabaseHelpers.adminListChecklists(pageSize: pageSize, offset: offset)
        } else {
            dataPage = await DatabaseHelpers.listChecklists(hidden: false, ownerID: sessionData.userID, pageSize: pageSize, offset: offset)
        }
        
        guard let dataPage else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        
        let totalPages = max(1, (dataPage.total + pageSize - 1) / pageSize)
        var items: [ChecklistListItemResponse] = []
        for checklist in dataPage.items {
            guard let questionsCount = await DatabaseHelpers.getChecklistQuestionsCount(checklistID: checklist.id),
                  let timesCompletedCount = await DatabaseHelpers.getChecklistTimesCompletedCount(checklistID: checklist.id) else {
                return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
            }
            let ownerResponse = await resolveOwnerResponse(checklist.author_id)
            items.append(ChecklistListItemResponse(
                id: checklist.id,
                owner: ownerResponse,
                name: checklist.title,
                description: checklist.description,
                is_public: checklist.is_public,
                is_hidden: checklist.is_hidden,
                created_at: userFriendlyDateString(checklist.created_at),
                questions: questionsCount,
                times_completed: timesCompletedCount
            ))
        }
        
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistListResponse(
            results: items,
            pagination: ChecklistListPaginationResponse(pages: totalPages, current: page)
        ))))
    }
    
    await server.on(path: "/api/checklists/list-by-user", method: "GET") { req in
        guard await parseAuthorizedSession(req) != nil else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let userIdRaw = getQueryParam(req, key: "userid"),
              let authorUserId = Int(userIdRaw), authorUserId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard await DatabaseHelpers.getUser(id: authorUserId) != nil else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistCompleteResponse(
                ok: false,
                error: "User not found"
            ))))
        }
        let pageSize = 50
        guard let dataPage = await DatabaseHelpers.listPublicChecklistsByAuthor(authorID: authorUserId, limit: pageSize) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        let totalPages = max(1, (dataPage.total + pageSize - 1) / pageSize)
        var items: [ChecklistListItemResponse] = []
        for checklist in dataPage.items {
            guard let questionsCount = await DatabaseHelpers.getChecklistQuestionsCount(checklistID: checklist.id),
                  let timesCompletedCount = await DatabaseHelpers.getChecklistTimesCompletedCount(checklistID: checklist.id) else {
                return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
            }
            let ownerResponse = await resolveOwnerResponse(checklist.author_id)
            items.append(ChecklistListItemResponse(
                id: checklist.id,
                owner: ownerResponse,
                name: checklist.title,
                description: checklist.description,
                is_public: checklist.is_public,
                is_hidden: checklist.is_hidden,
                created_at: userFriendlyDateString(checklist.created_at),
                questions: questionsCount,
                times_completed: timesCompletedCount
            ))
        }
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistListResponse(
            results: items,
            pagination: ChecklistListPaginationResponse(pages: totalPages, current: 1)
        ))))
    }
    
    await server.on(path: "/api/checklists/editable-list", method: "GET") { req in
        guard let sessionData = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        
        let page = parseUserPage(req)
        let pageSize = 50
        let offset = (page - 1) * pageSize
        
        guard let dataPage = await DatabaseHelpers.listOwnerChecklists(ownerID: sessionData.userID, includeHidden: true, pageSize: pageSize, offset: offset) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        
        let totalPages = max(1, (dataPage.total + pageSize - 1) / pageSize)
        var items: [ChecklistListItemResponse] = []
        for checklist in dataPage.items {
            guard let questionsCount = await DatabaseHelpers.getChecklistQuestionsCount(checklistID: checklist.id),
                  let timesCompletedCount = await DatabaseHelpers.getChecklistTimesCompletedCount(checklistID: checklist.id) else {
                return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
            }
            let ownerResponse = await resolveOwnerResponse(checklist.author_id)
            items.append(ChecklistListItemResponse(
                id: checklist.id,
                owner: ownerResponse,
                name: checklist.title,
                description: checklist.description,
                is_public: checklist.is_public,
                is_hidden: checklist.is_hidden,
                created_at: userFriendlyDateString(checklist.created_at),
                questions: questionsCount,
                times_completed: timesCompletedCount
            ))
        }
        
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(ChecklistListResponse(
            results: items,
            pagination: ChecklistListPaginationResponse(pages: totalPages, current: page)
        ))))
    }
}
