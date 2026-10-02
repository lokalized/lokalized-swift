public extension Cardinality {
    static func forNumber<Value: BinaryInteger>(_ number: Value, visibleDecimalPlaces: Int? = nil, locale: String,
                                               runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        try forNumber(NumericValue(number), visibleDecimalPlaces: visibleDecimalPlaces, locale: locale, runtimeLimits: runtimeLimits)
    }

    static func forNumber(_ number: Float, visibleDecimalPlaces: Int? = nil, locale: String,
                          runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        try forNumber(.float(number), visibleDecimalPlaces: visibleDecimalPlaces, locale: locale, runtimeLimits: runtimeLimits)
    }

    static func forNumber(_ number: Double, visibleDecimalPlaces: Int? = nil, locale: String,
                          runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        try forNumber(.double(number), visibleDecimalPlaces: visibleDecimalPlaces, locale: locale, runtimeLimits: runtimeLimits)
    }

    static func forNumber(_ number: ExactDecimal, visibleDecimalPlaces: Int? = nil, locale: String,
                          runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        try forNumber(.decimal(number), visibleDecimalPlaces: visibleDecimalPlaces, locale: locale, runtimeLimits: runtimeLimits)
    }

    static func forNumber(_ number: NumericValue, visibleDecimalPlaces: Int? = nil, locale: String,
                          runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> Self {
        let operands = try PluralOperands(number, visibleDecimalPlaces: visibleDecimalPlaces, runtimeLimits: runtimeLimits)
        return try forOperands(operands, locale: locale)
    }

    static func forOperands(_ operands: PluralOperands, locale: String) throws -> Self {
        Self.allCases[try PluralRules.classify(operands, locale: PluralLocale(locale), ordinal: false)]
    }

    static func forRange(_ start: Self, _ end: Self, locale: String) throws -> Self {
        let startIndex = Self.allCases.firstIndex(of: start)!
        let endIndex = Self.allCases.firstIndex(of: end)!
        return Self.allCases[try PluralRules.range(startIndex, endIndex, locale: PluralLocale(locale))]
    }

    /// Enum-ordered categories. An unsupported well-formed locale returns [].
    static func supportedCardinalitiesForLocale(_ locale: String) throws -> [Self] {
        guard let group = PluralRules.group(try PluralLocale(locale), ordinal: false) else { return [] }
        return group.rules.map { Self.allCases[$0.category] }
    }

    static func exampleIntegerValuesForLocale(_ locale: String) throws -> [Self: Range<Int>] {
        guard let group = PluralRules.group(try PluralLocale(locale), ordinal: false) else { return [:] }
        var examples: [Self: Range<Int>] = [:]
        for rule in group.rules where !rule.integerSamples.isEmpty {
            examples[Self.allCases[rule.category]] = .init(
                values: rule.integerSamples.split(separator: " ").map { Int($0)! }, isInfinite: rule.integerInfinite)
        }
        return examples
    }

    static func exampleDecimalValuesForLocale(_ locale: String) throws -> [Self: Range<ExactDecimal>] {
        guard let group = PluralRules.group(try PluralLocale(locale), ordinal: false) else { return [:] }
        var examples: [Self: Range<ExactDecimal>] = [:]
        for rule in group.rules where !rule.decimalSamples.isEmpty {
            examples[Self.allCases[rule.category]] = .init(
                values: try rule.decimalSamples.split(separator: " ").map { try ExactDecimal(String($0)) },
                isInfinite: rule.decimalInfinite)
        }
        return examples
    }

    /// Direct pinned rule tags, sorted lexically; und denotes CLDR's root group.
    static func getSupportedLocaleTags() -> [String] { PluralRules.supportedTags(ordinal: false) }
}
