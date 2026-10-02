/// A deterministic Java-compatible locale value, without Foundation Locale
/// negotiation. The tag is JDK projection; CLDR aliases are a separate stage.
public struct LocaleTag: Hashable, Sendable, CustomStringConvertible {
    public let tag: String
    public let language: String
    public let script: String
    public let region: String
    public let variants: [String]
    public let extensions: [String: String]
    public var privateUse: [String] { extensions["x"]?.split(separator: "-").map(String.init) ?? [] }
    public var description: String { tag }
    public var cldrCanonicalTag: String { CldrLocaleData.canonicalLanguageTag(tag) }
    public var likelySubtag: String? { CldrLocaleData.likelySubtagFor(tag) }
    public var fallbackLocaleTags: [String] { CldrLocaleData.fallbackLocaleTagsFor(tag) }
    public var isKnownLanguageTag: Bool { CldrLocaleData.isKnownLanguageTag(tag) }
    public var hasUndeterminedLanguage: Bool { CldrLocaleData.hasUndeterminedLanguage(tag) }
    public var isRightToLeft: Bool {
        let effective = script.isEmpty ? likelySubtag.map { Self.forLanguageTag($0).script } ?? "" : script
        return CldrLocaleData.isRightToLeftScript(effective)
    }

    /// Requires the complete input tag to parse and its resulting locale fields
    /// to be rebuildable by Java Locale.Builder. Unknown but syntactically valid
    /// languages remain accepted; catalog filename recognition is separate.
    public init(_ text: String) throws {
        let parsed = JDKLocaleTag.parse(text)
        guard parsed.wellFormed else {
            throw LocaleTagError(.malformedLanguageTag, "Locale tag '\(text)' is not a well-formed IETF BCP 47 language tag")
        }
        self = try JDKLocaleTag.requireWellFormed(JDKLocaleTag.make(parsed), description: "Locale")
    }

    /// Java Locale.forLanguageTag: never throws; an ill-formed suffix is dropped.
    /// It is deliberately different from the strict String initializer.
    public static func forLanguageTag(_ text: String) -> Self { JDKLocaleTag.make(JDKLocaleTag.parse(text)) }

    package init(tag: String, language: String, script: String, region: String, variants: [String], extensions: [String: String]) {
        self.tag = tag; self.language = language; self.script = script; self.region = region
        self.variants = variants; self.extensions = extensions
    }
    package var javaIdentifier: String {
        var value = language
        if !region.isEmpty || (!language.isEmpty && (!variants.isEmpty || !script.isEmpty || !extensions.isEmpty)) { value += "_" + region }
        if !variants.isEmpty && (!language.isEmpty || !region.isEmpty) { value += "_" + variants.joined(separator: "_") }
        if (!script.isEmpty || !extensions.isEmpty) && (!language.isEmpty || !region.isEmpty) {
            value += "_#" + script
            if !script.isEmpty && !extensions.isEmpty { value += "_" }
            value += extensions.keys.sorted().map { $0 + "-" + extensions[$0]! }.joined(separator: "-")
        }
        return value
    }
    public static func == (left: Self, right: Self) -> Bool {
        left.language == right.language && left.script == right.script && left.region == right.region
            && left.variants == right.variants && left.extensions == right.extensions
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(language); hasher.combine(script); hasher.combine(region); hasher.combine(variants)
        for singleton in extensions.keys.sorted() { hasher.combine(singleton); hasher.combine(extensions[singleton]) }
    }
}

public struct LocaleTagError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case malformedLanguageTag, malformedLocale }
    public let kind: Kind
    public let message: String
    public var description: String { message }
    package init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
}
