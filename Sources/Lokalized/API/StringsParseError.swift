/// A source-aware failure decoding or validating a Lokalized catalog.
/// Line/column are one-based and present for lexical errors. Path is bounded to
/// 4,096 UTF-16 units and present for duplicate-member diagnostics.
public struct StringsParseError: Error, CustomStringConvertible, Sendable {
    /// The source label or resource path associated with the failure.
    public let source: String
    /// The one-based source line for a lexical error, when available.
    public let line: Int?
    /// The one-based source column for a lexical error, when available.
    public let column: Int?
    /// The JSON object path for a duplicate-member error, when available. Limited to 4,096 UTF-16 code units.
    public let path: String?
    /// The underlying decoding or validation error, when available.
    public let cause: (any Error)?
    /// The source-aware diagnostic explanation.
    public let message: String
    /// The source-aware diagnostic message.
    public var description: String { message }

    package init(message: String, source: String, line: Int? = nil, column: Int? = nil,
                 path: String? = nil, cause: (any Error)? = nil) {
        self.message = message
        self.source = source
        self.line = line
        self.column = column
        self.path = path
        self.cause = cause
    }
}
