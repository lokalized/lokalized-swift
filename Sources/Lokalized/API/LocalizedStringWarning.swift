/// An immutable warning delivered in catalog declaration order.
public struct LocalizedStringWarning: Hashable, Sendable {
    public enum WarningType: String, CaseIterable, Hashable, Sendable {
        case incompleteCardinalityTranslations = "INCOMPLETE_CARDINALITY_TRANSLATIONS"
        case incompleteOrdinalityTranslations = "INCOMPLETE_ORDINALITY_TRANSLATIONS"
        case invalidLocaleFilename = "INVALID_CLASSPATH_LOCALE_FILENAME"
    }
    public let type: WarningType
    public let source: String
    public let locale: String?
    public let key: ExactString?
    public let placeholder: ExactString?
    public let missingLanguageForms: [String]
    public let message: String

    package init(type: WarningType, source: String, locale: String?, key: ExactString?, placeholder: ExactString?,
                 missingLanguageForms: [String], message: String) {
        self.type = type
        self.source = source
        self.locale = locale
        self.key = key
        self.placeholder = placeholder
        self.missingLanguageForms = missingLanguageForms
        self.message = message
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && ExactString(lhs.source) == ExactString(rhs.source)
        && lhs.locale.map { ExactString($0) } == rhs.locale.map { ExactString($0) }
        && lhs.key == rhs.key && lhs.placeholder == rhs.placeholder
        && lhs.missingLanguageForms.map { ExactString($0) } == rhs.missingLanguageForms.map { ExactString($0) }
        && ExactString(lhs.message) == ExactString(rhs.message)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(type); hasher.combine(ExactString(source)); hasher.combine(locale.map { ExactString($0) })
        hasher.combine(key); hasher.combine(placeholder); hasher.combine(missingLanguageForms.map { ExactString($0) })
        hasher.combine(ExactString(message))
    }
}

/// Synchronous observer for a parsing or loading warning. Throwing aborts the
/// operation; captures must support concurrent and reentrant invocation.
public typealias LocalizedStringWarningHandler = @Sendable (LocalizedStringWarning) throws -> Void
