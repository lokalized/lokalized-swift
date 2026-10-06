/// A failure evaluating an expression, selecting a generated fragment, or
/// interpolating a translation. Inspect `kind`, `message`, and `cause` to
/// understand the failed operation.
public final class TranslationEvaluationError: Error, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Sendable {
        /// An `expression` failure concerns expression evaluation; `invalidArgument` rejects a supplied value; `invalidState` identifies a translation state that cannot be resolved.
        case expression, invalidArgument, invalidState
    }
    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The underlying error, if one was supplied.
    public let cause: (any Error)?
    /// The diagnostic message.
    public var description: String { message }

    /// Creates an evaluation error with its category, message, and optional underlying cause.
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
