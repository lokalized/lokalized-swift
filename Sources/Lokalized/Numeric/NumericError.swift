/// A refused numeric value, operand option, or exact arithmetic operation.
public struct NumericError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        case invalidArgument
        case invalidDecimal
        case roundingNecessary
    }

    public let kind: Kind
    public let message: String
    public var description: String { message }

    package init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}
