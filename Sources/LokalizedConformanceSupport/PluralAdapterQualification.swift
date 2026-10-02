import Lokalized

enum PluralAdapterQualification {
    static func run() throws -> Int {
        var checks = 0
        func row(_ operation: String, _ input: String) throws -> BehavioralCase {
            .init(id: "self.plural", operation: operation, partition: "requiredPortableIds",
                  input: try JSONReader.parse(input), expected: .object([]))
        }
        func observation(_ operation: String, _ input: String, _ expected: String) throws {
            guard let actual = try ConformanceRunner.execute(row(operation, input)),
                  try JSONComparison.firstDifference(expected: JSONReader.parse(expected), actual: actual) == nil else {
                throw ConformanceError("Plural adapter self-test mismatch: \(operation)")
            }
            checks += 1
        }
        func refuses(_ operation: String, _ input: String) throws {
            do {
                _ = try ConformanceRunner.execute(row(operation, input))
            } catch is ConformanceError { checks += 1; return }
            throw ConformanceError("Plural adapter accepted malformed input: \(operation)")
        }
        try observation("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"integer","value":"1"}}"#,
                        #"{"classification":{"axis":"cardinality","name":"CARDINALITY_ONE","renderName":"ONE"}}"#)
        try observation("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"decimal","value":"1.00"}}"#,
                        #"{"classification":{"axis":"cardinality","name":"CARDINALITY_OTHER","renderName":"OTHER"}}"#)
        try observation("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"double","value":"Infinity"}}"#,
                        #"{"thrown":{"causeType":null,"identicalToRetainedCause":null,"message":"Number must be finite, but was Infinity","type":"java.lang.IllegalArgumentException"}}"#)
        try observation("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"decimal","value":"1.5"},"visibleDecimalPlaces":0}"#,
                        #"{"thrown":{"causeType":null,"identicalToRetainedCause":null,"message":"Rounding necessary","type":"java.lang.ArithmeticException"}}"#)
        try refuses("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"integer","value":"1"},"ignored":true}"#)
        try refuses("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"integer","value":"1","compactExponent":2}}"#)
        try refuses("cardinalityForNumber", #"{"locale":"en","value":{"$lokalized":"integer","value":"2147483648"}}"#)
        try refuses("cardinalityForOperands", #"{"locale":"en","value":{"$lokalized":"plural-operands","value":"1","compactExponent":"6"}}"#)
        try refuses("cardinalityForRange", #"{"locale":"en","start":{"$lokalized":"language-form","axis":"cardinality","name":"CARDINALITY_ONE","renderName":"OTHER"},"end":{"$lokalized":"language-form","axis":"cardinality","name":"CARDINALITY_OTHER"}}"#)
        try refuses("supportedCardinalitiesForLocale", #"{"locale":"en","ignored":null}"#)
        return checks
    }
}
