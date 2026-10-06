/// The two supported kinds of generated-placeholder definitions.
public enum PlaceholderDefinition: Hashable, Sendable {
    /// Generate a fragment using a language form or a cardinality range.
    case languageForm(LanguageFormTranslation)
    /// Generate a fragment using ordered expression alternatives and a default template.
    case expression(ExpressionTranslation)
}

/// A generated fragment selected by a runtime language form or cardinality range.
///
/// Construction retains the supplied map, including an empty map or mixed axes.
/// Catalog validation checks identifiers, templates, a single axis, and whether
/// a range uses cardinality. These are deliberately separate from construction.
public struct LanguageFormTranslation: Hashable, Sendable {
    /// The runtime placeholder or pair of placeholders used to select a form.
    public enum Selector: Hashable, Sendable {
        /// Select a form from the named runtime placeholder.
        case value(ExactString)
        /// Select a cardinality range form from the named start and end placeholders.
        case range(LanguageFormTranslationRange)
    }

    /// The single-value or cardinal-range selector.
    public let selector: Selector
    /// Language-form categories mapped to fragment templates. Catalog validation requires one consistent axis.
    public let translationsByLanguageForm: [LanguageFormValue: String]

    /// Creates a generated fragment selected by the named runtime value or cardinal-range endpoints.
    /// The map is validated for a consistent language-form axis when the catalog is validated.
    public init(value: ExactString, translationsByLanguageForm: [LanguageFormValue: String]) {
        selector = .value(value)
        self.translationsByLanguageForm = translationsByLanguageForm
    }

    /// Creates a generated fragment selected by the named runtime value or cardinal-range endpoints.
    /// The map is validated for a consistent language-form axis when the catalog is validated.
    public init(range: LanguageFormTranslationRange, translationsByLanguageForm: [LanguageFormValue: String]) {
        selector = .range(range)
        self.translationsByLanguageForm = translationsByLanguageForm
    }

    /// The runtime placeholder name for a single-value selector, or `nil` for a range.
    public var value: ExactString? {
        guard case .value(let value) = selector else { return nil }
        return value
    }

    /// The runtime endpoint names for a range selector, or `nil` for a single value.
    public var range: LanguageFormTranslationRange? {
        guard case .range(let range) = selector else { return nil }
        return range
    }

    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.selector == rhs.selector,
              lhs.translationsByLanguageForm.count == rhs.translationsByLanguageForm.count else { return false }
        for (form, translation) in lhs.translationsByLanguageForm {
            guard let other = rhs.translationsByLanguageForm[form],
                  CatalogExactText.equals(translation, other) else { return false }
        }
        return true
    }

    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(selector)
        hasher.combine(translationsByLanguageForm.count)
        // A map's equality is independent of insertion order. The closed form
        // set has at most 61 keys, so sorting makes the hash order deterministic.
        let translations = translationsByLanguageForm.sorted {
            $0.key.rawValue.utf16.lexicographicallyPrecedes($1.key.rawValue.utf16)
        }
        for (form, translation) in translations {
            hasher.combine(form)
            CatalogExactText.hash(translation, into: &hasher)
        }
    }
}

/// Runtime placeholder names used as the start and end of a cardinality range.
public struct LanguageFormTranslationRange: Hashable, Sendable {
    /// The runtime placeholder containing the range's start quantity.
    public let start: ExactString
    /// The runtime placeholder containing the range's end quantity.
    public let end: ExactString

    /// Creates the names of the runtime placeholders containing a cardinal range's endpoints.
    public init(start: ExactString, end: ExactString) {
        self.start = start
        self.end = end
    }
}

/// A scoped generated fragment with a default template and ordered alternatives.
public struct ExpressionTranslation: Hashable, Sendable {
    /// The default generated-fragment template used when no alternative matches.
    public let translation: String
    /// Expression alternatives tested in authored order.
    public let alternatives: [ExpressionAlternative]

    /// Creates a translation-only fragment. Empty translations are valid values.
    public init(translation: String) {
        self.translation = translation
        alternatives = []
    }

    /// Creates a fragment with at least one ordered expression alternative.
    /// Expression and template syntax are checked when the catalog is validated.
    public init(translation: String, alternatives: [ExpressionAlternative]) throws {
        guard !alternatives.isEmpty else {
            throw CatalogModelError(reason: .emptyExpressionAlternatives)
        }
        self.translation = translation
        self.alternatives = alternatives
    }

    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        CatalogExactText.equals(lhs.translation, rhs.translation) && lhs.alternatives == rhs.alternatives
    }

    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        CatalogExactText.hash(translation, into: &hasher)
        hasher.combine(alternatives)
    }
}

/// One ordered expression-driven alternative inside a generated fragment.
public struct ExpressionAlternative: Hashable, Sendable {
    /// The expression evaluated to decide whether this alternative applies.
    public let expression: ExactString
    /// The generated-fragment template used when the expression evaluates to true.
    public let translation: String

    /// Creates an expression alternative and its fragment template. Syntax is checked during catalog validation.
    public init(expression: ExactString, translation: String) {
        self.expression = expression
        self.translation = translation
    }

    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.expression == rhs.expression && CatalogExactText.equals(lhs.translation, rhs.translation)
    }

    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(expression)
        CatalogExactText.hash(translation, into: &hasher)
    }
}
