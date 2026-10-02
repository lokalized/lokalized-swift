/// A source-aware failure decoding or validating a Lokalized catalog.
/// Line/column are one-based and present for lexical errors. Path is bounded to
/// 4,096 UTF-16 units and present for duplicate-member diagnostics.
public struct StringsParseError: Error, CustomStringConvertible, Sendable {
    public let source: String
    public let line: Int?
    public let column: Int?
    public let path: String?
    public let cause: (any Error)?
    public let message: String
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
