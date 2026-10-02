/// A failure locating or reading an explicitly requested local resource.
/// Catalog decoding and limit failures remain `StringsParseError`; errors thrown
/// by a warning handler propagate unchanged.
public final class LocalizedStringLoadingError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case io, discovery, invalidResource, duplicateLocale }
    public let kind: Kind
    public let message: String
    public let source: String
    public let cause: (any Error)?
    public var description: String { message }

    public init(message: String, source: String, cause: (any Error)? = nil, kind: Kind = .io) {
        self.kind = kind; self.message = message; self.source = source; self.cause = cause
    }
}
