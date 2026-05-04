import Foundation

/// Тело запроса на печать: адрес страницы и опциональный TTL файла PDF (секунды).
struct PrintPageRequest: Codable, Sendable {
    let url: URL
    /// Время жизни сгенерированного PDF на диске, в секундах. Если `nil` — берётся TTL по умолчанию из `FileTTLStore`.
    let fileTTL: TimeInterval?
}

/// Ответ на запрос печати: флаг успеха, ссылка на PDF при `ok == true`, текст ошибки при `ok == false`.
struct PrintPageResponse: Codable, Sendable {
    let ok: Bool
    /// Заполнено при успехе.
    let pdfurl: String?
    /// Заполнено при ошибке (для обработчика после `catch` или валидации).
    let error: String?

    static func success(pdfurl: String) -> PrintPageResponse {
        PrintPageResponse(ok: true, pdfurl: pdfurl, error: nil)
    }

    static func failure(_ message: String) -> PrintPageResponse {
        PrintPageResponse(ok: false, pdfurl: nil, error: message)
    }
}
