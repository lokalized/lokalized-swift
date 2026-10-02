/// Exhaustive nonoptional handler decision. Replacement strings are verbatim.
public enum TranslationFailureResponse: Hashable, Sendable {
    case returnKey
    case returnString(String)
    case throwException
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.returnKey, .returnKey), (.throwException, .throwException): true
        case (.returnString(let left), .returnString(let right)): ExactString(left) == ExactString(right)
        default: false
        }
    }
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .returnKey: hasher.combine(0)
        case .returnString(let text): hasher.combine(1); hasher.combine(ExactString(text))
        case .throwException: hasher.combine(2)
        }
    }
}
