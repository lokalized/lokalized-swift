/// Classifies raw caller text under the catalog's supplying locale.
/// Each evaluated site invokes the callback; generated-name memoization does
/// not become a global application-resolver cache.
public typealias PhoneticResolver = @Sendable (String, LocaleTag) throws -> Phonetic

package enum PhoneticResolvers {
    static let failFast: PhoneticResolver = { _, _ in
        throw TranslationEvaluationError(kind: .invalidState,
            message: "No PhoneticResolver was configured. Provide one via Strings.Builder#phoneticResolver(...)")
    }
}
