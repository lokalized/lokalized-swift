/// A failure locating or reading an explicitly requested local resource.
/// Catalog decoding and limit failures remain `StringsParseError`; errors thrown
/// by a warning handler propagate unchanged.
public final class LocalizedStringLoadingError: Error, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Sendable {
        /// An `io` failure prevents reading content; `discovery` prevents resource enumeration; `invalidResource` rejects a resource path or kind; `duplicateLocale` means two discovered resources identify the same locale.
        case io, discovery, invalidResource, duplicateLocale
    }
    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The resource path or source label associated with the loading failure.
    public let source: String
    /// The underlying error, if one was supplied.
    public let cause: (any Error)?
    /// The diagnostic message.
    public var description: String { message }

    /// Creates a local-resource loading error with a source label and optional underlying cause.
    public init(message: String, source: String, cause: (any Error)? = nil, kind: Kind = .io) {
        self.kind = kind; self.message = message; self.source = source; self.cause = cause
    }
}
