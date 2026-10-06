// Copyright 2026 Revetware LLC. Licensed under the Apache License, Version 2.0.
// Build-time verification only; SwiftParser and SwiftSyntax come from Xcode.
import Foundation
import CryptoKit
import SwiftParser
import SwiftSyntax

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).resolvingSymlinksInPath()
let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
var fingerprints: [String: String] = [:]
for case let entry as URL in enumerator where entry.pathExtension == "swift" {
    let file = entry.resolvingSymlinksInPath()
    let source = try String(contentsOf: file, encoding: .utf8)
    let tree = Parser.parse(source: source)
    guard !tree.hasError else { fatalError("Unable to parse \(file.path)") }
    // Trivia includes whitespace and comments. Tokens preserve literals,
    // interpolation, operators, attributes, and conditional compilation.
    let tokens = tree.tokens(viewMode: .sourceAccurate).map(\.text)
    let data = try JSONSerialization.data(withJSONObject: tokens)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    fingerprints[String(file.path.dropFirst(root.path.count + 1))] = digest
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: fingerprints, options: [.sortedKeys]))
