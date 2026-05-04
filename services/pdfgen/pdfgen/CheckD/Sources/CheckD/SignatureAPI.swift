//
//  SignatureHelpers.swift
//  CheckD
//
//  Created by NeKoChan on 4/23/26.
//

import AsyncHTTPClient
import Foundation

struct SignSigntaureRequest: Codable {
    let message: String
}

struct SignSigntaureResponse: Codable {
    let signature: String
}

struct ValidateSigntaureRequest: Codable {
    let message: String
    let signature: String
}

struct ValidateSignatureResponse: Codable {
    let valid: Bool
}

private enum SignatureServiceEnv {
    /// DNS/хост token-verfer (docker-compose). ENV: **`CHECKD_SIGNATURE_API_HOST`**, иначе `127.0.0.1`.
    static var host: String {
        let raw = ProcessInfo.processInfo.environment["CHECKD_SIGNATURE_API_HOST"] ?? ""
        return raw.isEmpty ? "127.0.0.1" : raw
    }

    /// Порт HTTP token-verfer. ENV: **`CHECKD_SIGNATURE_API_PORT`**, иначе `8082`.
    static var port: String {
        let raw = ProcessInfo.processInfo.environment["CHECKD_SIGNATURE_API_PORT"] ?? ""
        return raw.isEmpty ? "8082" : raw
    }

    static var baseURL: String {
        "http://\(host):\(port)"
    }
}

public final class SignatureAPI {
    public static func Sign(text: String) async -> String? {
        var request = HTTPClientRequest(url: "\(SignatureServiceEnv.baseURL)/sign")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(try! JSONEncoder().encode(SignSigntaureRequest(message: text)))
        
        guard let response = try? await HTTPClient.shared.execute(request, timeout: .seconds(5)) else {
            return nil
        }
        if response.status == .ok {
            guard let body = try? await response.body.collect(upTo: 65536) else {
                return nil
            }
            let signature = try? JSONDecoder().decode(SignSigntaureResponse.self, from: body)
            return signature?.signature
        }
        return nil
    }
    
    public static func Validate(text: String, signature: String) async -> Bool? {
        var request = HTTPClientRequest(url: "\(SignatureServiceEnv.baseURL)/validate")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .bytes(try! JSONEncoder().encode(ValidateSigntaureRequest(message: text, signature: signature)))
        
        guard let response = try? await HTTPClient.shared.execute(request, timeout: .seconds(5)) else {
            return nil
        }
        if response.status == .ok {
            guard let body = try? await response.body.collect(upTo: 65536) else {
                return nil
            }
            let result = try? JSONDecoder().decode(ValidateSignatureResponse.self, from: body)
            return result?.valid
        }
        return nil
    }
}
