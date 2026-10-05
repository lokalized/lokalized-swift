import Foundation

// Compiled alongside the production sources, never linked into the runtime package.
private func units(_ value: String?) -> Any {
    value.map { $0.utf16.map(Int.init) } ?? NSNull()
}

private func project(_ model: LocalizedString) -> [Any] {
    let placeholders: [[Any]] = model.placeholderDefinitionOrder.map { key in
        let definition = model.placeholderDefinitions[key]!
        let value: [Any]
        switch definition {
        case .languageForm(let form):
            let range: Any = form.range.map { [units($0.start.string), units($0.end.string)] } ?? NSNull()
            let translations = form.translationsByLanguageForm.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { [units($0.key.rawValue), units($0.value)] }
            value = ["languageForm", units(form.value?.string), range, translations]
        case .expression(let template):
            value = ["expression", units(template.translation), template.alternatives.map {
                [units($0.expression.string), units($0.translation)]
            }]
        }
        return [units(key.string), value]
    }
    return [units(model.key.string), units(model.translation), units(model.commentary),
            placeholders, model.alternatives.map(project)]
}

private final class Warnings: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [[Int]] = []
    func append(_ warning: LocalizedStringWarning) {
        lock.lock(); defer { lock.unlock() }
        messages.append(warning.message.utf16.map(Int.init))
    }
    var values: [[Int]] {
        lock.lock(); defer { lock.unlock() }
        return messages
    }
}

@main private enum ParserStressProbe {
    static func main() throws {
        while let line = readLine() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            precondition(fields.count == 4)
            var options: [String: Int] = [:]
            for field in fields[2].split(separator: ",") {
                let pair = field.split(separator: "=", omittingEmptySubsequences: false)
                precondition(pair.count == 2)
                options[String(pair[0])] = Int(pair[1])!
            }
            precondition(Set(options.keys).isSubset(of: ["maximumInputBytes", "maximumTotalInputBytes",
                "maximumReaderCharacters", "maximumJsonNestingDepth", "maximumTranslationNodes", "maximumWarnings"]))
            let limits = try LocalizedStringLoadingOptions(
                maximumInputBytes: options["maximumInputBytes"] ?? LocalizedStringLoadingOptions.defaultMaximumInputBytes,
                maximumReaderCharacters: options["maximumReaderCharacters"] ?? LocalizedStringLoadingOptions.defaultMaximumReaderCharacters,
                maximumJsonNestingDepth: options["maximumJsonNestingDepth"] ?? LocalizedStringLoadingOptions.defaultMaximumJsonNestingDepth,
                maximumTotalInputBytes: options["maximumTotalInputBytes"] ?? LocalizedStringLoadingOptions.defaultMaximumTotalInputBytes,
                maximumTranslationNodes: options["maximumTranslationNodes"] ?? LocalizedStringLoadingOptions.defaultMaximumTranslationNodes,
                maximumWarnings: options["maximumWarnings"] ?? LocalizedStringLoadingOptions.defaultMaximumWarnings)
            let bytes = Data(base64Encoded: fields[3])!
            let warnings = Warnings()
            var row: [String: Any] = ["id": fields[0]]
            do {
                let parsed = try LocalizedStringLoader.parse(bytes, locale: fields[1], source: fields[0],
                    warningHandler: { warnings.append($0) }, loadingOptions: limits)
                row["status"] = "returned"
                row["class"] = NSNull()
                row["value"] = parsed.strings.sorted { $0.key < $1.key }.map(project)
            } catch {
                row["status"] = "threw"
                row["class"] = String(reflecting: type(of: error))
                row["value"] = units((error as? StringsParseError)?.message ?? String(describing: error))
            }
            row["warnings"] = warnings.values
            let output = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            print(String(decoding: output, as: UTF8.self))
        }
    }
}
