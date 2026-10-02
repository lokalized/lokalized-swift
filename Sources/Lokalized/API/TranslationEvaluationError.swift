/// An immutable, identity-preserving evaluation failure. Swift has no ambient
/// IllegalArgumentException/IllegalStateException hierarchy; the category keeps
/// those reference distinctions explicit through contextual wrappers.
public final class TranslationEvaluationError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case expression, invalidArgument, invalidState }
    public let kind: Kind
    public let message: String
    public let cause: (any Error)?
    public var description: String { message }

    public init(kind: Kind, message: String, cause: (any Error)? = nil) {
        self.kind = kind; self.message = message; self.cause = cause
    }
}

package enum EvaluationErrors {
    static func message(_ error: any Error) -> String {
        switch error {
        case let error as TranslationEvaluationError: error.message
        case let error as ExpressionCompilationError: error.message
        case let error as NumericError: error.message
        case let error as UnsupportedLocaleError: error.message
        case let error as LocaleTagError: error.message
        case let error as PluralLocaleError: error.message
        default: String(describing: error)
        }
    }

    /// Add context only to categories recognized by the reference. An arbitrary
    /// application error, including a custom class instance, travels unchanged.
    static func contextualize(_ error: any Error, message: String) -> any Error {
        if let error = error as? TranslationEvaluationError {
            return TranslationEvaluationError(kind: error.kind, message: message, cause: error)
        }
        if let error = error as? ExpressionCompilationError {
            return TranslationEvaluationError(kind: .expression, message: message, cause: error)
        }
        if let error = error as? NumericError, error.kind != .roundingNecessary {
            return TranslationEvaluationError(kind: .invalidArgument, message: message, cause: error)
        }
        return error
    }
}
