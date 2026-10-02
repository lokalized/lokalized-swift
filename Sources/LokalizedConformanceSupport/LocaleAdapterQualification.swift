import Lokalized

enum LocaleAdapterQualification {
    static func run() throws -> Int {
        var checks = 0
        let fixture = try JSONReader.parse(#"{"files":{"en":{},"fr":{}},"rawFiles":{},"rawFilesBase64":{},"loadingOptions":null,"fallbackLocale":"en","tiebreakers":null}"#)
        func row(_ operation: String, _ input: String) throws -> BehavioralCase {
            .init(id: "self.locale", operation: operation, partition: "requiredPortableIds",
                  input: try JSONReader.parse(input), expected: .object([]), fixture: fixture)
        }
        func observation(_ operation: String, _ input: String, _ expected: String) throws {
            guard let actual = try ConformanceRunner.execute(row(operation, input)),
                  try JSONComparison.firstDifference(expected: JSONReader.parse(expected), actual: actual) == nil else {
                throw ConformanceError("Locale adapter self-test mismatch: \(operation)")
            }
            checks += 1
        }
        func refuses(_ operation: String, _ input: String) throws {
            do { _ = try ConformanceRunner.execute(row(operation, input)) }
            catch is ConformanceError { checks += 1; return }
            throw ConformanceError("Locale adapter accepted malformed input: \(operation)")
        }
        try observation("matchFor", #"{"locale":"FR"}"#,
                        #"{"match":{"consideredLocales":["en","fr"],"effectiveWeight":1,"fallbackLocale":"en","isMatch":true,"languageRange":"fr","locale":"fr","matchType":"EXACT","requestedLanguageRanges":[{"range":"fr","weight":1}]}}"#)
        try observation("matchFor", #"{"languageRanges":"fr;q=0.9,en;q=0.3"}"#,
                        #"{"match":{"consideredLocales":["en","fr"],"effectiveWeight":0.9,"fallbackLocale":"en","isMatch":true,"languageRange":"fr","locale":"fr","matchType":"EXACT","requestedLanguageRanges":[{"range":"fr","weight":0.9},{"range":"en","weight":0.3}]}}"#)
        try observation("acceptLanguage", #"{"header":null}"#, #"{"acceptLanguage":{"bestMatch":"en"}}"#)
        try observation("acceptLanguage", #"{"header":", \tfr,,"}"#, #"{"acceptLanguage":{"bestMatch":"fr"}}"#)
        try observation("matchFor", #"{"languageRanges":"fr;q=abc"}"#,
                        #"{"thrown":{"causeType":null,"identicalToRetainedCause":null,"message":"weight=\"abc\" for language range \"fr\"","type":"java.lang.IllegalArgumentException"}}"#)
        try refuses("matchFor", #"{"locale":"fr","languageRanges":[]}"#)
        try refuses("matchFor", #"{"languageRanges":[{"range":"fr","weight":"0.9"}]}"#)
        try refuses("matchFor", #"{"languageRanges":[{"range":"fr","weight":0.9,"ignored":true}]}"#)
        try refuses("acceptLanguage", #"{}"#)
        try refuses("acceptLanguage", #"{"header":false}"#)
        return checks
    }
}
