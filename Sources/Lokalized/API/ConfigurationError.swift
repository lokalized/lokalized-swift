/// Native construction refusal, retaining its argument/state category and cause.
public final class ConfigurationError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case invalidArgument, invalidState }
    public let kind: Kind
    public let message: String
    public let cause: (any Error)?
    public init(kind: Kind, message: String, cause: (any Error)? = nil) {
        self.kind = kind; self.message = message; self.cause = cause
    }
    public var description: String { message }
}
