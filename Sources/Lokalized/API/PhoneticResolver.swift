/// Classifies caller-supplied text for a catalog locale's pronunciation rules.
/// The callback receives the term and the locale supplying the translation.
/// It can be invoked more than once in a lookup; captures must support concurrent,
/// reentrant calls. Thrown errors become resolution failures.
public typealias PhoneticResolver = @Sendable (String, LocaleTag) throws -> Phonetic

package enum PhoneticResolvers {
    static let failFast: PhoneticResolver = { _, _ in
        throw TranslationEvaluationError(kind: .invalidState,
            message: "No PhoneticResolver was configured. Provide one via Strings.Builder#phoneticResolver(...)")
    }
}
