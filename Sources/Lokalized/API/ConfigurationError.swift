/// Invalid inputs or catalog configuration supplied to `DefaultStrings`.
/// Inspect `kind` for the category and `cause` for an underlying error.
public final class ConfigurationError: Error, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Sendable {
        /// An `invalidArgument` means a supplied setting is invalid; `invalidState` means the supplied configuration cannot construct a usable runtime.
        case invalidArgument, invalidState
    }
    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The underlying error, if one was supplied.
    public let cause: (any Error)?
    /// Creates a construction or configuration error with an optional underlying cause.
    public init(kind: Kind, message: String, cause: (any Error)? = nil) {
        self.kind = kind; self.message = message; self.cause = cause
    }
    /// The diagnostic message.
    public var description: String { message }
}
