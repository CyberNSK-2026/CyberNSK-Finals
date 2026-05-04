import Foundation

/// Каталог с файлами, у каждого из которых есть время жизни; `cleanup()` удаляет просроченные записи и файлы с диска.
actor FileTTLStore {
    private let basePath: URL
    private let defaultTTL: TimeInterval
    /// Полный путь файла → момент, после которого файл считается просроченным.
    private var expiryByURL: [URL: Date] = [:]

    /// Создаёт базовый каталог при необходимости.
    init(basePath: URL, defaultTTL: TimeInterval) throws {
        self.basePath = basePath.standardizedFileURL
        self.defaultTTL = defaultTTL
        try FileManager.default.createDirectory(at: self.basePath, withIntermediateDirectories: true)
    }

    /// Регистрирует новый файл с TTL и возвращает **полный URL** (файл на диске создаётся вызывающим кодом).
    /// Имя: `UUID` + опциональное расширение (по умолчанию `pdf`).
    func create(ttl: TimeInterval? = nil, fileExtension: String = "pdf") -> URL {
        let id = UUID().uuidString
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let name = ext.isEmpty ? id : "\(id).\(ext)"
        let url = basePath.appendingPathComponent(name)
        let interval = ttl ?? defaultTTL
        expiryByURL[url] = Date().addingTimeInterval(interval)
        return url
    }

    /// Удаляет просроченные файлы и снимает их с учёта. Вызывай из таймера / цикла как угодно часто.
    func cleanup() {
        let now = Date()
        let fm = FileManager.default
        let expired = expiryByURL.filter { $0.value <= now }
        for (url, _) in expired {
            expiryByURL.removeValue(forKey: url)
            try? fm.removeItem(at: url)
        }
    }
}
