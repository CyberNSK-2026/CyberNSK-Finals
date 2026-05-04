//
//  DatabaseHelpers.swift
//  CheckD
//
//  Created by NeKoChan on 4/23/26.
//

import PostgresNIO
import Foundation

public struct User: Codable {
    let id: Int
    let name: String
    let email: String
    let role: Int
    let last_auth_at: Date
}

public struct Checklist: Codable {
    let id: Int
    let title: String
    let description: String
    let author_id: Int
    let is_hidden: Bool
    let is_public: Bool
    let created_at: Date
}

public struct ChecklistListPage: Codable {
    let total: Int
    let current_offset: Int
    let page_size: Int
    let items: [Checklist]
}

/// Строка из `checklist_answers` для списка / экспорта (без тела JSON `answers`).
public struct ChecklistAnswerListItem: Codable {
    public let id: Int
    public let checklist_id: Int
    public let user_id: Int
    public let created_at: Date
}

public struct ChecklistAnswerListPage: Codable {
    public let total: Int
    public let current_offset: Int
    public let page_size: Int
    public let items: [ChecklistAnswerListItem]
}

/// Одна строка `checklist_answers` по `id` записи (включая распарсенный JSON `answers`).
public struct ChecklistAnswerRecord: Codable {
    public let id: Int
    public let user_id: Int
    public let checklist_id: Int
    public let created_at: Date
    public let answers: [ChecklistAnswerEntry]
}

public enum ChecklistQuestionType: Int, Codable {
    case bool = 1
    case single = 2
    case multi = 3
    case text = 4
    
    init?(apiValue: String) {
        switch apiValue.lowercased() {
        case "bool":
            self = .bool
        case "single":
            self = .single
        case "multi":
            self = .multi
        case "text":
            self = .text
        default:
            return nil
        }
    }
    
    var apiValue: String {
        switch self {
        case .bool:
            return "bool"
        case .single:
            return "single"
        case .multi:
            return "multi"
        case .text:
            return "text"
        }
    }
}

public struct ChecklistQuestion: Codable {
    let id: Int
    let name: String
    let title: String
    let description: String
    let type: ChecklistQuestionType
    let possible_answers: [String]?
    let checklist_id: Int
}

/// Одна запись в JSON-массиве `checklist_answers.answers`.
public struct ChecklistAnswerEntry: Codable {
    public let question_id: Int
    public let answers: [String]
}

/// Метаданные файла пользователя (`user_files`); содержимое — на диске у API.
public struct UserFileRow: Codable {
    public let id: Int
    public let user_id: Int
    public let filename: String
    public let size_bytes: Int
    public let created_at: Date
}

public final class DatabaseHelpers {
    public static func tryLoginUser(email: String, password: String) async -> Int? {
        guard let result = try? await database.query("SELECT id FROM users WHERE email = \(email) AND password_hash = hash_sha256(\(password))") else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        if !rows.isEmpty {
            guard let user_id = try? rows.first?.decode(Int.self) else {
                return nil
            }
            return user_id
        }
        return -1
    }
    
    public static func createUser(user: inout User, password: String) async -> Bool? {
        guard let res0 = try? await database.query("SELECT id FROM users WHERE email = \(user.email)") else {
            return nil
        }
        guard let isEmpty = (try? await res0.collect())?.isEmpty else {
            return nil
        }
        guard isEmpty else {
            return false
        }
        let safeName = user.name
        guard let userRowRes = try? await database.query("INSERT INTO users (name, email, role, password_hash, last_auth_at) VALUES (\(safeName), \(user.email), \(user.role), hash_sha256(\(password)), \(Date(timeIntervalSince1970: 0))) RETURNING id") else {
            return nil
        }
        guard let userRow = try? await userRowRes.collect().first else {
            return nil
        }
        if let user_id = try? userRow.decode(Int.self) {
            user = User(id: user_id, name: safeName, email: user.email, role: user.role, last_auth_at: Date(timeIntervalSince1970: 0))
            return true
        }
        return nil
    }
    
    public static func getUser(id: Int) async -> User? {
        guard let result = try? await database.query("SELECT id, name, email, role, last_auth_at FROM users WHERE id = \(id)") else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        if !rows.isEmpty {
            guard let user = try? rows.first?.decode((Int,String,String,Int,Date).self) else {
                return nil
            }
            return User(id: user.0, name: user.1, email: user.2, role: user.3, last_auth_at: user.4)
        }
        return nil
    }
    
    public static func updateUser(user: User) async -> Bool {
        guard let _ = try? await database.query("UPDATE users SET name = \(user.name), email = \(user.email), last_auth_at = \(user.last_auth_at), role = \(user.role) WHERE id = \(user.id)") else {
            return false
        }
        return true
    }
    
    public static func createChecklist(checklist: inout Checklist) async -> Bool? {
        guard let res0 = try? await database.query("SELECT id FROM checklists WHERE author_id = \(checklist.author_id) AND title = \(checklist.title)") else {
            return nil
        }
        guard let isEmpty = (try? await res0.collect())?.isEmpty else {
            return nil
        }
        guard isEmpty else {
            return false
        }
        guard let checklistRowRes = try? await database.query("INSERT INTO checklists (title, description, author_id, is_hidden, is_public) VALUES (\(checklist.title), \(checklist.description), \(checklist.author_id), \(checklist.is_hidden), \(checklist.is_public)) RETURNING id, created_at") else {
            return nil
        }
        guard let checklistRow = try? await checklistRowRes.collect().first else {
            return nil
        }
        if let checklistData = try? checklistRow.decode((Int, Date).self) {
            checklist = Checklist(
                id: checklistData.0,
                title: checklist.title,
                description: checklist.description,
                author_id: checklist.author_id,
                is_hidden: checklist.is_hidden,
                is_public: checklist.is_public,
                created_at: checklistData.1
            )
            return true
        }
        return nil
    }
    
    public static func createChecklistQuestions(questions: inout [ChecklistQuestion], checklistID: Int) async -> Bool {
        var createdQuestions: [ChecklistQuestion] = []
        for question in questions {
            let questionRowRes: PostgresRowSequence?
            if let possibleAnswers = question.possible_answers {
                guard let encodedData = try? JSONEncoder().encode(possibleAnswers),
                      let possibleAnswersJSON = String(data: encodedData, encoding: .utf8) else {
                    return false
                }
                questionRowRes = try? await database.query("INSERT INTO checklist_questions (name, title, description, type, possible_answers, checklist_id) VALUES (\(question.name), \(question.title), \(question.description), \(question.type.rawValue), \(possibleAnswersJSON)::jsonb, \(checklistID)) RETURNING id")
            } else {
                questionRowRes = try? await database.query("INSERT INTO checklist_questions (name, title, description, type, possible_answers, checklist_id) VALUES (\(question.name), \(question.title), \(question.description), \(question.type.rawValue), NULL, \(checklistID)) RETURNING id")
            }
            guard let questionRowRes else {
                return false
            }
            guard let questionRow = try? await questionRowRes.collect().first else {
                return false
            }
            guard let questionID = try? questionRow.decode(Int.self) else {
                return false
            }
            createdQuestions.append(ChecklistQuestion(
                id: questionID,
                name: question.name,
                title: question.title,
                description: question.description,
                type: question.type,
                possible_answers: question.possible_answers,
                checklist_id: checklistID
            ))
        }
        questions = createdQuestions
        return true
    }
    
    public static func getChecklist(id: Int) async -> Checklist? {
        guard let result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE id = \(id)") else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        if !rows.isEmpty {
            guard let checklist = try? rows.first?.decode((Int, String, String, Int, Bool, Bool, Date).self) else {
                return nil
            }
            return Checklist(
                id: checklist.0,
                title: checklist.1,
                description: checklist.2,
                author_id: checklist.3,
                is_hidden: checklist.4,
                is_public: checklist.5,
                created_at: checklist.6
            )
        }
        return nil
    }
    
    public static func getChecklistQuestions(checklistID: Int) async -> [ChecklistQuestion]? {
        guard let result = try? await database.query("SELECT id, name, title, description, type, possible_answers::text, checklist_id FROM checklist_questions WHERE checklist_id = \(checklistID) ORDER BY id ASC") else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        
        var questions: [ChecklistQuestion] = []
        for row in rows {
            guard let question = try? row.decode((Int, String, String, String, Int, String?, Int).self),
                  let questionType = ChecklistQuestionType(rawValue: question.4) else {
                return nil
            }
            var decodedPossibleAnswers: [String]? = nil
            if let possibleAnswersJSON = question.5 {
                guard let jsonData = possibleAnswersJSON.data(using: .utf8),
                      let possibleAnswers = try? JSONDecoder().decode([String].self, from: jsonData) else {
                    return nil
                }
                decodedPossibleAnswers = possibleAnswers
            }
            questions.append(ChecklistQuestion(
                id: question.0,
                name: question.1,
                title: question.2,
                description: question.3,
                type: questionType,
                possible_answers: decodedPossibleAnswers,
                checklist_id: question.6
            ))
        }
        return questions
    }
    
    public static func updateChecklistQuestions(checklistID: Int, questions: inout [ChecklistQuestion]) async -> Bool {
        guard let _ = try? await database.query("DELETE FROM checklist_questions WHERE checklist_id = \(checklistID)") else {
            return false
        }
        return await createChecklistQuestions(questions: &questions, checklistID: checklistID)
    }
    
    public static func listChecklists(hidden: Bool, ownerID: Int?, pageSize: Int = 50, offset: Int = 0) async -> ChecklistListPage? {
        let safePageSize = min(max(pageSize, 1), 200)
        let safeOffset = max(offset, 0)
        
        let totalRes: PostgresRowSequence?
        let result: PostgresRowSequence?
        if let ownerID {
            if hidden {
                totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE (is_public = TRUE OR author_id = \(ownerID))")
                result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE (is_public = TRUE OR author_id = \(ownerID)) ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
            } else {
                totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE (is_public = TRUE OR author_id = \(ownerID)) AND is_hidden = FALSE")
                result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE (is_public = TRUE OR author_id = \(ownerID)) AND is_hidden = FALSE ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
            }
        } else {
            if hidden {
                totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE is_public = TRUE")
                result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE is_public = TRUE ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
            } else {
                totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE is_public = TRUE AND is_hidden = FALSE")
                result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE is_public = TRUE AND is_hidden = FALSE ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
            }
        }
        
        guard let totalRes else {
            return nil
        }
        guard let totalRows = try? await totalRes.collect(),
              let totalRow = totalRows.first,
              let total = try? totalRow.decode(Int.self) else {
            return nil
        }
        
        guard let result else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        
        var items: [Checklist] = []
        for row in rows {
            guard let checklist = try? row.decode((Int, String, String, Int, Bool, Bool, Date).self) else {
                return nil
            }
            items.append(Checklist(
                id: checklist.0,
                title: checklist.1,
                description: checklist.2,
                author_id: checklist.3,
                is_hidden: checklist.4,
                is_public: checklist.5,
                created_at: checklist.6
            ))
        }
        
        return ChecklistListPage(
            total: total,
            current_offset: safeOffset,
            page_size: safePageSize,
            items: items
        )
    }
    
    /// Публичные и не скрытые чеклисты автора `authorID`, последние до `limit` записей (сортировка `id DESC`, offset 0).
    public static func listPublicChecklistsByAuthor(authorID: Int, limit: Int = 50) async -> ChecklistListPage? {
        let safeLimit = min(max(limit, 1), 200)
        
        guard let totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE author_id = \(authorID) AND is_public = TRUE AND is_hidden = FALSE") else {
            return nil
        }
        guard let totalRows = try? await totalRes.collect(),
              let totalRow = totalRows.first,
              let total = try? totalRow.decode(Int.self) else {
            return nil
        }
        
        guard let result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE author_id = \(authorID) AND is_public = TRUE AND is_hidden = FALSE ORDER BY id DESC LIMIT \(safeLimit) OFFSET 0") else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        
        var items: [Checklist] = []
        for row in rows {
            guard let checklist = try? row.decode((Int, String, String, Int, Bool, Bool, Date).self) else {
                return nil
            }
            items.append(Checklist(
                id: checklist.0,
                title: checklist.1,
                description: checklist.2,
                author_id: checklist.3,
                is_hidden: checklist.4,
                is_public: checklist.5,
                created_at: checklist.6
            ))
        }
        
        return ChecklistListPage(
            total: total,
            current_offset: 0,
            page_size: safeLimit,
            items: items
        )
    }
    
    public static func adminListChecklists(pageSize: Int = 50, offset: Int = 0) async -> ChecklistListPage? {
        let safePageSize = min(max(pageSize, 1), 200)
        let safeOffset = max(offset, 0)
        
        guard let totalRes = try? await database.query("SELECT COUNT(*) FROM checklists") else {
            return nil
        }
        guard let totalRows = try? await totalRes.collect(),
              let totalRow = totalRows.first,
              let total = try? totalRow.decode(Int.self) else {
            return nil
        }
        
        guard let result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)") else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        
        var items: [Checklist] = []
        for row in rows {
            guard let checklist = try? row.decode((Int, String, String, Int, Bool, Bool, Date).self) else {
                return nil
            }
            items.append(Checklist(
                id: checklist.0,
                title: checklist.1,
                description: checklist.2,
                author_id: checklist.3,
                is_hidden: checklist.4,
                is_public: checklist.5,
                created_at: checklist.6
            ))
        }
        
        return ChecklistListPage(
            total: total,
            current_offset: safeOffset,
            page_size: safePageSize,
            items: items
        )
    }
    
    public static func listOwnerChecklists(ownerID: Int, includeHidden: Bool, pageSize: Int = 50, offset: Int = 0) async -> ChecklistListPage? {
        let safePageSize = min(max(pageSize, 1), 200)
        let safeOffset = max(offset, 0)
        
        let totalRes: PostgresRowSequence?
        let result: PostgresRowSequence?
        if includeHidden {
            totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE author_id = \(ownerID)")
            result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE author_id = \(ownerID) ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
        } else {
            totalRes = try? await database.query("SELECT COUNT(*) FROM checklists WHERE author_id = \(ownerID) AND is_hidden = FALSE")
            result = try? await database.query("SELECT id, title, description, author_id, is_hidden, is_public, created_at FROM checklists WHERE author_id = \(ownerID) AND is_hidden = FALSE ORDER BY id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
        }
        
        guard let totalRes else {
            return nil
        }
        guard let totalRows = try? await totalRes.collect(),
              let totalRow = totalRows.first,
              let total = try? totalRow.decode(Int.self) else {
            return nil
        }
        
        guard let result else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        
        var items: [Checklist] = []
        for row in rows {
            guard let checklist = try? row.decode((Int, String, String, Int, Bool, Bool, Date).self) else {
                return nil
            }
            items.append(Checklist(
                id: checklist.0,
                title: checklist.1,
                description: checklist.2,
                author_id: checklist.3,
                is_hidden: checklist.4,
                is_public: checklist.5,
                created_at: checklist.6
            ))
        }
        
        return ChecklistListPage(
            total: total,
            current_offset: safeOffset,
            page_size: safePageSize,
            items: items
        )
    }
    
    public static func getChecklistQuestionsCount(checklistID: Int) async -> Int? {
        guard let result = try? await database.query("SELECT COUNT(*) FROM checklist_questions WHERE checklist_id = \(checklistID)") else {
            return nil
        }
        guard let rows = try? await result.collect(),
              let row = rows.first,
              let count = try? row.decode(Int.self) else {
            return nil
        }
        return count
    }
    
    public static func getChecklistTimesCompletedCount(checklistID: Int) async -> Int? {
        guard let result = try? await database.query("SELECT COUNT(*) FROM checklist_answers WHERE checklist_id = \(checklistID)") else {
            return nil
        }
        guard let rows = try? await result.collect(),
              let row = rows.first,
              let count = try? row.decode(Int.self) else {
            return nil
        }
        return count
    }
    
    /// Сохраняет ответы пользователя по чеклисту в `checklist_answers` (`answers` — JSONB-массив записей `question_id` + `answers`).
    public static func saveChecklistAnswers(userID: Int, checklistID: Int, entries: [ChecklistAnswerEntry]) async -> Bool {
        guard let encodedData = try? JSONEncoder().encode(entries),
              let answersJSON = String(data: encodedData, encoding: .utf8) else {
            return false
        }
        guard let _ = try? await database.query("INSERT INTO checklist_answers (user_id, checklist_id, answers) VALUES (\(userID), \(checklistID), \(answersJSON)::jsonb)") else {
            return false
        }
        return true
    }
    
    /// Пагинированный список завершений чеклистов: админ видит все; обычный пользователь — только ответы по чеклистам, где он `author_id`.
    public static func listChecklistAnswers(isAdmin: Bool, authorUserID: Int, pageSize: Int = 50, offset: Int = 0) async -> ChecklistAnswerListPage? {
        let safePageSize = min(max(pageSize, 1), 200)
        let safeOffset = max(offset, 0)
        
        let totalRes: PostgresRowSequence?
        let result: PostgresRowSequence?
        if isAdmin {
            totalRes = try? await database.query("SELECT COUNT(*) FROM checklist_answers")
            result = try? await database.query("SELECT ca.id, ca.checklist_id, ca.user_id, ca.created_at FROM checklist_answers ca ORDER BY ca.id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
        } else {
            totalRes = try? await database.query("SELECT COUNT(*) FROM checklist_answers ca INNER JOIN checklists c ON c.id = ca.checklist_id WHERE c.author_id = \(authorUserID)")
            result = try? await database.query("SELECT ca.id, ca.checklist_id, ca.user_id, ca.created_at FROM checklist_answers ca INNER JOIN checklists c ON c.id = ca.checklist_id WHERE c.author_id = \(authorUserID) ORDER BY ca.id DESC LIMIT \(safePageSize) OFFSET \(safeOffset)")
        }
        
        guard let totalRes else {
            return nil
        }
        guard let totalRows = try? await totalRes.collect(),
              let totalRow = totalRows.first,
              let total = try? totalRow.decode(Int.self) else {
            return nil
        }
        
        guard let result else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        
        var items: [ChecklistAnswerListItem] = []
        for row in rows {
            guard let rowData = try? row.decode((Int, Int, Int, Date).self) else {
                return nil
            }
            items.append(ChecklistAnswerListItem(
                id: rowData.0,
                checklist_id: rowData.1,
                user_id: rowData.2,
                created_at: rowData.3
            ))
        }
        
        return ChecklistAnswerListPage(
            total: total,
            current_offset: safeOffset,
            page_size: safePageSize,
            items: items
        )
    }
    
    /// Одна запись ответа пользователя по `id` строки в `checklist_answers`.
    public static func getChecklistAnswer(recordId: Int) async -> ChecklistAnswerRecord? {
        guard let result = try? await database.query("SELECT id, user_id, checklist_id, answers::text, created_at FROM checklist_answers WHERE id = \(recordId)") else {
            return nil
        }
        guard let rows = try? await result.collect(), !rows.isEmpty else {
            return nil
        }
        guard let row = try? rows.first?.decode((Int, Int, Int, String?, Date).self) else {
            return nil
        }
        let answersJSON = row.3 ?? "[]"
        guard let data = answersJSON.data(using: .utf8),
              let entries = try? JSONDecoder().decode([ChecklistAnswerEntry].self, from: data) else {
            return nil
        }
        return ChecklistAnswerRecord(
            id: row.0,
            user_id: row.1,
            checklist_id: row.2,
            created_at: row.4,
            answers: entries
        )
    }
    
    /// Удалить запись ответа пользователя в `checklist_answers` по `id` строки.
    public static func deleteChecklistAnswer(recordId: Int) async -> Bool {
        guard let _ = try? await database.query("DELETE FROM checklist_answers WHERE id = \(recordId)") else {
            return false
        }
        return true
    }
    
    /// Удалить чеклист по `id`. Связанные `checklist_questions` и `checklist_answers` удаляются каскадом (`ON DELETE CASCADE` в схеме).
    public static func deleteChecklist(id: Int) async -> Bool {
        guard let _ = try? await database.query("DELETE FROM checklists WHERE id = \(id)") else {
            return false
        }
        return true
    }

    // MARK: - User files (metadata only; bytes on disk)

    /// Все файлы пользователя, новые сверху.
    public static func listUserFiles(userID: Int) async -> [UserFileRow]? {
        guard let result = try? await database.query(
            "SELECT id, user_id, filename, size_bytes, created_at FROM user_files WHERE user_id = \(userID) ORDER BY id DESC"
        ) else {
            return nil
        }
        guard let rows = try? await result.collect() else {
            return nil
        }
        var out: [UserFileRow] = []
        for row in rows {
            guard let r = try? row.decode((Int, Int, String, Int64, Date).self) else {
                return nil
            }
            out.append(UserFileRow(
                id: r.0,
                user_id: r.1,
                filename: r.2,
                size_bytes: Int(r.3),
                created_at: r.4
            ))
        }
        return out
    }

    /// Одна строка, только если владелец `userID`.
    public static func getUserFileRow(fileId: Int, userID: Int) async -> UserFileRow? {
        guard let result = try? await database.query(
            "SELECT id, user_id, filename, size_bytes, created_at FROM user_files WHERE id = \(fileId) AND user_id = \(userID)"
        ) else {
            return nil
        }
        guard let rows = try? await result.collect(), let row = rows.first else {
            return nil
        }
        guard let r = try? row.decode((Int, Int, String, Int64, Date).self) else {
            return nil
        }
        return UserFileRow(
            id: r.0,
            user_id: r.1,
            filename: r.2,
            size_bytes: Int(r.3),
            created_at: r.4
        )
    }

    public static func userFileNameExists(userID: Int, filename: String) async -> Bool {
        guard let result = try? await database.query(
            "SELECT 1 FROM user_files WHERE user_id = \(userID) AND filename = \(filename) LIMIT 1"
        ) else {
            return false
        }
        guard let rows = try? await result.collect() else {
            return false
        }
        return !rows.isEmpty
    }

    /// Вставка метаданных; при дубликате `(user_id, filename)` запрос падает → `nil`.
    public static func insertUserFile(userID: Int, filename: String, sizeBytes: Int) async -> Int? {
        guard let result = try? await database.query(
            "INSERT INTO user_files (user_id, filename, size_bytes) VALUES (\(userID), \(filename), \(sizeBytes)) RETURNING id"
        ) else {
            return nil
        }
        guard let row = try? await result.collect().first,
              let id = try? row.decode(Int.self) else {
            return nil
        }
        return id
    }

    /// Удаление строки только для владельца; `true`, если что-то удалили.
    public static func deleteUserFileRow(fileId: Int, userID: Int) async -> Bool {
        guard let result = try? await database.query(
            "DELETE FROM user_files WHERE id = \(fileId) AND user_id = \(userID) RETURNING id"
        ) else {
            return false
        }
        guard let rows = try? await result.collect(), !rows.isEmpty else {
            return false
        }
        return true
    }
}
