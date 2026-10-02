public extension Ordinality {
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
        Self.allCases[try PluralRules.classify(operands, locale: PluralLocale(locale), ordinal: true)]
    }

    /// Enum-ordered categories. Cardinal-supported locales without an explicit
    /// ordinal group have OTHER; unsupported locales return [].
    static func supportedOrdinalitiesForLocale(_ locale: String) throws -> [Self] {
        guard let group = PluralRules.group(try PluralLocale(locale), ordinal: true) else { return [] }
        return group.rules.map { Self.allCases[$0.category] }
    }

    static func exampleIntegerValuesForLocale(_ locale: String) throws -> [Self: Range<Int>] {
        guard let group = PluralRules.group(try PluralLocale(locale), ordinal: true) else { return [:] }
        var examples: [Self: Range<Int>] = [:]
        for rule in group.rules where !rule.integerSamples.isEmpty {
            examples[Self.allCases[rule.category]] = .init(
                values: rule.integerSamples.split(separator: " ").map { Int($0)! }, isInfinite: rule.integerInfinite)
        }
        return examples
    }

    /// Union of direct cardinal and ordinal tags: cardinal support guarantees
    /// ordinal OTHER fallback even when no explicit ordinal group exists.
    static func getSupportedLocaleTags() -> [String] { PluralRules.supportedTags(ordinal: true) }
}
