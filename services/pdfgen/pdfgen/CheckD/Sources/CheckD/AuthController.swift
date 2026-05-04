//
//  AuthController.swift
//  CheckD
//
//  Created by NeKoChan on 4/23/26.
//

import NIO
import Foundation
import FastCGI2
import ServiceStdio

struct AuthLoginRequest: Codable {
    let email: String
    let pass: String
}

struct AuthRegisterRequest: Codable {
    let user: String
    let email: String
    let pass: String
}

struct AuthResponse: Codable {
    let ok: Bool
    let token: String?
    let error: String?
}

public struct SessionData: Codable {
    let username: String
    let userID: Int
    let userRole: Int
    let expires: Date
}

/// Полезная нагрузка SSO-токена (только эти поля в JSON перед подписью).
private struct SSOTokenPayload: Codable {
    let expires: Date
    let username: String
    let role: Int
}

private struct SSOCreateTokenResponse: Codable {
    let ok: Bool
    let token: String?
}

public func CheckAuth(auth_hdr: String) async -> SessionData? {
    let parts = auth_hdr.split(separator: ".")
    guard parts.count == 2 else { return nil }
    let session = String(parts[0])
    let signature = String(parts[1])
    
    guard B64Validator.isBase64Padded(session) && B64Validator.isBase64Padded(signature) else {
        return nil
    }
    
    guard let isValid = await SignatureAPI.Validate(text: "session=\(session)", signature: signature), isValid else {
        return nil;
    }
    
    let sessionData = Data(base64Encoded: session)!
    return try? JSONDecoder().decode(SessionData.self, from: sessionData)
}

public func parseAuthorizedSession(_ req: Request) async -> SessionData? {
    guard let token = req.getParam(param: "HTTP_AUTHORIZATION") else {
        return nil
    }
    let authHeader = token.split(separator: " ")
    guard authHeader.count == 2, authHeader[0] == "Custom" else {
        return nil
    }
    return await CheckAuth(auth_hdr: String(authHeader[1]))
}

public func InitAuthRoures() async {
    await server.on(path: "/api/auth/login", method: "POST") { req in
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            await ServiceStdio.shared.log("auth/login: body too large")
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BodyTooLarge)
        }
        
        var reqData: AuthLoginRequest
        do {
            reqData = try JSONDecoder().decode(AuthLoginRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        
        guard let user_id = await DatabaseHelpers.tryLoginUser(email: reqData.email, password: reqData.pass) else {
            return Response(statusCode: 200, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        guard user_id > 0 else {
            return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(AuthResponse(
                ok: false,
                token: nil,
                error: "Wrong username or password"
            ))))
        }
        
        let userInfo = await DatabaseHelpers.getUser(id: user_id)!
        let newuserInfo = User(id: userInfo.id, name: userInfo.name, email: userInfo.email, role: userInfo.role, last_auth_at: Date())
        _ = await DatabaseHelpers.updateUser(user: newuserInfo)
        
        let session = SessionData(
            username: userInfo.name,
            userID: userInfo.id,
            userRole: userInfo.role,
            expires: Date().addingTimeInterval(600)
        )
        
        let sessionDump = try! JSONEncoder().encode(session)
        let sessionb64 = sessionDump.base64EncodedString()
        let sessiontext = "session=\(sessionb64)"
        
        guard let signature = await SignatureAPI.Sign(text: sessiontext) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        await ServiceStdio.shared.log("auth/login: token issued user_id=\(userInfo.id)")

        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(AuthResponse(
            ok: true,
            token: "\(sessionb64).\(signature)",
            error: nil
        ))))
    }
    await server.on(path: "/api/auth/register", method: "POST") { req in
        var buffer = ByteBuffer()
        let bodyLen = await req.readBytes(buffer: &buffer, limit: 65535)
        if bodyLen == 65535 && req.readableBytes > 0 {
            await ServiceStdio.shared.log("auth/register: body too large")
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BodyTooLarge)
        }
        
        var reqData: AuthRegisterRequest
        do {
            reqData = try JSONDecoder().decode(AuthRegisterRequest.self, from: buffer)
        } catch {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        
        //TODO: Register user password and load user from database
        let eMail = reqData.email
        if !EmailValidator.isValid(eMail) {
            return Response(statusCode: 400, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(AuthResponse(
                ok: true,
                token: nil,
                error: "Email looks wrong. Please check it and try again."
            ))))
        }
        
        //By default user role is 2 = user
        var user = User(id: 0, name: escapeHTML(reqData.user), email: reqData.email, role: 2, last_auth_at: Date())
        guard let cRes = await DatabaseHelpers.createUser(user: &user, password: reqData.pass) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        
        guard cRes else {
            return Response(statusCode: 409, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(AuthResponse(
                ok: true,
                token: nil,
                error: "That email is already taken."
            ))))
        }
        
        let session = SessionData(
            username: user.name,
            userID: user.id,
            userRole: user.role,
            expires: Date().addingTimeInterval(600)
        )
        
        let sessionDump = try! JSONEncoder().encode(session)
        let sessionb64 = sessionDump.base64EncodedString()
        let sessiontext = "session=\(sessionb64)"
        
        guard let signature = await SignatureAPI.Sign(text: sessiontext) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }
        await ServiceStdio.shared.log("auth/register: token issued user_id=\(user.id)")

        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(AuthResponse(
            ok: true,
            token: "\(sessionb64).\(signature)",
            error: nil
        ))))
    }
    await server.on(path: "/api/auth/check_session", method: "GET") { req in
        guard let token = req.getParam(param: "HTTP_AUTHORIZATION") else {
            return Response(statusCode: 401, contentType: "applicaion/json", data: StaticAnswers.Unauthorized)
        }
        let authHeader = token.split(separator: " ")
        guard authHeader.count == 2, authHeader[0] == "Custom" else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        let sessStr = String(authHeader[1])
        guard let sessionData = await CheckAuth(auth_hdr: sessStr) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        let valid = sessionData.expires >= Date()
        await ServiceStdio.shared.log("auth/check_session: user_id=\(sessionData.userID) session_valid=\(valid)")
        if sessionData.expires < Date() {
            return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(string: "{\"ok\": true, \"session_valid\": false}"))
        }
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(string: "{\"ok\": true, \"session_valid\": true}"))
    }

    /// SSO: выпуск подписанного токена с полями `expires`, `username`, `role` (нужна обычная сессия `Custom …`).
    await server.on(path: "/api/sso/create-token", method: "GET") { req in
        guard let session = await parseAuthorizedSession(req) else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        if session.expires < Date() {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }

        let payload = SSOTokenPayload(
            expires: Date().addingTimeInterval(86400),
            username: session.username,
            role: session.userRole
        )
        let payloadDump = try! JSONEncoder().encode(payload)
        let payloadB64 = payloadDump.base64EncodedString()
        let sessiontext = "sso-token=\(payloadB64)"

        guard let signature = await SignatureAPI.Sign(text: sessiontext) else {
            return Response(statusCode: 500, contentType: "application/json", data: StaticAnswers.InternalServerError)
        }

        let token = "\(payloadB64).\(signature)"
        return Response(
            statusCode: 200,
            contentType: "application/json",
            data: ByteBuffer(data: try! JSONEncoder().encode(SSOCreateTokenResponse(ok: true, token: token)))
        )
    }
}
