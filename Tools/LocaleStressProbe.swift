import Foundation

// Compiled beside current production sources; absent from the runtime target.
private func units(_ value: String) -> [Int] { value.utf16.map(Int.init) }

private func observe(_ text: String) -> [[Int]] {
    let locale = LocaleTag.forLanguageTag(text)
    let full = JDKLocaleTag.parse(text).wellFormed
    let rebuildable = (try? JDKLocaleTag.requireWellFormed(locale, description: "Locale")) != nil
    let script = locale.script.isEmpty ? locale.likelySubtag.map { LocaleTag.forLanguageTag($0).script } ?? "" : locale.script
    let fields = [locale.tag, locale.language, locale.script, locale.region,
        locale.variants.joined(separator: "_"),
        locale.extensions.keys.sorted().map { $0 + "-" + locale.extensions[$0]! }.joined(separator: "-"),
        locale.javaIdentifier, String(rebuildable), String(full), String((try? LocaleTag(text)) != nil),
        String(JDKLocaleTag.isCatalogLanguageTag(text)), CldrLocaleData.canonicalLanguageTag(text),
        locale.cldrCanonicalTag, CldrLocaleData.likelySubtagFor(text) ?? "<nil>",
        locale.likelySubtag ?? "<nil>", CldrLocaleData.languageScriptForLikelySubtag(text) ?? "<nil>",
        locale.fallbackLocaleTags.joined(separator: "|"), String(CldrLocaleData.isKnownLanguageTag(text)),
        String(CldrLocaleData.hasUndeterminedLanguage(text)), String(CldrLocaleData.isPrivateUseLanguageTag(text)),
        String(CldrLocaleData.isRightToLeftScript(script))]
    return fields.map(units)
}

@main private enum LocaleStressProbe {
    static func main() throws {
        while let line = readLine() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            precondition(fields.count == 2)
            let text = String(decoding: Data(base64Encoded: fields[1])!, as: UTF8.self)
            let output: [String: Any] = ["id": fields[0], "values": observe(text)]
            let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
