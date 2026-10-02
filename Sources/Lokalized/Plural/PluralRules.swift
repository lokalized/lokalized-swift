package struct PluralRule: Sendable {
    package let category: Int
    package let conditionOffset: Int
    package let integerSamples: String
    package let integerInfinite: Bool
    package let decimalSamples: String
    package let decimalInfinite: Bool
}

package struct PluralRuleGroup: Sendable {
    package let locales: String
    package let rules: [PluralRule]
}

package struct PluralRangeGroup: Sendable {
    package let locales: String
    /// Category indices; 255 means CLDR has no explicit row for this pair.
    package let results: [UInt8]
}

package enum PluralRules {
    private static let cardinalIndex = index(PluralTables.cardinalGroups.map(\.locales))
    private static let ordinalIndex = index(PluralTables.ordinalGroups.map(\.locales))
    private static let rangeIndex = index(PluralTables.rangeGroups.map(\.locales))

    private static func index(_ groups: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: groups.enumerated().flatMap { index, locales in
            locales.split(separator: " ").map { (String($0), index) }
        })
    }

    private static func lookup(_ locale: PluralLocale, in index: [String: Int]) -> Int? {
        for candidate in locale.candidates {
            if let found = index[candidate] { return found }
        }
        return nil
    }

    package static func group(_ locale: PluralLocale, ordinal: Bool) -> PluralRuleGroup? {
        if ordinal {
            if let found = lookup(locale, in: ordinalIndex) { return PluralTables.ordinalGroups[found] }
            // Missing ordinals have OTHER only when cardinal rules support the
            // locale. An unknown language must never silently become OTHER.
            guard lookup(locale, in: cardinalIndex) != nil, let root = ordinalIndex["und"] else { return nil }
            return PluralTables.ordinalGroups[root]
        }
        guard let found = lookup(locale, in: cardinalIndex) else { return nil }
        return PluralTables.cardinalGroups[found]
    }

    package static func classify(_ operands: PluralOperands, locale: PluralLocale, ordinal: Bool) throws -> Int {
        guard let group = group(locale, ordinal: ordinal) else { throw UnsupportedLocaleError(locale: locale.tag) }
        let values = [operands.n, operands.i, .integer(operands.v), .integer(operands.w),
                      operands.f, operands.t, .integer(operands.c), .integer(operands.e)]
        for rule in group.rules {
            if try matches(rule.conditionOffset, values: values) { return rule.category }
        }
        return 5
    }

    /// Executes generator-validated DNF bytecode. No CLDR condition strings are
    /// parsed, and no OS locale/plural implementation participates in evaluation.
    private static func matches(_ offset: Int, values: [ExactDecimal]) throws -> Bool {
        let code = PluralTables.bytecode
        var cursor = offset
        func read() -> Int { defer { cursor += 1 }; return Int(code[cursor]) }
        let disjuncts = read()
        if disjuncts == 0 { return true }
        for _ in 0..<disjuncts {
            let conjuncts = read()
            var all = true
            for _ in 0..<conjuncts {
                let operand = read(), modulus = read(), negated = read() != 0, intervals = read()
                var value = values[operand]
                if all, modulus != 0 { value = try value.remainder(dividingBy: modulus) }
                var contains = false
                for _ in 0..<intervals {
                    let minimum = read(), maximum = read()
                    if all, !contains {
                        if minimum == maximum {
                            contains = value.compare(to: .integer(minimum)) == 0
                        } else if value.isIntegerValued {
                            contains = value.compare(to: .integer(minimum)) >= 0 && value.compare(to: .integer(maximum)) <= 0
                        }
                    }
                }
                if all { all = negated ? !contains : contains }
            }
            if all { return true }
        }
        return false
    }

    package static func range(_ start: Int, _ end: Int, locale: PluralLocale) throws -> Int {
        guard group(locale, ordinal: false) != nil else { throw UnsupportedLocaleError(locale: locale.tag) }
        guard let found = lookup(locale, in: rangeIndex) else { return end }
        let result = Int(PluralTables.rangeGroups[found].results[start * 6 + end])
        return result == 255 ? end : result
    }

    package static func supportedTags(ordinal: Bool) -> [String] {
        var tags = Set(cardinalIndex.keys)
        if ordinal { tags.formUnion(ordinalIndex.keys) }
        return tags.sorted()
    }
}
