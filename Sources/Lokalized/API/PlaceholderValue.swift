/// An application value with explicit, bounded display conversion.
/// Custom values remain unsupported expression/selector operands. Pass formatted
/// text as `.text` when it should be available to a phonetic resolver.
public protocol PlaceholderConvertible: Sendable {
    /// The type name used in diagnostics; the default is the Swift type name.
    var lokalizedTypeName: String { get }
    /// Returns display text for interpolation.
    ///
    /// `maximumCharacters` is the remaining UTF-16 output budget, or `nil` when no budget is provided.
    /// Honor it to avoid allocating oversized text. Conversion errors propagate as resolution failures.
    /// Custom values cannot serve as expression, plural, language-form, or phonetic selector operands.
    func lokalizedDescription(maximumCharacters: Int?) throws -> String
}

public extension PlaceholderConvertible {
    /// The type name used in diagnostics; the default is the Swift type name.
    var lokalizedTypeName: String { String(describing: Self.self) }
}

/// Typed caller values used by expressions, interpolation, and form selection.
/// Explicit null differs from an absent dictionary key. Integer widths remain
/// available in type diagnostics; generated fragments are defined by the catalog.
public enum PlaceholderValue: Sendable {
    /// An explicit null value. It remains distinct from an absent placeholder name.
    case null
    /// Caller-supplied text, available to interpolation and phonetic selection.
    case text(String)
    /// A Boolean value for expressions and display as `true` or `false`.
    case boolean(Bool)
    /// A typed numeric input for expressions, interpolation, and plural selection.
    case number(NumericValue)
    /// A signed 8-bit integer, preserving its width in type diagnostics.
    case byte(Int8)
    /// A signed 16-bit integer, preserving its width in type diagnostics.
    case short(Int16)
    /// A signed 32-bit integer, preserving its width in type diagnostics.
    case integer(Int32)
    /// Precomputed plural operands, including visible decimal places and any compact exponent.
    case pluralOperands(PluralOperands)
    /// An explicit grammatical, phonetic, or plural category.
    case languageForm(LanguageFormValue)
    /// An application value with bounded display conversion. Custom values are not selector or expression operands.
    case custom(any PlaceholderConvertible)

    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: String) { self = .text(value) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: Bool) { self = .boolean(value) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: NumericValue) { self = .number(value) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: ExactDecimal) { self = .number(.decimal(value)) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: Float) { self = .number(.float(value)) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: Double) { self = .number(.double(value)) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: PluralOperands) { self = .pluralOperands(value) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
    public init(_ value: LanguageFormValue) { self = .languageForm(value) }
    /// Wraps a typed caller value for expressions, interpolation, or language-form selection. Integer widths are preserved when applicable.
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
