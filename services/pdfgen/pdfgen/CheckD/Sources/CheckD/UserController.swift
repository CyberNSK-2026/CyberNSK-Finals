//
//  UserController.swift
//  CheckD
//
//  Created by NeKoChan on 4/24/26.
//

import NIO
import Foundation
import FastCGI2

struct UserGetResponse: Codable {
    let ok: Bool
    let username: String?
    let last_login: String?
    let error: String?
}

public func InitUserRoutes() async {
    await server.on(path: "/api/users/get", method: "GET") { req in
        guard await parseAuthorizedSession(req) != nil else {
            return Response(statusCode: 401, contentType: "application/json", data: StaticAnswers.Unauthorized)
        }
        guard let userIdRaw = getQueryParam(req, key: "userid"),
              let userId = Int(userIdRaw), userId > 0 else {
            return Response(statusCode: 400, contentType: "application/json", data: StaticAnswers.BadReqeust)
        }
        guard let user = await DatabaseHelpers.getUser(id: userId) else {
            return Response(statusCode: 404, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(UserGetResponse(
                ok: false,
                username: nil,
                last_login: nil,
                error: "User not found"
            ))))
        }
        return Response(statusCode: 200, contentType: "application/json", data: ByteBuffer(data: try! JSONEncoder().encode(UserGetResponse(
            ok: true,
            username: user.name,
            last_login: userFriendlyDateString(user.last_auth_at),
            error: nil
        ))))
    }
}
