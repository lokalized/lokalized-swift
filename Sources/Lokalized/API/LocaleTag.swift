/// A normalized locale tag with deterministic parsing and bundled CLDR helpers.
///
/// Use the throwing initializer for complete, strict validation. Use
/// `forLanguageTag` to accept a valid prefix of imperfect input. Parsing
/// preserves tag identity; `cldrCanonicalTag` applies CLDR aliases separately.
public struct LocaleTag: Hashable, Sendable, CustomStringConvertible {
    /// The normalized IETF BCP 47 language tag.
    public let tag: String
    /// The language subtag, or an empty string when no language is specified.
    public let language: String
    /// The script subtag, or an empty string when it is absent.
    public let script: String
    /// The region subtag, or an empty string when it is absent.
    public let region: String
    /// The ordered variant subtags.
    public let variants: [String]
    /// Extension singleton keys and their hyphen-separated values, including private use under `x`.
    public let extensions: [String: String]
    /// The private-use subtags following `x`, or an empty array.
    public var privateUse: [String] { extensions["x"]?.split(separator: "-").map(String.init) ?? [] }
    /// The normalized language tag.
    public var description: String { tag }
    /// The tag after applying the bundled CLDR language, script, region, and variant aliases.
    public var cldrCanonicalTag: String { CldrLocaleData.canonicalLanguageTag(tag) }
    /// The language, script, and region inferred from bundled CLDR likely-subtag data, or `nil` if no inference is available.
    public var likelySubtag: String? { CldrLocaleData.likelySubtagFor(tag) }
    /// The ordered locale ancestry computed from CLDR parents and tag truncation.
    /// This does not append an application-configured fallback catalog.
    public var fallbackLocaleTags: [String] { CldrLocaleData.fallbackLocaleTagsFor(tag) }
    /// Whether the tag is recognized by the bundled locale data for use as a catalog locale.
    /// A syntactically valid tag can still return `false`.
    public var isKnownLanguageTag: Bool { CldrLocaleData.isKnownLanguageTag(tag) }
    /// Whether the tag has no determined language, such as `und`.
    public var hasUndeterminedLanguage: Bool { CldrLocaleData.hasUndeterminedLanguage(tag) }
    /// Whether the explicit or inferred script uses right-to-left writing.
    public var isRightToLeft: Bool {
        let effective = script.isEmpty ? likelySubtag.map { Self.forLanguageTag($0).script } ?? "" : script
        return CldrLocaleData.isRightToLeftScript(effective)
    }

    /// Parses and validates a complete IETF BCP 47 language tag.
    ///
    /// Unknown but syntactically valid languages are accepted. Use
    /// `isKnownLanguageTag` to check recognition in the bundled locale data.
    /// Throws `LocaleTagError` for invalid syntax or locale fields.
    public init(_ text: String) throws {
        let parsed = JDKLocaleTag.parse(text)
        guard parsed.wellFormed else {
            throw LocaleTagError(.malformedLanguageTag, "Locale tag '\(text)' is not a well-formed IETF BCP 47 language tag")
        }
        self = try JDKLocaleTag.requireWellFormed(JDKLocaleTag.make(parsed), description: "Locale")
    }

    /// Parses the valid prefix of a language tag, dropping an ill-formed suffix.
    /// Returns an undetermined locale when no valid language prefix is available.
    /// Use the throwing initializer when the entire input must be valid.
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
    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (left: Self, right: Self) -> Bool {
        left.language == right.language && left.script == right.script && left.region == right.region
            && left.variants == right.variants && left.extensions == right.extensions
    }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(language); hasher.combine(script); hasher.combine(region); hasher.combine(variants)
        for singleton in extensions.keys.sorted() { hasher.combine(singleton); hasher.combine(extensions[singleton]) }
    }
}

/// A malformed language tag or locale refused by strict locale construction.
public struct LocaleTagError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Sendable {
        /// A `malformedLanguageTag` identifies invalid source tag syntax; `malformedLocale` identifies fields that cannot form a valid locale.
        case malformedLanguageTag, malformedLocale
    }
    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The diagnostic message.
    public var description: String { message }
    package init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
}
