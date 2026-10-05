import Foundation

// Compiled with the production sources; absent from the runtime package target.
private func units(_ value: String) -> [Int] { value.utf16.map(Int.init) }

private func errorChain(_ error: any Error) -> [[Any]] {
    var chain: [[Any]] = []
    var current: (any Error)? = error
    while let failure = current {
        let name: String
        let message: String
        switch failure {
        case let value as TranslationEvaluationError:
            name = "TranslationEvaluationError.\(value.kind.rawValue)"; message = value.message
            current = value.cause
        case let value as ExpressionCompilationError:
            name = "ExpressionCompilationError"; message = value.message
            current = value.cause
        case let value as NumericError:
            name = "NumericError.\(value.kind.rawValue)"; message = value.message
            current = nil
        case let value as UnsupportedLocaleError:
            name = "UnsupportedLocaleError"; message = value.message
            current = nil
        default: preconditionFailure("unmapped Swift expression error: \(type(of: failure))")
        }
        chain.append([name, units(message)])
        precondition(chain.count <= 8)
    }
    return chain
}

private func value(_ encoded: [String]) throws -> PlaceholderValue {
    precondition(encoded.count == 2)
    let raw = encoded[1]
    switch encoded[0] {
    case "null": return .null
    case "boolean": return .boolean(raw == "true")
    case "text": return .text(raw)
    case "byte": return .byte(Int8(raw)!)
    case "short": return .short(Int16(raw)!)
    case "integer": return .integer(Int32(raw)!)
    case "long": return .number(.integer(Int64(raw)!))
    case "bigInteger": return .number(.bigInteger(raw))
    case "decimal": return .number(.decimal(try ExactDecimal(raw, runtimeLimits: .numericHardCeilings)))
    case "floatBits": return .number(.float(Float(bitPattern: UInt32(raw, radix: 16)!)))
    case "doubleBits": return .number(.double(Double(bitPattern: UInt64(raw, radix: 16)!)))
    case "form": return .languageForm(LanguageFormValue(rawValue: raw)!)
    default: preconditionFailure("unknown value fixture")
    }
}

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [[[Int]]] = []
    func append(_ term: String, _ locale: LocaleTag) {
        lock.lock(); defer { lock.unlock() }
        records.append([units(term), units(locale.tag)])
    }
    var snapshot: [[[Int]]] {
        lock.lock(); defer { lock.unlock() }
        return records
    }
}

@main private enum ExpressionStressProbe {
    static func main() throws {
        while let line = readLine() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            precondition(fields.count == 6)
            let source = String(decoding: Data(base64Encoded: fields[3])!, as: UTF8.self)
            let encoded = try JSONReader.parse(Data(base64Encoded: fields[4])!)
            guard case .array(let contexts) = encoded else { preconditionFailure("contexts fixture must be an array") }
            var options: [String: Int] = [:]
            for pair in fields[2].split(separator: ",") {
                let tokens = pair.split(separator: "=", omittingEmptySubsequences: false)
                precondition(tokens.count == 2)
                options[String(tokens[0])] = Int(tokens[1])!
            }
            precondition(Set(options.keys).isSubset(of: ["characters", "tokens", "nesting", "precision", "scale", "phonetic"]))
            let limits = try TranslationRuntimeLimits(
                maximumNumberPrecision: options["precision"] ?? 1024,
                maximumAbsoluteNumberScale: options["scale"] ?? 1024,
                maximumExpressionCharacters: options["characters"] ?? 2048,
                maximumExpressionTokens: options["tokens"] ?? 256,
                maximumExpressionNestingDepth: options["nesting"] ?? 32,
                maximumInterpolatedOutputCharacters: options["phonetic"] ?? 262144)
            var row: [String: Any] = ["id": fields[0]]
            var results: [[String: Any]] = []
            do {
                let compiled = try ExpressionEvaluator.compile(source, runtimeLimits: limits)
                row["compile"] = NSNull()
                for encodedContext in contexts {
                    guard case .object(let members) = encodedContext else { preconditionFailure("context fixture must be an object") }
                    let context = try Dictionary(uniqueKeysWithValues: members.map { member -> (ExactString, PlaceholderValue) in
                        guard case .array(let items) = member.value else { preconditionFailure("value fixture must be an array") }
                        let texts = items.map { item -> String in
                            guard case .string(let text) = item else { preconditionFailure("value fixture must contain strings") }
                            return text
                        }
                        return (member.name, try value(texts))
                    })
                    let calls = Calls(), mode = fields[5]
                    let resolver: PhoneticResolver = { term, locale in
                        calls.append(term, locale)
                        if mode == "throw" { throw TranslationEvaluationError(kind: .invalidState, message: "resolver failure") }
                        return term.hasPrefix("hon") ? .vowel : .consonant
                    }
                    var result: [String: Any] = [:]
                    do {
                        result["value"] = try ExpressionEvaluator.evaluate(compiled, context: context,
                            locale: LocaleTag.forLanguageTag(fields[1]), runtimeLimits: limits, phoneticResolver: resolver)
                    } catch { result["error"] = errorChain(error) }
                    result["calls"] = calls.snapshot
                    results.append(result)
                }
            } catch { row["compile"] = errorChain(error) }
            row["results"] = results
            let output = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            print(String(decoding: output, as: UTF8.self))
        }
    }
}
