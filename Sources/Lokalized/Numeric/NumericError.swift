/// A refused numeric value, operand option, or exact arithmetic operation.
public struct NumericError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The category of the failure.
    public enum Kind: String, Sendable {
        /// A numeric value or conversion option is outside its allowed limits.
        case invalidArgument
        /// The source text is not a valid decimal or integer representation.
        case invalidDecimal
        /// The requested exact operation would discard nonzero digits.
        case roundingNecessary
    }

    /// The category of the failure.
    public let kind: Kind
    /// The diagnostic explanation of the failure.
    public let message: String
    /// The diagnostic message.
    public var description: String { message }

    package init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}
