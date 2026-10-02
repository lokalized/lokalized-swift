/// A value-construction error, separate from catalog schema and expression errors.
public struct CatalogModelError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Reason: Hashable, Sendable {
        case missingTranslationOrAlternative(key: ExactString)
        case emptyExpressionAlternatives
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }

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
