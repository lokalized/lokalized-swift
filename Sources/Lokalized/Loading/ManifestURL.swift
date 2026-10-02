import Foundation

/// Original special-URL parsing for manifest references. Unicode domain/IDNA
/// processing is explicitly unqualified; no host Foundation/ICU data is used.
package enum ManifestURL {
    package struct Failure: Error, Sendable, CustomStringConvertible {
        package enum Kind: Sendable { case invalidURL, unsupportedFeature }
        package let feature: UnqualifiedFeature?
        package let kind: Kind
        package let description: String
    }
    package enum UnqualifiedFeature: String, Sendable { case unicodeDomain, punycodeDomain }
    /// Input-only capability classification. Ordinary malformed inputs return nil.
    package static func unqualifiedFeature(reference: String, relativeTo base: String? = nil) -> UnqualifiedFeature? {
        do { _ = try resolve(reference, relativeTo: base); return nil }
        catch let failure as Failure { return failure.feature }
        catch { return nil }
    }
    private struct Record {
        var scheme: String
        var username = "", password = "", host = ""
        var port: Int?
        var path: [String] = []
        var query: String?, fragment: String?
        var opaque: String?
        var serialized: String {
            if let opaque { return scheme + ":" + opaque + (query.map { "?" + $0 } ?? "") + (fragment.map { "#" + $0 } ?? "") }
            var authority = host
            if !username.isEmpty || !password.isEmpty { authority = username + (password.isEmpty ? "" : ":" + password) + "@" + authority }
            if let port { authority += ":" + String(port) }
            return scheme + "://" + authority + "/" + path.joined(separator: "/")
                + (query.map { "?" + $0 } ?? "") + (fragment.map { "#" + $0 } ?? "")
        }
    }
    package static func resolve(_ reference: String, relativeTo base: String? = nil) throws -> String {
        let parsedBase = try base.map { try parse(clean($0), base: nil) }
        return try parse(clean(reference), base: parsedBase).serialized
    }
    private static func invalid() -> Failure { .init(feature: nil, kind: .invalidURL, description: "Invalid URL") }
    private static func unsupported(_ feature: UnqualifiedFeature) -> Failure {
        .init(feature: feature, kind: .unsupportedFeature, description: "URL feature is not yet qualified: " + feature.rawValue)
    }
    private static func clean(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let first = scalars.firstIndex { $0.value > 32 } ?? scalars.endIndex
        let end = scalars.lastIndex { $0.value > 32 }.map { $0 + 1 } ?? first
        return String(String.UnicodeScalarView(scalars[first..<end].filter { ![9, 10, 13].contains($0.value) }))
    }
    private static func scheme(_ text: String) -> (String, String)? {
        let bytes = Array(text.utf8)
        guard let colon = bytes.firstIndex(of: 58), colon > 0, alpha(bytes[0]),
              bytes[..<colon].allSatisfy({ alpha($0) || digit($0) || [43, 45, 46].contains($0) }) else { return nil }
        return (asciiLower(String(decoding: bytes[..<colon], as: UTF8.self)), String(decoding: bytes[(colon + 1)...], as: UTF8.self))
    }
    private static func parse(_ text: String, base: Record?) throws -> Record {
        if let (name, rest) = scheme(text) {
            if ["http", "https", "ftp", "ws", "wss"].contains(name) {
                if let base, base.scheme == name, !rest.utf8.starts(with: [47, 47]), !rest.utf8.starts(with: [92, 92]) {
                    return try relative(rest, base: base)
                }
                return try specialAbsolute(rest, scheme: name)
            }
            if name == "file" {
                if let base, base.scheme == "file", !rest.utf8.starts(with: [47, 47]), !rest.utf8.starts(with: [92, 92]) { return try relative(rest, base: base) }
                return try fileAbsolute(rest)
            }
            // These records are only used to diagnose a disallowed manifest
            // scheme. Opaque schemes never enter a permitted catalog fetch plan.
            let pieces = splitSuffix(rest)
            return Record(scheme: name, query: pieces.query.map { encode($0, set: .query) },
                          fragment: pieces.fragment.map { encode($0, set: .fragment) }, opaque: encode(pieces.path, set: .opaque))
        }
        guard let base else { throw invalid() }
        if base.opaque != nil {
            if text.utf8.first == 35 { var result = base; result.fragment = encode(String(decoding: text.utf8.dropFirst(), as: UTF8.self), set: .fragment); return result }
            throw invalid()
        }
        return try relative(text, base: base)
    }
    private static func specialAbsolute(_ text: String, scheme: String) throws -> Record {
        let text = text.replacingOccurrences(of: "\\", with: "/")
        let stripped = Array(text.utf8.drop(while: { $0 == 47 }))
        let stop = stripped.firstIndex { [47, 63, 35].contains($0) } ?? stripped.endIndex
        let authority = String(decoding: stripped[..<stop], as: UTF8.self)
        var record = try authorityRecord(authority, scheme: scheme)
        applySuffix(String(decoding: stripped[stop...], as: UTF8.self), record: &record, rooted: true)
        return record
    }
    private static func fileAbsolute(_ text: String) throws -> Record {
        let text = text.replacingOccurrences(of: "\\", with: "/")
        var result = Record(scheme: "file")
        if text.utf8.starts(with: [47, 47]) {
            let remaining = Array(text.utf8.dropFirst(2))
            let stop = remaining.firstIndex { [47, 63, 35].contains($0) } ?? remaining.endIndex
            let host = String(decoding: remaining[..<stop], as: UTF8.self)
            if drive(host) { applySuffix("/" + host + String(decoding: remaining[stop...], as: UTF8.self), record: &result, rooted: true) }
            else {
                if host.contains("@") || host.contains(":") && !host.hasPrefix("[") { throw invalid() }
                result.host = host.isEmpty ? "" : try parseHost(host)
                if result.host == "localhost" { result.host = "" }
                applySuffix(String(decoding: remaining[stop...], as: UTF8.self), record: &result, rooted: true)
            }
        } else { applySuffix(text, record: &result, rooted: true) }
        return result
    }
    private static func relative(_ text: String, base: Record) throws -> Record {
        let text = text.replacingOccurrences(of: "\\", with: "/")
        if text.utf8.starts(with: [47, 47]) { return try base.scheme == "file" ? fileAbsolute(text) : specialAbsolute(text, scheme: base.scheme) }
        var result = base
        result.fragment = nil
        if text.isEmpty { return result }
        if text.utf8.first == 35 { result.fragment = encode(String(decoding: text.utf8.dropFirst(), as: UTF8.self), set: .fragment); return result }
        if text.utf8.first == 63 {
            let suffix = splitSuffix(text); result.query = suffix.query.map { encode($0, set: .query) }
            result.fragment = suffix.fragment.map { encode($0, set: .fragment) }; return result
        }
        let suffix = splitSuffix(text)
        let startsDrive = base.scheme == "file" && drive(suffix.path.unicodeScalars.split(omittingEmptySubsequences: false, whereSeparator: { $0.value == 47 }).first.map(String.init) ?? "")
        if startsDrive { result.path = [] }
        else if text.utf8.first == 47 {
            let rootComponent = suffix.path.unicodeScalars.dropFirst().split(omittingEmptySubsequences: false, whereSeparator: { $0.value == 47 }).first.map(String.init) ?? ""
            result.path = base.scheme == "file" && !drive(rootComponent) && base.path.first.map(drive) == true ? [base.path[0]] : []
        } else { shorten(&result.path, file: base.scheme == "file") }
        applySuffix(text, record: &result, rooted: false)
        return result
    }
    private static func authorityRecord(_ authority: String, scheme: String) throws -> Record {
        var result = Record(scheme: scheme), hostPort = Array(authority.utf8)
        if let at = hostPort.lastIndex(of: 64) {
            let credentials = String(decoding: hostPort[..<at], as: UTF8.self).replacingOccurrences(of: "@", with: "%40")
            let bytes = Array(credentials.utf8)
            if let colon = bytes.firstIndex(of: 58) {
                result.username = encode(String(decoding: bytes[..<colon], as: UTF8.self), set: .userinfo)
                result.password = encode(String(decoding: bytes[(colon + 1)...], as: UTF8.self), set: .userinfo)
            } else { result.username = encode(credentials, set: .userinfo) }
            hostPort = Array(hostPort[(at + 1)...])
        }
        var host = hostPort, portText: [UInt8]?
        if hostPort.first == 91 {
            guard let close = hostPort.firstIndex(of: 93) else { throw invalid() }
            host = Array(hostPort[...close])
            let tail = hostPort[(close + 1)...]
            if !tail.isEmpty { guard tail.first == 58 else { throw invalid() }; portText = Array(tail.dropFirst()) }
        } else if let colon = hostPort.lastIndex(of: 58) {
            host = Array(hostPort[..<colon]); portText = Array(hostPort[(colon + 1)...])
        }
        guard !host.isEmpty else { throw invalid() }
        result.host = try parseHost(String(decoding: host, as: UTF8.self))
        if let portText, !portText.isEmpty {
            var port = 0
            for byte in portText {
                guard digit(byte), port <= 6_553 else { throw invalid() }
                port = port * 10 + Int(byte - 48)
                guard port <= 65_535 else { throw invalid() }
            }
            let defaults = ["http": 80, "https": 443, "ftp": 21, "ws": 80, "wss": 443]
            if defaults[scheme] != port { result.port = port }
        }
        return result
    }
    private static func splitSuffix(_ text: String) -> (path: String, query: String?, fragment: String?) {
        let bytes = Array(text.utf8)
        let hash = bytes.firstIndex(of: 35) ?? bytes.endIndex
        let question = bytes[..<hash].firstIndex(of: 63) ?? hash
        return (String(decoding: bytes[..<question], as: UTF8.self),
                question == hash ? nil : String(decoding: bytes[(question + 1)..<hash], as: UTF8.self),
                hash == bytes.endIndex ? nil : String(decoding: bytes[(hash + 1)...], as: UTF8.self))
    }
    private static func applySuffix(_ text: String, record: inout Record, rooted: Bool) {
        let suffix = splitSuffix(text)
        if rooted { record.path = [] }
        let path = suffix.path.utf8.first == 47 ? String(decoding: suffix.path.utf8.dropFirst(), as: UTF8.self) : suffix.path
        let components = path.unicodeScalars.split(omittingEmptySubsequences: false, whereSeparator: { $0.value == 47 }).map(String.init)
        for (index, component) in components.enumerated() {
            let dot = asciiLower(component)
            if [".", "%2e"].contains(dot) { if index + 1 == components.count { record.path.append("") } }
            else if ["..", ".%2e", "%2e.", "%2e%2e"].contains(dot) {
                shorten(&record.path, file: record.scheme == "file")
                if index + 1 == components.count { record.path.append("") }
            } else {
                var encoded = encode(component, set: .path)
                if record.scheme == "file" && record.path.isEmpty && drive(encoded) {
                    encoded = String(encoded.prefix(1)) + ":"
                }
                record.path.append(encoded)
            }
        }
        record.query = suffix.query.map { encode($0, set: .query) }
        record.fragment = suffix.fragment.map { encode($0, set: .fragment) }
    }
    private static func shorten(_ path: inout [String], file: Bool) {
        if file && path.count == 1 && drive(path[0]) { return }
        if !path.isEmpty { path.removeLast() }
    }
    private static func drive(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.count == 2 && alpha(bytes[0]) && (bytes[1] == 58 || bytes[1] == 124)
    }
    private enum EncodeSet { case opaque, fragment, query, path, userinfo }
    private static func encode(_ text: String, set: EncodeSet) -> String {
        let extra: Set<UInt8>
        switch set {
        case .opaque: extra = []
        case .fragment: extra = [32, 34, 60, 62, 96]
        case .query: extra = [32, 34, 35, 39, 60, 62]
        case .path: extra = [32, 34, 35, 60, 62, 63, 94, 96, 123, 125]
        case .userinfo: extra = [32, 34, 35, 47, 58, 59, 60, 61, 62, 63, 64, 91, 92, 93, 94, 96, 123, 124, 125]
        }
        let hex = Array("0123456789ABCDEF".utf8)
        var result: [UInt8] = []
        for byte in text.utf8 {
            if byte < 32 || byte > 126 || extra.contains(byte) { result += [37, hex[Int(byte >> 4)], hex[Int(byte & 15)]] }
            else { result.append(byte) }
        }
        return String(decoding: result, as: UTF8.self)
    }
    private static func parseHost(_ raw: String) throws -> String {
        if raw.hasPrefix("[") {
            guard raw.hasSuffix("]") else { throw invalid() }
            let literal = String(raw.dropFirst().dropLast())
            let words = try ipv6Words(literal)
            var bestStart = -1, bestLength = 1, index = 0
            while index < 8 {
                if words[index] != 0 { index += 1; continue }
                let start = index
                while index < 8 && words[index] == 0 { index += 1 }
                if index - start > bestLength { bestStart = start; bestLength = index - start }
            }
            if bestStart < 0 { return "[" + words.map { String($0, radix: 16) }.joined(separator: ":") + "]" }
            let left = words[..<bestStart].map { String($0, radix: 16) }.joined(separator: ":")
            let right = words[(bestStart + bestLength)...].map { String($0, radix: 16) }.joined(separator: ":")
            return "[" + left + "::" + right + "]"
        }
        let decoded = try percentDecode(raw)
        guard decoded.utf8.allSatisfy({ $0 < 128 }) else { throw unsupported(.unicodeDomain) }
        let host = asciiLower(decoded)
        guard !host.utf8.contains(where: { $0 <= 32 || $0 == 127 || [35, 37, 47, 58, 60, 62, 63, 64, 91, 92, 93, 94, 124].contains($0) }) else { throw invalid() }
        if host.split(separator: ".", omittingEmptySubsequences: false).contains(where: { $0.hasPrefix("xn--") }) {
            throw unsupported(.punycodeDomain)
        }
        var parts = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.last == "" { parts.removeLast() }
        guard let last = parts.last else { return host }
        let lastBytes = Array(last.utf8)
        let hexadecimalNumber = asciiLower(last).hasPrefix("0x") && lastBytes.dropFirst(2).allSatisfy { hexDigit($0) != nil }
        if last.utf8.allSatisfy(digit) || hexadecimalNumber || ipv4Number(last) != nil {
            guard parts.count <= 4, !parts.isEmpty else { throw invalid() }
            let values = try parts.map { text -> UInt64 in guard let value = ipv4Number(text) else { throw invalid() }; return value }
            guard values.dropLast().allSatisfy({ $0 <= 255 }), values.last! < (UInt64(1) << (8 * (5 - values.count))) else { throw invalid() }
            var value = values.last!
            for (index, part) in values.dropLast().enumerated() { value += part << (8 * (3 - index)) }
            return [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
        }
        return host
    }
    private static func ipv6Words(_ literal: String) throws -> [UInt16] {
        guard literal.utf8.allSatisfy({ $0 < 128 }) else { throw invalid() }
        let sides = literal.components(separatedBy: "::")
        guard sides.count <= 2 else { throw invalid() }
        func parseSide(_ side: String, allowIPv4: Bool) throws -> [UInt16] {
            if side.isEmpty { return [] }
            let pieces = side.split(separator: ":", omittingEmptySubsequences: false)
            var words: [UInt16] = []
            for (index, piece) in pieces.enumerated() {
                if piece.contains(".") {
                    guard allowIPv4, index + 1 == pieces.count else { throw invalid() }
                    let decimals = piece.split(separator: ".", omittingEmptySubsequences: false)
                    guard decimals.count == 4 else { throw invalid() }
                    let bytes = try decimals.map { text -> UInt16 in
                        guard !text.isEmpty, text.utf8.allSatisfy(digit), text.utf8.count == 1 || text.utf8.first != 48,
                              let value = UInt16(text), value <= 255 else { throw invalid() }
                        return value
                    }
                    words += [bytes[0] << 8 | bytes[1], bytes[2] << 8 | bytes[3]]
                } else {
                    guard !piece.isEmpty, piece.utf8.count <= 4, piece.utf8.allSatisfy({ hexDigit($0) != nil }),
                          let value = UInt16(piece, radix: 16) else { throw invalid() }
                    words.append(value)
                }
            }
            return words
        }
        if sides.count == 1 {
            let words = try parseSide(sides[0], allowIPv4: true)
            guard words.count == 8 else { throw invalid() }
            return words
        }
        let left = try parseSide(sides[0], allowIPv4: false), right = try parseSide(sides[1], allowIPv4: true)
        guard left.count + right.count < 8 else { throw invalid() }
        return left + Array(repeating: 0, count: 8 - left.count - right.count) + right
    }
    private static func ipv4Number(_ text: String) -> UInt64? {
        if text.isEmpty { return nil }
        var bytes = Array(text.utf8), radix: UInt64 = 10
        if bytes.count >= 2 && bytes[0] == 48 && (bytes[1] == 120 || bytes[1] == 88) { radix = 16; bytes.removeFirst(2) }
        else if bytes.count >= 2 && bytes[0] == 48 { radix = 8; bytes.removeFirst() }
        var value: UInt64 = 0
        for byte in bytes {
            guard let number = hexDigit(byte), number < radix else { return nil }
            let (times, overflow) = value.multipliedReportingOverflow(by: radix)
            let (sum, sumOverflow) = times.addingReportingOverflow(number)
            if overflow || sumOverflow { return nil }; value = sum
        }
        return value
    }
    private static func percentDecode(_ text: String) throws -> String {
        let bytes = Array(text.utf8); var result: [UInt8] = [], index = 0
        while index < bytes.count {
            if bytes[index] == 37, index + 2 < bytes.count,
               let a = hexDigit(bytes[index + 1]), let b = hexDigit(bytes[index + 2]) {
                result.append(UInt8(a * 16 + b)); index += 3
            } else { result.append(bytes[index]); index += 1 }
        }
        guard let decoded = String(bytes: result, encoding: .utf8) else { throw invalid() }
        return decoded
    }
    private static func asciiLower(_ text: String) -> String { String(decoding: text.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }, as: UTF8.self) }
    private static func alpha(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    private static func digit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    private static func hexDigit(_ byte: UInt8) -> UInt64? {
        if digit(byte) { return UInt64(byte - 48) }
        if (65...70).contains(byte) { return UInt64(byte - 55) }
        if (97...102).contains(byte) { return UInt64(byte - 87) }
        return nil
    }
}
