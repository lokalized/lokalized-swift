/// Exhaustive nonoptional handler decision. Replacement strings are verbatim.
public enum TranslationFailureResponse: Hashable, Sendable {
    /// Display the requested key using the runtime's bounded key interpolation and bidi handling.
    case returnKey
    /// Display the associated replacement string verbatim; it is not interpolated.
    case returnString(String)
    /// Throw the retained resolution cause, or `MissingTranslationError` if no resolution cause exists.
    case throwException
    /// Compares the stored values for equality, preserving exact catalog-text spelling where applicable.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.returnKey, .returnKey), (.throwException, .throwException): true
        case (.returnString(let left), .returnString(let right)): ExactString(left) == ExactString(right)
        default: false
        }
    }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .returnKey: hasher.combine(0)
        case .returnString(let text): hasher.combine(1); hasher.combine(ExactString(text))
        case .throwException: hasher.combine(2)
        }
    }
}
