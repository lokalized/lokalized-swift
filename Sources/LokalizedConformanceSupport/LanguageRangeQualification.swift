import Lokalized

/// Native range qualification independent of XCTest and reference file reads.
enum LanguageRangeQualification {
    static func run() throws -> Int {
        var checks = 0
        func expect(_ condition: @autoclosure () throws -> Bool, _ detail: String) throws {
            guard try condition() else { throw ConformanceError("Language-range qualification: " + detail) }
            checks += 1
        }
        func refuse(_ kind: LanguageRangeError.Kind, _ message: String, _ action: () throws -> Void) throws {
            do { try action() }
            catch let error as LanguageRangeError {
                try expect(error.kind == kind && error.message == message, message)
                return
            }
            throw ConformanceError("Language-range qualification accepted: " + message)
        }
        let upper = try LanguageRange("EN-Us")
        try expect(upper.range == "en-us" && upper.weight == 1 && upper.description == "en-us", "constructor casing without expansion")
        try expect(try LanguageRange("iw").range == "iw", "constructor does not canonicalize aliases")
        try expect(try LanguageRange("x-foo-*").range == "x-foo-*", "one-letter and wildcard subtags")
        try expect(try LanguageRange("\u{212a}").range == "k", "pinned ROOT lowercase Kelvin sign")
        try refuse(.invalidArgument, "weight=2.0") { _ = try LanguageRange("", weight: 2) }
        try refuse(.indexOutOfBounds, "Index 0 out of bounds for length 0") { _ = try LanguageRange("---") }
        try refuse(.invalidArgument, "range=en-") { _ = try LanguageRange("EN-") }
        try refuse(.invalidArgument, "range=") { _ = try LanguageRange("") }
        let positiveZero = try LanguageRange("en", weight: 0)
        let negativeZero = try LanguageRange("en", weight: -0.0)
        try expect(positiveZero == negativeZero && positiveZero.hashValue == negativeZero.hashValue, "signed-zero equality and coherent native hashing")
        try expect(negativeZero.description == "en;q=-0.0", "signed-zero weight spelling")
        let nan = try LanguageRange("en", weight: .nan), copy = nan
        try expect(nan == copy, "NaN identity survives value copying")
        try expect(try nan != LanguageRange("en", weight: .nan), "separate NaN constructors remain unequal")
        let hebrew = try LanguageRangeParser.parse("ACCEPT-LANGUAGE: IW;q=.9,HE;q=.4")
        try expect(hebrew.map(\.range) == ["iw", "he"] && hebrew.allSatisfy { $0.weight == 0.9 }, "equivalence first occurrence owns weight")
        try expect(try LanguageRangeParser.parse("he;q=.4,iw;q=.9").allSatisfy { $0.weight == 0.4 }, "lower first occurrence wins equivalence group")
        try expect(try LanguageRangeParser.parse("sgn-BE-FR").map(\.range) == ["sgn-be-fr", "sgn-sfb", "sfb", "sgn-be-fx"], "reverse insertion order across both equivalence arms")
        try expect(try LanguageRangeParser.parse("de-a-foo-de").map(\.range) == ["de-a-foo-de"], "region rewrite suppressed inside singleton extension")
        try expect(try LanguageRangeParser.parse("yol").map(\.range) == ["yol", "enm"], "2026 IANA registry expansion")
        try expect(try LanguageRangeParser.parse("yol", equivalents: .jdk).map(\.range) == ["yol"], "pinned JDK21 table is observably distinct")
        try expect(try LanguageRangeParser.parse("fr;q=0x1p-1f").first?.weight == 0.5, "hexadecimal numeric weight and suffix")
        try expect(try LanguageRangeParser.parse("fr;q=-1e-99999").first?.weight.bitPattern == 0x8000000000000000, "underflow retains negative zero")
        try expect(try LanguageRangeParser.parse("fr,,").map(\.range) == ["fr"], "trailing empty members dropped")
        try expect(try LanguageRangeParser.parse(",,,").isEmpty, "comma-only Java split yields no members")
        try refuse(.invalidArgument, "range=") { _ = try LanguageRangeParser.parse("fr,,en") }
        try refuse(.invalidArgument, "weight=\"nan\" for language range \"fr\"") { _ = try LanguageRangeParser.parse("fr;q=NaN") }
        try refuse(.invalidArgument, "weight=2.0 for language range \"fr\". It must be between 0.0 and 1.0.") { _ = try LanguageRangeParser.parse("fr;q=1,fr;q=2") }
        try refuse(.invalidArgument, "range=\tfr") { _ = try LanguageRangeParser.parse("en,\tfr") }
        let large = (0..<300).map { "a-\($0)" }.joined(separator: ",")
        try expect(try LanguageRangeParser.parse(large).count == 300, "strict parse applies no matching-list cap")
        try expect(LanguageRangeLowercase.apply("A.\u{3a3}") == "a.\u{3c2}" && LanguageRangeLowercase.apply("A\u{3a3}\u{10400}") == "a\u{3c3}\u{10428}", "ROOT word context final sigma")
        try expect(LanguageRangeLowercase.apply("A\u{3a3}A") == "a\u{3c3}a" && LanguageRangeLowercase.apply("A\u{3a3}\u{10107}A") == "a\u{3c2}\u{10107}a", "ROOT following cased letter keeps sigma")
        return checks
    }
}
