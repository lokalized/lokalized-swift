import Foundation
import Lokalized

public extension ConformanceRunner {
    /// Runs without XCTest so deployment qualification can run at the library's
    /// OS floor. XCTest calls this same body rather than duplicating assertions.
    static func selfTest() throws -> Int {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw ConformanceError("Self-test failed: \(message)") }
            checks += 1
        }
        func rejects(_ message: String, _ action: () throws -> Void) throws {
            var rejected = false
            do { try action() } catch { rejected = true }
            try expect(rejected, message)
        }
        func parse(_ source: String) throws -> JSONValue { try JSONReader.parse(source) }

        let unicode = try parse(#"{"é":1,"e\u0301":2,"emoji":"\uD83D\uDE00","nul":"a\u0000b"}"#)
        let members = try unicode.checkedObject(at: "$")
        try expect(members.count == 4, "canonical-equivalent keys must both survive")
        try expect(members[ExactString("é")].numberLiteral == "1", "composed key value")
        try expect(members[ExactString("e\u{0301}")].numberLiteral == "2", "decomposed key value")
        try expect(ExactString(try members.string("emoji", at: "$")) == ExactString("😀"), "escaped surrogate pair")
        let nul = try members.string("nul", at: "$")
        try expect(Array(nul.utf16) == [97, 0, 98], "embedded NUL must not truncate")

        let duplicate = try parse(#"{"a":1,"\u0061":2}"#)
        guard case .object(let duplicateMembers) = duplicate else { throw ConformanceError("Missing duplicate object") }
        try expect(duplicateMembers.count == 2, "reader must retain exact duplicates for diagnostics")
        try rejects("decoder must reject duplicate member") { _ = try duplicate.checkedObject(at: "$") }
        try rejects("comparison must reject duplicate observation") {
            _ = try JSONComparison.firstDifference(expected: duplicate, actual: duplicate)
        }

        let number = "-123456789012345678901234567890.00100e+1000"
        guard case .number(let literal) = try parse(number) else { throw ConformanceError("Missing numeric literal") }
        try expect(literal == number, "retain decimal lexeme without Double conversion")
        for malformed in ["", "01", "-", "1.", "1e", "1e+", "NaN", "Infinity", "true false", "[1,]", "{\"a\":1,}", "\u{00A0}null"] {
            try rejects("reject malformed JSON \(malformed)") { _ = try parse(malformed) }
        }
        for invalidEscape in [#""\uD800""#, #""\uDC00""#, #""\uD800\u0041""#, #""\uD800x""#, #""\uZZZZ""#, #""\x20""#, "\"a\nb\""] {
            try rejects("reject malformed string \(invalidEscape)") { _ = try parse(invalidEscape) }
        }

        let oneBOM = "\u{FEFF}{\"x\":true}"
        try expect(try JSONComparison.firstDifference(expected: parse(oneBOM), actual: JSONReader.parse(Data(oneBOM.utf8))) == nil,
                   "Data and String accept exactly one leading BOM equally")
        for source in ["\u{FEFF}\u{FEFF}{}", " \u{FEFF}{}"] {
            try rejects("String must reject extra/misplaced BOM") { _ = try parse(source) }
            try rejects("Data must reject extra/misplaced BOM") { _ = try JSONReader.parse(Data(source.utf8)) }
        }
        for bytes: [UInt8] in [[0xC0, 0x80], [0xC2], [0x80], [0xE0, 0x80, 0x80], [0xED, 0xA0, 0x80], [0xF0, 0x80, 0x80, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xF5, 0x80, 0x80, 0x80]] {
            try rejects("strict UTF-8 must reject \(bytes)") { _ = try JSONReader.parse(Data(bytes)) }
        }
        guard case .string(let combining) = try parse("\"}}\u{0301}\""),
              case .string(let interiorBOM) = try parse("\"\u{FEFF}\"") else { throw ConformanceError("Missing string observation") }
        try expect(Array(combining.utf16) == [125, 125, 769], "preserve combining mark after delimiter")
        try expect(Array(interiorBOM.utf16) == [0xFEFF], "BOM inside string is content")

        do {
            _ = try parse("\r\n{\"😀\":0,}")
            throw ConformanceError("Invalid JSON was accepted")
        } catch let error as JSONReadError {
            try expect(error.location == .init(offset: 10, line: 2, column: 9), "UTF-16 offset and CRLF location")
        }
        _ = try JSONReader.parse("[0]", limits: .init(maximumCharacters: 3, maximumDepth: 1, maximumNodes: 2))
        checks += 1
        try rejects("character budget is enforced") { _ = try JSONReader.parse("[0]", limits: .init(maximumCharacters: 2)) }
        try rejects("container nesting budget is enforced") { _ = try JSONReader.parse("[[0]]", limits: .init(maximumDepth: 1)) }
        try rejects("node budget is enforced") { _ = try JSONReader.parse("[0]", limits: .init(maximumNodes: 1)) }
        _ = try JSONReader.parse("\"😀\"", limits: .init(maximumCharacters: 4))
        checks += 1
        try rejects("characters mean UTF-16 rather than graphemes") { _ = try JSONReader.parse("\"😀\"", limits: .init(maximumCharacters: 3)) }

        try expect(try JSONComparison.firstDifference(expected: parse(#"{"a":1,"b":2}"#), actual: parse(#"{"b":2,"a":1}"#)) == nil,
                   "object order does not affect observations")
        for (expected, actual) in [
            (#"{"a":1}"#, #"{"a":1,"ignored":2}"#),
            (#"{"a":1,"required":2}"#, #"{"a":1}"#),
            (#"{"s":"é"}"#, #"{"s":"e\u0301"}"#),
            (#"[1,2]"#, #"[2,1]"#), (#"1"#, #"1.0"#), (#"null"#, #"false"#)
        ] {
            try expect(try JSONComparison.firstDifference(expected: parse(expected), actual: parse(actual)) != nil,
                       "all fields, exact strings, array order, numbers and types must be compared")
        }
        let actualForms = languageFormsObservation()
        let formObject = try actualForms.checkedObject(at: "$")
        guard case .array(let tuples) = try formObject.value("tuples", at: "$") else { throw ConformanceError("Missing forms") }
        try expect(tuples.count == 61, "61 actual library language forms")
        let formCase = BehavioralCase(id: "self.language-forms", operation: "languageForms", partition: "requiredPortableIds", input: .object([]), expected: actualForms)
        try expect(try JSONComparison.firstDifference(expected: actualForms, actual: execute(formCase)!) == nil,
                   "languageForms adapter invokes actual enums")
        let unexpectedInput = BehavioralCase(id: "self.bad-input", operation: "languageForms", partition: "requiredPortableIds", input: .object([.test("unknown", .bool(true))]), expected: actualForms)
        try rejects("implemented operation rejects unknown input fields") { _ = try execute(unexpectedInput) }
        let unknown = BehavioralCase(id: "self.unknown", operation: "futureOperation", partition: "requiredPortableIds", input: .object([]), expected: .object([]))
        try rejects("unknown operation must not pass") { _ = try execute(unknown) }
        let pending = BehavioralCase(id: "self.pending", operation: "loadClasspath", partition: "requiredPortableIds", input: .object([]), expected: actualForms)
        try expect(try execute(pending) == nil, "known unfinished operation remains unimplemented")

        let corpus = try BehavioralCorpus(value: syntheticCorpus(cases: [formCase, pending]))
        let report = try audit(corpus)
        try expect(report.status == "incomplete" && report.runtimePassed == [formCase.id] && report.unimplemented == [pending.id]
                   && report.failed.isEmpty && report.nativeRepresentationMapped.isEmpty,
                   "coverage is exhaustive and incomplete work cannot turn green")
        let failing = BehavioralCase(id: "self.mismatch", operation: "languageForms", partition: "requiredPortableIds", input: .object([]), expected: .object([.test("tuples", .array([]))]))
        let failureReport = try audit(BehavioralCorpus(value: syntheticCorpus(cases: [failing])))
        try expect(failureReport.status == "failed" && failureReport.failed == [failing.id] && failureReport.runtimePassed.isEmpty,
                   "a real observation mismatch is a failure")
        let informational = BehavioralCase(id: "self.informational", operation: "loadClasspath", partition: "informationalIds", input: .object([]), expected: actualForms)
        let portableReport = try audit(BehavioralCorpus(value: syntheticCorpus(cases: [formCase, informational])))
        try expect(portableReport.status == "passed" && portableReport.unimplemented == [informational.id],
                   "informational work is accounted for without blocking required qualification")
        try rejects("zero-case corpus must not pass") { _ = try BehavioralCorpus(value: syntheticCorpus(cases: [])) }
        try rejects("duplicate IDs must be refused") { _ = try BehavioralCorpus(value: syntheticCorpus(cases: [formCase, formCase])) }
        try rejects("unknown operation in corpus must be refused") { _ = try BehavioralCorpus(value: syntheticCorpus(cases: [unknown])) }
        let badPartition = BehavioralCase(id: "self.partition", operation: "parse", partition: "forgottenIds", input: .object([]), expected: actualForms)
        try rejects("unknown partition must be refused") { _ = try BehavioralCorpus(value: syntheticCorpus(cases: [badPartition])) }
        return checks + (try CatalogQualification.run()) + (try NumericQualification.run())
            + (try PluralAdapterQualification.run())
            + (try LocaleAdapterQualification.run())
            + (try LanguageRangeQualification.run())
            + (try matcherSelfTest())
            + (try LocaleDataQualification.run())
            + (try ResolutionComponentQualification.runNative())
            + (try ExpressionQualification.run())
            + (try fragmentSelfTest())
            + (try runtimeSelfTest())
            + (try LocalLoadingQualification.run())
            + (try preferredLanguageSelfTest())
            + (try LoaderQualification.runNative())
            + (try ManifestIdentityQualification.runNative())
            + (try manifestValidationSelfTest())
            + (try manifestPlanningSelfTest())
    }
}

private func syntheticCorpus(cases: [BehavioralCase]) -> JSONValue {
    let fixtureKeys = [
        "bidiIsolation", "constructionOverrides", "description", "entries", "fallbackLocale", "files",
        "instanceLocale", "loadOnly", "loadingOptions", "localeMatchSupplier", "localeSupplier",
        "pathShape", "phoneticResolver", "rawFiles", "rawFilesBase64", "refusesConstruction",
        "runtimeLimits", "tiebreakers", "translationFailureHandler", "translationFallbackPolicy"
    ]
    return .object([
        .test("formatVersion", .number("1")), .test("behavioralVectorsVersion", .string("self-test")),
        .test("oracle", .object([.test("implementation", .string("self-test")), .test("javaVersion", .string("none")), .test("librarySourcesSha256", .string("none"))])),
        .test("fixtures", .object([.test("self-test", .object(fixtureKeys.map { .test($0, .null) }))])),
        .test("cases", .array(cases.map { row in .object([
            .test("id", .string(row.id)), .test("operation", .string(row.operation)), .test("partition", .string(row.partition)),
            .test("fixture", .string("self-test")), .test("input", row.input), .test("expected", row.expected), .test("requirementIds", .array([]))
        ]) }))
    ])
}
