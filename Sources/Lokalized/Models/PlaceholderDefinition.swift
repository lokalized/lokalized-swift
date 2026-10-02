/// The two supported kinds of generated-placeholder definitions.
public enum PlaceholderDefinition: Hashable, Sendable {
    case languageForm(LanguageFormTranslation)
    case expression(ExpressionTranslation)
}

/// A generated fragment selected by a runtime language form or cardinality range.
///
/// Construction retains the supplied map, including an empty map or mixed axes.
/// Catalog validation checks identifiers, templates, a single axis, and whether
/// a range uses cardinality. These are deliberately separate from construction.
public struct LanguageFormTranslation: Hashable, Sendable {
    public enum Selector: Hashable, Sendable {
        case value(ExactString)
        case range(LanguageFormTranslationRange)
    }

    public let selector: Selector
    public let translationsByLanguageForm: [LanguageFormValue: String]

    public init(value: ExactString, translationsByLanguageForm: [LanguageFormValue: String]) {
        selector = .value(value)
        self.translationsByLanguageForm = translationsByLanguageForm
    }

    public init(range: LanguageFormTranslationRange, translationsByLanguageForm: [LanguageFormValue: String]) {
        selector = .range(range)
        self.translationsByLanguageForm = translationsByLanguageForm
    }

    public var value: ExactString? {
        guard case .value(let value) = selector else { return nil }
        return value
    }

    public var range: LanguageFormTranslationRange? {
        guard case .range(let range) = selector else { return nil }
        return range
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.selector == rhs.selector,
              lhs.translationsByLanguageForm.count == rhs.translationsByLanguageForm.count else { return false }
        for (form, translation) in lhs.translationsByLanguageForm {
            guard let other = rhs.translationsByLanguageForm[form],
                  CatalogExactText.equals(translation, other) else { return false }
        }
        return true
    }

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
    public let start: ExactString
    public let end: ExactString

    public init(start: ExactString, end: ExactString) {
        self.start = start
        self.end = end
    }
}

/// A scoped generated fragment with a default template and ordered alternatives.
public struct ExpressionTranslation: Hashable, Sendable {
    public let translation: String
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

    public static func == (lhs: Self, rhs: Self) -> Bool {
        CatalogExactText.equals(lhs.translation, rhs.translation) && lhs.alternatives == rhs.alternatives
    }

    public func hash(into hasher: inout Hasher) {
        CatalogExactText.hash(translation, into: &hasher)
        hasher.combine(alternatives)
    }
}

/// One ordered expression-driven alternative inside a generated fragment.
public struct ExpressionAlternative: Hashable, Sendable {
    public let expression: ExactString
    public let translation: String

    public init(expression: ExactString, translation: String) {
        self.expression = expression
        self.translation = translation
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.expression == rhs.expression && CatalogExactText.equals(lhs.translation, rhs.translation)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(expression)
        CatalogExactText.hash(translation, into: &hasher)
    }
}
