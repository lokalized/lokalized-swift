package enum TranslationContractValidation {
    package static func locale(_ value: LocaleTag, description: String) throws -> LocaleTag {
        do { return try JDKLocaleTag.requireWellFormed(value, description: description) }
        catch let error as LocaleTagError {
            throw TranslationEvaluationError(kind: .invalidArgument, message: error.message, cause: error)
        }
    }
    package static func attemptedLocales(_ values: [LocaleTag]) throws -> [LocaleTag] {
        var seen: Set<ExactString> = []
        for value in values {
            _ = try locale(value, description: "Attempted locale")
            guard seen.insert(ExactString(LanguageRangeLowercase.apply(value.tag))).inserted else {
                throw argument("Attempted locales must not contain duplicate language tag '\(value.tag)'")
            }
        }
        guard Set(values).count == values.count else { throw argument("Attempted locales must not contain duplicates") }
        return values
    }
    package static func argument(_ message: String) -> TranslationEvaluationError { .init(kind: .invalidArgument, message: message) }
}
