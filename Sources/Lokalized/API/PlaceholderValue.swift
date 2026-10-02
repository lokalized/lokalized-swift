/// An application value with explicit, bounded display conversion.
/// Custom values remain unsupported expression/selector operands. Pass formatted
/// text as `.text` when it should be available to a phonetic resolver.
public protocol PlaceholderConvertible: Sendable {
    var lokalizedTypeName: String { get }
    func lokalizedDescription(maximumCharacters: Int?) throws -> String
}

public extension PlaceholderConvertible {
    var lokalizedTypeName: String { String(describing: Self.self) }
}

/// Raw caller values, kept separate from generated translation fragments.
/// Explicit null differs from an absent dictionary key. Integral widths remain
/// available for the reference's observable runtime type diagnostics.
public enum PlaceholderValue: Sendable {
    case null
    case text(String)
    case boolean(Bool)
    case number(NumericValue)
    case byte(Int8)
    case short(Int16)
    case integer(Int32)
    case pluralOperands(PluralOperands)
    case languageForm(LanguageFormValue)
    case custom(any PlaceholderConvertible)

    public init(_ value: String) { self = .text(value) }
    public init(_ value: Bool) { self = .boolean(value) }
    public init(_ value: NumericValue) { self = .number(value) }
    public init(_ value: ExactDecimal) { self = .number(.decimal(value)) }
    public init(_ value: Float) { self = .number(.float(value)) }
    public init(_ value: Double) { self = .number(.double(value)) }
    public init(_ value: PluralOperands) { self = .pluralOperands(value) }
    public init(_ value: LanguageFormValue) { self = .languageForm(value) }
    public init<Value: BinaryInteger>(_ value: Value) {
        if let value = value as? Int8 { self = .byte(value) }
        else if let value = value as? Int16 { self = .short(value) }
        else if let value = value as? Int32 { self = .integer(value) }
        else { self = .number(NumericValue(value)) }
    }
}

package extension PlaceholderValue {
    var isMissing: Bool { if case .null = self { true } else { false } }
    var number: NumericValue? {
        switch self {
        case .number(let value): value
        case .byte(let value): .integer(Int64(value))
        case .short(let value): .integer(Int64(value))
        case .integer(let value): .integer(Int64(value))
        default: nil
        }
    }
    var pluralOperands: PluralOperands? { if case .pluralOperands(let value) = self { value } else { nil } }
    var languageForm: LanguageFormValue? { if case .languageForm(let value) = self { value } else { nil } }
    var diagnosticTypeName: String {
        switch self {
        case .null: "null"
        case .text: "String"
        case .boolean: "Boolean"
        case .byte: "Byte"
        case .short: "Short"
        case .integer: "Integer"
        case .pluralOperands: "PluralOperands"
        case .languageForm(let value):
            switch value {
            case .cardinality: "Cardinality"
            case .ordinality: "Ordinality"
            case .gender: "Gender"
            case .grammaticalCase: "GrammaticalCase"
            case .definiteness: "Definiteness"
            case .classifier: "Classifier"
            case .formality: "Formality"
            case .clusivity: "Clusivity"
            case .animacy: "Animacy"
            case .phonetic: "Phonetic"
            }
        case .custom(let value): value.lokalizedTypeName
        case .number(let value):
            switch value {
            case .integer: "Long"
            case .unsignedInteger: "BigInteger"
            case .bigInteger: "BigInteger"
            case .decimal: "BigDecimal"
            case .float: "Float"
            case .double: "Double"
            }
        }
    }

    /// Nil lets interpolation retain an unresolved null reference. Limits are
    /// checked by the output scanner; a custom converter receives the remaining
    /// budget so it can avoid constructing a needlessly large display value.
    func interpolationText(maximumCharacters: Int = -1) throws -> String? {
        switch self {
        case .null: nil
        case .text(let value): value
        case .boolean(let value): value ? "true" : "false"
        case .byte(let value): String(value)
        case .short(let value): String(value)
        case .integer(let value): String(value)
        case .number(let value): value.description
        case .pluralOperands(let value): value.description
        case .languageForm(let value): value.displayName
        case .custom(let value): try value.lokalizedDescription(maximumCharacters: maximumCharacters < 0 ? nil : maximumCharacters)
        }
    }
    func phoneticTerm(maximumCharacters: Int, description: String) throws -> String? {
        guard case .text(let value) = self else { return nil }
        guard value.utf16.count <= maximumCharacters else {
            throw TranslationEvaluationError(kind: .invalidArgument,
                message: "\(description) exceeds the maximum of \(maximumCharacters) characters")
        }
        return value
    }
}
