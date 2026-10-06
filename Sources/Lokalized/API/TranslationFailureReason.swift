/// Why an attempted locale could not produce a translation for a key.
public enum TranslationFailureReason: String, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    /// The candidate catalog has no entry for the requested key.
    case missingTranslation = "missing-translation"
    /// The entry has no applicable translation or matching alternative.
    case noMatchingAlternative = "no-matching-alternative"
    /// Expression evaluation, generated-fragment selection, or interpolation raised an error.
    case resolutionFailure = "resolution-failure"
    /// The uppercase diagnostic name of the failure category.
    public var displayName: String {
        switch self {
        case .missingTranslation: "MISSING_TRANSLATION"
        case .noMatchingAlternative: "NO_MATCHING_ALTERNATIVE"
        case .resolutionFailure: "RESOLUTION_FAILURE"
        }
    }
    /// The uppercase diagnostic name of the failure category.
    public var description: String { displayName }
}
