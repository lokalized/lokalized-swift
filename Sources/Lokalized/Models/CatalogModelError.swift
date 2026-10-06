/// A value-construction error, separate from catalog schema and expression errors.
public struct CatalogModelError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Why a programmatically created translation model is invalid.
    public enum Reason: Hashable, Sendable {
        /// The associated key has neither a translation nor a whole-message alternative.
        case missingTranslationOrAlternative(key: ExactString)
        /// An expression fragment initializer received an empty alternative list. Use its translation-only initializer instead.
        case emptyExpressionAlternatives
    }

    /// The model-construction failure category.
    public let reason: Reason

    /// Creates a programmatic-model error with the supplied reason.
    public init(reason: Reason) {
        self.reason = reason
    }

    /// The diagnostic explanation of the invalid model.
    public var description: String {
        switch reason {
        case .missingTranslationOrAlternative(let key):
            "You must provide either a translation or at least one alternative expression. Offending key was '\(key.string)'"
        case .emptyExpressionAlternatives:
            "alternatives must not be empty; use ExpressionTranslation(String) for a translation-only fragment"
        }
    }
}

/// Standard String equality/hashing normalizes Unicode. Catalog text must not.
enum CatalogExactText {
    static func equals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }

    static func equalsOptional(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let left), .some(let right)): equals(left, right)
        default: false
        }
    }

    static func hash(_ value: String, into hasher: inout Hasher) {
        hasher.combine(value.utf16.count)
        for codeUnit in value.utf16 { hasher.combine(codeUnit) }
    }

    static func hashOptional(_ value: String?, into hasher: inout Hasher) {
        switch value {
        case .none: hasher.combine(false)
        case .some(let string):
            hasher.combine(true)
            hash(string, into: &hasher)
        }
    }
}
