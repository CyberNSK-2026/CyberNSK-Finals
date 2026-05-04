//
//  StaticErrors.swift
//  CheckD
//
//  Created by NeKoChan on 4/23/26.
//

import NIOCore

final class StaticAnswers {
    public static let BodyTooLarge = ByteBuffer(string: "{\"ok\": false, \"reason\": \"body too large\"}")
    public static let BadReqeust = ByteBuffer(string: "{\"ok\": false, \"reason\": \"Body has invalid syntax or malformed\"}")
    public static let Unauthorized = ByteBuffer(string: "{\"ok\": false, \"reason\": \"Unauthorized\"}")
    public static let Forbidden = ByteBuffer(string: "{\"ok\": false, \"reason\": \"Forbidden\"}")
    public static let InternalServerError = ByteBuffer(string: "{\"ok\": false, \"reason\": \"Internal server error\"}")
}
