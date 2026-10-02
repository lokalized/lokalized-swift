import Foundation
import Lokalized

// Development-only public consumer. Sampling observes unmodified library code.
let mode = CommandLine.arguments[1]
let en = try LocaleTag("en")
let plain = #"{"hello":"Hello {{name}}!"}"#
let plural = #"{"items":{"translation":"{{n}}","placeholders":{"n":{"value":"count","translations":{"CARDINALITY_ONE":"one","CARDINALITY_OTHER":"other"}}}}}"#
let parsed = try LocalizedStringLoader.parse(mode == "plain" ? plain : plural, locale: "en")
let strings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { [en: LocalizedCatalog(strings: parsed.strings)] },
    localeSupplier: { _ in en }, fallbackLocale: en, bidiIsolation: .disabled))
let key: ExactString = mode == "plain" ? "hello" : "items"
let expected = mode == "plain" ? "Hello Ada!" : "other"
let values: PlaceholderValues
switch mode {
case "plain": values = ["name": .text("Ada")]
case "double-pi": values = ["count": .number(.double(.pi))]
case "double-max": values = ["count": .number(.double(.greatestFiniteMagnitude))]
default: fatalError("Unknown profile workload")
}
for _ in 0..<20 {
    let result = try strings.getResult(key, placeholders: values)
    precondition(result.translation == expected)
}
FileHandle.standardError.write(Data("ready\n".utf8))
let start = DispatchTime.now().uptimeNanoseconds
var iterations = 0, checksum = 0
while DispatchTime.now().uptimeNanoseconds - start < 5_000_000_000 {
    let result = try strings.getResult(key, placeholders: values)
    precondition(result.translation == expected && result.status == .translated && result.resolvedLocale == en)
    checksum += result.translation.utf16.count
    iterations += 1
}
let elapsed = DispatchTime.now().uptimeNanoseconds - start
precondition(checksum == iterations * expected.utf16.count)
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
struct Result: Encodable {
    let workload: String
    let iterations: Int
    let checksum: Int
    let durationNs: UInt64
}
FileHandle.standardOutput.write(try encoder.encode(Result(workload: mode, iterations: iterations, checksum: checksum, durationNs: elapsed)))
print("")
