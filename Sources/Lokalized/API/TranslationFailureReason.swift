public enum TranslationFailureReason: String, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    case missingTranslation = "missing-translation"
    case noMatchingAlternative = "no-matching-alternative"
    case resolutionFailure = "resolution-failure"
    public var displayName: String {
        switch self {
        case .missingTranslation: "MISSING_TRANSLATION"
        case .noMatchingAlternative: "NO_MATCHING_ALTERNATIVE"
        case .resolutionFailure: "RESOLUTION_FAILURE"
        }
    }
    public var description: String { displayName }
}
