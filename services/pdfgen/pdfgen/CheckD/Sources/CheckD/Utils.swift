//
//  Utils.swift
//  CheckD
//
//  Created by NeKoChan on 4/23/26.
//

import Foundation
import FastCGI2


public enum B64Validator {
    static let regex = try! NSRegularExpression(
        pattern: "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"
    )
    static func isBase64Padded(_ s: String, maxLen: Int = 8192) -> Bool {
        let n = s.utf16.count
        if n == 0 || n > maxLen || n % 4 != 0 { return false }
        let range = NSRange(location: 0, length: n)
        return regex.firstMatch(in: s, options: [], range: range) != nil
    }
}

enum EmailValidator {
    private static let regex = try! NSRegularExpression(
        pattern: #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,63}$"#,
        options: [.caseInsensitive]
    )
    static func isValid(_ email: String, maxLength: Int = 254) -> Bool {
        let len = email.utf16.count
        guard len > 0, len <= maxLength else { return false }
        guard !email.hasPrefix("."), !email.hasSuffix("."), !email.contains("..") else { return false }
        let range = NSRange(location: 0, length: len)
        return regex.firstMatch(in: email, options: [], range: range) != nil
    }
}


public func escapeHTML(_ input: String) -> String {
    var result = String()
    result.reserveCapacity(input.count)
    for ch in input {
        switch ch {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        case "'": result += "&#39;"   // безопаснее, чем &apos; для HTML
        default: result.append(ch)
        }
    }
    return result
}

public func getQueryParam(_ req: Request, key: String) -> String? {
    guard let queryString = req.getParam(param: "QUERY_STRING"), !queryString.isEmpty else {
        return nil
    }
    let parts = queryString.split(separator: "&")
    for part in parts {
        let kv = part.split(separator: "=", maxSplits: 1)
        guard !kv.isEmpty else {
            continue
        }
        let k = String(kv[0]).removingPercentEncoding ?? String(kv[0])
        if k == key {
            if kv.count == 2 {
                return String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
            return ""
        }
    }
    return nil
}

public func userFriendlyDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}
