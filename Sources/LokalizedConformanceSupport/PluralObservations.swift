import Lokalized

/// Translates only the frozen oracle's explicit numeric carriers and error
/// types. Every result comes from the public Swift numeric/plural APIs.
enum PluralObservations {
    static let operations: Set<String> = [
        "cardinalityForNumber", "cardinalityForOperands", "cardinalityForRange",
        "ordinalityForNumber", "ordinalityForOperands",
        "supportedCardinalitiesForLocale", "supportedOrdinalitiesForLocale"
    ]

    static func execute(_ row: BehavioralCase) throws -> JSONValue {
        let allowed: Set<String>
        switch row.operation {
        case "cardinalityForNumber": allowed = ["locale", "value", "visibleDecimalPlaces"]
        case "ordinalityForNumber", "cardinalityForOperands", "ordinalityForOperands": allowed = ["locale", "value"]
        case "cardinalityForRange": allowed = ["locale", "start", "end"]
        case "supportedCardinalitiesForLocale", "supportedOrdinalitiesForLocale": allowed = ["locale"]
        default: throw ConformanceError("Unregistered plural operation: \(row.operation)")
        }
        let input = try row.input.checkedObject(at: "plural.input", allowed: allowed)
        let locale = LocaleTag.forLanguageTag(try input.string("locale", at: "plural.input")).tag
        do {
            switch row.operation {
            case "cardinalityForNumber":
                let number = try numericValue(input.value("value", at: "plural.input"))
                let form = try Cardinality.forNumber(number, visibleDecimalPlaces: optionalInteger(input["visibleDecimalPlaces"]), locale: locale)
                return classification(form, axis: "cardinality")
            case "ordinalityForNumber":
                return classification(try Ordinality.forNumber(numericValue(input.value("value", at: "plural.input")), locale: locale), axis: "ordinality")
            case "cardinalityForOperands":
                return classification(try Cardinality.forOperands(operands(input.value("value", at: "plural.input")), locale: locale), axis: "cardinality")
            case "ordinalityForOperands":
                return classification(try Ordinality.forOperands(operands(input.value("value", at: "plural.input")), locale: locale), axis: "ordinality")
            case "cardinalityForRange":
                return classification(try Cardinality.forRange(cardinality(input.value("start", at: "plural.input")), cardinality(input.value("end", at: "plural.input")), locale: locale), axis: "cardinality")
            case "supportedCardinalitiesForLocale":
                return .object([.test("classifications", .array(try Cardinality.supportedCardinalitiesForLocale(locale).map { formObservation($0, axis: "cardinality") }))])
            case "supportedOrdinalitiesForLocale":
                return .object([.test("classifications", .array(try Ordinality.supportedOrdinalitiesForLocale(locale).map { formObservation($0, axis: "ordinality") }))])
            default: throw ConformanceError("Unregistered plural operation")
            }
        } catch let error as NumericError {
            let type: String
            switch error.kind {
            case .invalidArgument: type = "java.lang.IllegalArgumentException"
            case .invalidDecimal: type = "java.lang.NumberFormatException"
            case .roundingNecessary: type = "java.lang.ArithmeticException"
            }
            return thrown(type: type, message: error.message)
        } catch let error as UnsupportedLocaleError {
            return thrown(type: "com.lokalized.UnsupportedLocaleException", message: error.message)
        }
    }

    private static func numericValue(_ value: JSONValue) throws -> NumericValue {
        let fields = try value.checkedObject(at: "numeric.value", allowed: ["$lokalized", "value"])
        try fields.requireKeys(["$lokalized", "value"], at: "numeric.value")
        let text = try fields.string("value", at: "numeric.value")
        switch try fields.string("$lokalized", at: "numeric.value") {
        case "integer":
            guard let value = Int32(text) else { throw ConformanceError("Malformed Java Integer carrier") }
            return .integer(Int64(value))
        case "long":
            guard let value = Int64(text) else { throw ConformanceError("Malformed Java Long carrier") }
            return .integer(value)
        case "bigint": return try .forBigInteger(text)
        case "decimal": return try .forDecimal(text)
        case "float":
            guard let value = Float(text) else { throw ConformanceError("Malformed Java Float carrier") }
            return .float(value)
        case "double":
            guard let value = Double(text) else { throw ConformanceError("Malformed Java Double carrier") }
            return .double(value)
        default: throw ConformanceError("Unknown or nonnumeric carrier")
        }
    }

    private static func operands(_ value: JSONValue) throws -> PluralOperands {
        let fields = try value.checkedObject(at: "plural.operands", allowed: ["$lokalized", "value", "visibleDecimalPlaces", "compactExponent"])
        try fields.requireKeys(["$lokalized", "value"], at: "plural.operands")
        guard try fields.string("$lokalized", at: "plural.operands") == "plural-operands" else {
            throw ConformanceError("Expected plural-operands carrier")
        }
        return try PluralOperands(.forDecimal(fields.string("value", at: "plural.operands")),
                                  visibleDecimalPlaces: optionalInteger(fields["visibleDecimalPlaces"]),
                                  compactExponent: optionalInteger(fields["compactExponent"]))
    }

    private static func cardinality(_ value: JSONValue) throws -> Cardinality {
        let fields = try value.checkedObject(at: "range.form", allowed: ["$lokalized", "axis", "name", "renderName"])
        try fields.requireKeys(["$lokalized", "axis", "name"], at: "range.form")
        guard try fields.string("$lokalized", at: "range.form") == "language-form",
              try fields.string("axis", at: "range.form") == "cardinality",
              let form = Cardinality(rawValue: try fields.string("name", at: "range.form")) else {
            throw ConformanceError("Invalid range cardinality carrier")
        }
        if let renderName = fields["renderName"] {
            guard case .string(let text) = renderName, ExactString(text) == ExactString(form.displayName) else {
                throw ConformanceError("Inconsistent range cardinality renderName")
            }
        }
        return form
    }

    private static func optionalInteger(_ value: JSONValue?) throws -> Int? {
        guard let value else { return nil }
        if case .null = value { return nil }
        guard case .number(let literal) = value, let result = Int(literal) else {
            throw ConformanceError("Operand option must be an integer or null")
        }
        return result
    }

    private static func formObservation<Form: LanguageForm>(_ form: Form, axis: String) -> JSONValue {
        .object([.test("axis", .string(axis)), .test("name", .string(form.rawValue)), .test("renderName", .string(form.displayName))])
    }
    private static func classification<Form: LanguageForm>(_ form: Form, axis: String) -> JSONValue {
        .object([.test("classification", formObservation(form, axis: axis))])
    }
    private static func thrown(type: String, message: String) -> JSONValue {
        .object([.test("thrown", .object([
            .test("causeType", .null), .test("identicalToRetainedCause", .null),
            .test("message", .string(message)), .test("type", .string(type))
        ]))])
    }
}
