/// An immutable warning delivered in catalog declaration order.
public struct LocalizedStringWarning: Hashable, Sendable {
    /// The kind of nonfatal catalog or resource-discovery warning.
    public enum WarningType: String, CaseIterable, Hashable, Sendable {
        /// A generated cardinal fragment omits categories supported by its catalog locale.
        case incompleteCardinalityTranslations = "INCOMPLETE_CARDINALITY_TRANSLATIONS"
        /// A generated ordinal fragment omits categories supported by its catalog locale.
        case incompleteOrdinalityTranslations = "INCOMPLETE_ORDINALITY_TRANSLATIONS"
        /// A discovered resource name does not identify a recognized catalog locale and was skipped.
        case invalidLocaleFilename = "INVALID_CLASSPATH_LOCALE_FILENAME"
    }
    /// The warning category.
    public let type: WarningType
    /// The source label or resource path that produced the warning.
    public let source: String
    /// The catalog locale tag, when known.
    public let locale: String?
    /// The exact localized entry key, when the warning concerns an entry.
    public let key: ExactString?
    /// The generated-placeholder name, when the warning concerns a placeholder.
    public let placeholder: ExactString?
    /// The missing plural category tokens in deterministic order.
    public let missingLanguageForms: [String]
    /// The diagnostic explanation of the warning.
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

    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type && ExactString(lhs.source) == ExactString(rhs.source)
        && lhs.locale.map { ExactString($0) } == rhs.locale.map { ExactString($0) }
        && lhs.key == rhs.key && lhs.placeholder == rhs.placeholder
        && lhs.missingLanguageForms.map { ExactString($0) } == rhs.missingLanguageForms.map { ExactString($0) }
        && ExactString(lhs.message) == ExactString(rhs.message)
    }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(type); hasher.combine(ExactString(source)); hasher.combine(locale.map { ExactString($0) })
        hasher.combine(key); hasher.combine(placeholder); hasher.combine(missingLanguageForms.map { ExactString($0) })
        hasher.combine(ExactString(message))
    }
}

/// Synchronous observer for a parsing or loading warning. Throwing aborts the
/// operation; captures must support concurrent and reentrant invocation.
public typealias LocalizedStringWarningHandler = @Sendable (LocalizedStringWarning) throws -> Void
