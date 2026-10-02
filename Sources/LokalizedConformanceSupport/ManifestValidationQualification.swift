import Foundation
import Lokalized

public extension ConformanceRunner {
    /// Native manifest schema/preflight probes, independent of donor corpus cases.
    static func manifestValidationSelfTest() throws -> Int {
        var checks = 0
        func expect(_ value: @autoclosure () throws -> Bool, _ detail: String) throws {
            checks += 1
            guard try value() else { throw ConformanceError("Manifest validation self-test: \(detail)") }
        }
        func failure(_ body: () throws -> Void) throws -> any Error {
            checks += 1
            do { try body() } catch { return error }
            throw ConformanceError("Expected manifest validation refusal")
        }
        func changed(_ input: StringsManifestValue, _ name: ExactString, _ replacement: StringsManifestValue?) -> StringsManifestValue {
            guard case .object(var members) = input else { preconditionFailure("fixture object") }
            members.removeAll { $0.name == name }
            if let replacement { members.append(.init(name: name, value: replacement)) }
            return .object(members)
        }
        func built(files: [ExactString: StringsManifestFile] = ["en": .init(url: "en.json", sha256: String(repeating: "a", count: 64))],
                   fallback: String = "en", ties: [ExactString: [String]] = [:], base: String = "https://cdn.example/v1/") throws -> StringsManifestV1 {
            let identity = try LocalizedStringLoader.computeCatalogIdentity(.init(catalogVersion: "v1", resolvedFallbackLocale: fallback,
                localeToSha256: files.mapValues(\.sha256), tiebreakerLocalesByLanguageCode: ties))
            return .init(catalogVersion: "v1", catalogFingerprint: identity.catalogFingerprint, fallbackLocale: fallback,
                         baseUrl: base, files: files, tiebreakerLocalesByLanguageCode: ties)
        }
        let base = try built()
        let validated = try LocalizedStringLoader.validateStringsManifest(base)
        try expect(validated.catalogFingerprint == base.catalogFingerprint && validated.files.count == 1, "valid typed input")
        try expect(validated.fallbackLocale == "en" && validated.tiebreakerLocalesByLanguageCode.isEmpty, "explicit singleton tiebreakers are not synthesized")
        let decoded = base.decodedValue
        let unknown = changed(decoded, "extra", .object([.init(name: "unrecognized", value: .array([.null]))]))
        try expect(try LocalizedStringLoader.validateStringsManifest(unknown).catalogFingerprint == base.catalogFingerprint, "unknown fields are tolerated and excluded")
        var duplicateMembers: [StringsManifestMember]
        if case .object(let members) = decoded { duplicateMembers = members } else { throw ConformanceError("fixture shape") }
        duplicateMembers.insert(.init(name: "formatVersion", value: .number(2)), at: 0)
        try expect(try LocalizedStringLoader.validateStringsManifest(.object(duplicateMembers)).formatVersion == 1, "semantic duplicate is last value, first property position")
        let shape = try failure { _ = try LocalizedStringLoader.validateStringsManifest(.array([])) }
        try expect((shape as? ConfigurationError)?.message == "A strings manifest must be an object", "semantic shape error category")
        for (field, value, message) in [
            (ExactString("formatVersion"), StringsManifestValue.number(2), "A strings manifest must declare formatVersion 1; received 2"),
            ("catalogVersion", .string(""), "A strings manifest must carry a non-empty catalogVersion"),
            ("catalogFingerprint", .string(String(repeating: "A", count: 64)), "A manifest's catalogFingerprint must be a full lowercase hexadecimal SHA-256")
        ] {
            let error = try failure { _ = try LocalizedStringLoader.validateStringsManifest(changed(decoded, field, value)) }
            try expect((error as? ConfigurationError)?.message == message, "manifest header diagnostic")
        }
        for field: ExactString in ["cldrVersion", "dataFingerprint", "localeDataMode", "cardinalityMode", "behavioralVectorsVersion", "ianaRegistryDate", "ianaDataFingerprint"] {
            let error = try failure { _ = try LocalizedStringLoader.validateStringsManifest(changed(decoded, field, nil)) }
            try expect(error is ConfigurationError, "every required build identity field refuses when missing")
        }
        for (field, value, fragment) in [
            (ExactString("cldrVersion"), StringsManifestValue.string("47"), "published against CLDR 47"),
            ("dataFingerprint", .string(String(repeating: "f", count: 64)), "this build carries CLDR"),
            ("localeDataMode", .string("host"), "localeDataMode must be \"pinned\""),
            ("cardinalityMode", .string("approximate"), "cardinalityMode must be \"exact\""),
            ("behavioralVectorsVersion", .string("99.0.0"), "and vectors 99.0.0"),
            ("ianaRegistryDate", .string("other-identity"), "published against IANA other-identity"),
            ("ianaDataFingerprint", .string(String(repeating: "f", count: 64)), "this build carries")
        ] {
            let error = try failure { _ = try LocalizedStringLoader.validateStringsManifest(changed(decoded, field, value)) }
            try expect((error as? ConfigurationError)?.message.contains(fragment) == true, "each build identity value independently binds compatibility")
        }
        let cldrFirst = changed(changed(decoded, "cldrVersion", .string("47")), "localeDataMode", .string("host"))
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(cldrFirst) } as? ConfigurationError)?.message.contains("published against CLDR") == true,
                   "CLDR mismatch precedes remaining identity shape checks")
        let mismatched = changed(decoded, "catalogFingerprint", .string(String(repeating: "f", count: 64)))
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(mismatched) } as? ConfigurationError)?.message.contains("declared catalogFingerprint does not match") == true,
                   "declared identity is recomputed")
        for baseURL in ["http://localhost:8080/", "https://cdn.example/v1/", "file:///srv/catalogs/"] {
            try expect(try LocalizedStringLoader.validateStringsManifest(built(base: baseURL)).baseUrl == baseURL, "three common manifest schemes and verbatim spelling")
        }
        for baseURL in ["ftp://cdn.example/", "/relative/only"] {
            try expect(try failure { _ = try LocalizedStringLoader.validateStringsManifest(built(base: baseURL)) } is ConfigurationError, "unsupported base scheme or relative base")
        }
        let wrongScheme = try built(files: ["en": .init(url: "ftp://elsewhere.example/en", sha256: String(repeating: "a", count: 64))])
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(wrongScheme) } as? ConfigurationError)?.message.contains("scheme 'ftp:'") == true,
                   "resolved entry scheme checked independently")
        for count in [Double.nan, .infinity, -1, 1.5, 9_007_199_254_740_992] {
            let entry: StringsManifestValue = .object([.init(name: "url", value: .string("en")), .init(name: "sha256", value: .string(String(repeating: "a", count: 64))),
                                                     .init(name: "decodedBytes", value: .number(count))])
            let malformed = changed(decoded, "files", .object([.init(name: "en", value: entry)]))
            try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(malformed) } as? ConfigurationError)?.message == "The decodedBytes for 'en' must be a non-negative integer", "decoded byte safe integer domain")
        }
        let lexicalOne = try built(files: ["en": .init(url: "en", sha256: String(repeating: "a", count: 64), decodedBytes: 9_007_199_254_740_991)])
        try expect(try LocalizedStringLoader.validateStringsManifest(lexicalOne).files["en"]?.decodedBytes == 9_007_199_254_740_991, "safe integer ceiling accepted")
        let twoFiles: [ExactString: StringsManifestFile] = ["en": .init(url: "en", sha256: String(repeating: "a", count: 64)), "fr": .init(url: "fr", sha256: String(repeating: "b", count: 64))]
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(built(files: twoFiles), loadingOptions: .init(maximumLocalizedStringsFiles: 1)) } as? ConfigurationError)?.message == "A manifest declares 2 files, which exceeds the maximum of 1", "file budget before entry work")
        let orderedKeys = changed(decoded, "files", .object([.init(name: "10", value: .null), .init(name: "2", value: .null), .init(name: "en", value: .null)]))
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(orderedKeys) } as? ConfigurationError)?.message.contains("is '2'") == true, "ECMA numeric property order")
        let equalNormalized = changed(decoded, "files", .object([
            .init(name: "EN", value: .object([.init(name: "url", value: .string("en")), .init(name: "sha256", value: .string(String(repeating: "a", count: 64)))])),
            .init(name: "en", value: .null)]))
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(equalNormalized) } as? ConfigurationError)?.message == "A manifest declares two file keys that normalize to 'en'", "normalized duplicate precedes second entry shape")
        let siblings: [ExactString: StringsManifestFile] = ["en": .init(url: "en", sha256: String(repeating: "a", count: 64)), "en-US": .init(url: "us", sha256: String(repeating: "b", count: 64))]
        let legalTies = try built(files: siblings, ties: ["en": ["en-US", "en"]])
        try expect(try LocalizedStringLoader.validateStringsManifest(legalTies).tiebreakerLocalesByLanguageCode["en"] == ["en-US", "en"], "authored complete tiebreaker order")
        for ties: [ExactString: [String]] in [[:], ["en": ["en"]], ["en": ["en-US", "en-US"]], ["fr": ["fr"]]] {
            try expect(try failure { _ = try LocalizedStringLoader.validateStringsManifest(built(files: siblings, ties: ties)) } is ConfigurationError, "full declared-manifest tie validation")
        }
        let overwrittenTies = changed(legalTies.decodedValue, "tiebreakerLocalesByLanguageCode", .object([
            .init(name: "EN", value: .array([.string("en"), .string("en-US")])),
            .init(name: "en", value: .array([.string("en-US"), .string("en")]))]))
        try expect(try LocalizedStringLoader.validateStringsManifest(overwrittenTies).tiebreakerLocalesByLanguageCode["en"] == ["en-US", "en"], "normalized tie keys retain last declared order")
        let caseFiles: [ExactString: StringsManifestFile] = ["en-FONIPA": .init(url: "a", sha256: String(repeating: "a", count: 64)), "en-fonipa": .init(url: "b", sha256: String(repeating: "b", count: 64))]
        let caseManifest = try built(files: caseFiles, fallback: "en-FONIPA", ties: ["en": ["en-FONIPA", "en-fonipa"]])
        try expect(try LocalizedStringLoader.validateStringsManifest(caseManifest).files.count == 2, "manifest exact case variants do not inherit stricter Java runtime duplicate guard")
        let soleAlias = try built(files: ["deu": .init(url: "de", sha256: String(repeating: "a", count: 64))], fallback: "deu")
        try expect(try LocalizedStringLoader.validateStringsManifest(changed(soleAlias.decodedValue, "fallbackLocale", .string("de"))).fallbackLocale == "deu", "sole CLDR equivalent fallback elects authored tag")
        let german: [ExactString: StringsManifestFile] = ["de": .init(url: "de", sha256: String(repeating: "a", count: 64)), "deu": .init(url: "deu", sha256: String(repeating: "b", count: 64))]
        try expect(try LocalizedStringLoader.validateStringsManifest(built(files: german, fallback: "de", ties: ["de": ["deu", "de"]])).fallbackLocale == "de", "exact fallback beats alias tiebreaker")
        let und: [ExactString: StringsManifestFile] = ["und-bokmal": .init(url: "a", sha256: String(repeating: "a", count: 64)), "und-nynorsk": .init(url: "b", sha256: String(repeating: "b", count: 64))]
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(changed(built(files: und, fallback: "und-bokmal").decodedValue, "fallbackLocale", .string("und"))) } as? ConfigurationError)?.message.contains("declare it as one of them exactly") == true, "undetermined ambiguity gives usable exact spelling remedy")
        let privateManifest = try built(files: ["en": .init(url: "e", sha256: String(repeating: "a", count: 64)), "x-a": .init(url: "a", sha256: String(repeating: "b", count: 64)), "x-b": .init(url: "b", sha256: String(repeating: "c", count: 64)), "und": .init(url: "u", sha256: String(repeating: "d", count: 64))])
        try expect(try LocalizedStringLoader.validateStringsManifest(privateManifest).files.count == 4, "private-use and undetermined tags need no broad-language tiebreakers")
        let badFallback = changed(decoded, "fallbackLocale", .string("fr"))
        try expect((try failure { _ = try LocalizedStringLoader.validateStringsManifest(badFallback) } as? ConfigurationError)?.message == "A manifest's fallbackLocale is 'fr' but no matching catalog was declared. Known locales: [en]", "zero-equivalent fallback diagnostic before fingerprint")
        let syntaxCases: [(String, Int, Int, Int, String)] = [
            (#"{"x":"\q"}"#, 1, 8, 7, "Invalid string escape"),
            ("{\r\n\"😀\":\"\\q\"}", 2, 8, 10, "Invalid string escape"),
            ("{\"x\":\"\\\n\"}", 1, 8, 7, "Invalid string escape"),
            (#"{"x":"\u00q0"}"#, 1, 11, 10, "Invalid Unicode escape"),
            ("{\r?}", 2, 1, 2, "Expected object member name"),
            ("{\r\n?}", 2, 1, 3, "Expected object member name"),
            ("{\n?}", 2, 1, 2, "Expected object member name")
        ]
        for (text, line, column, offset, reason) in syntaxCases {
            for parse in [
                { try LocalizedStringLoader.parseStringsManifest(text, source: "wire") },
                { try LocalizedStringLoader.parseStringsManifest(Data(text.utf8), source: "wire") }
            ] {
                let error = try failure { _ = try parse() } as? StringsParseError
                let cause = error?.cause as? JSONReadError
                try expect(error?.message == "wire:\(line):\(column): unable to parse localized strings file"
                    && error?.line == line && error?.column == column && cause?.reason == reason
                    && cause?.location == .init(offset: offset, line: line, column: column), "manifest syntax outer/cause cursor is the pinned offending UTF16 unit")
            }
        }
        let unchanged = try failure { _ = try JSONReader.parse(#"{"x":"\q"}"#) } as? JSONReadError
        try expect(unchanged?.location.column == 9, "shared catalog reader cursor remains unchanged")
        return checks
    }
}
