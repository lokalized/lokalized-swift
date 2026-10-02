/// A closed, heterogeneous value for the language forms supported by Lokalized.
///
/// This is the key type for a generated-placeholder translation map. Its cases
/// admit the ten built-in axes without accepting custom `LanguageForm` types.
public enum LanguageFormValue: RawRepresentable, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    case cardinality(Cardinality)
    case ordinality(Ordinality)
    case gender(Gender)
    case grammaticalCase(GrammaticalCase)
    case definiteness(Definiteness)
    case classifier(Classifier)
    case formality(Formality)
    case clusivity(Clusivity)
    case animacy(Animacy)
    case phonetic(Phonetic)

    /// All 61 values, in axis declaration order and then enum declaration order.
    public static let allCases: [Self] =
        Cardinality.allCases.map(Self.cardinality)
        + Ordinality.allCases.map(Self.ordinality)
        + Gender.allCases.map(Self.gender)
        + GrammaticalCase.allCases.map(Self.grammaticalCase)
        + Definiteness.allCases.map(Self.definiteness)
        + Classifier.allCases.map(Self.classifier)
        + Formality.allCases.map(Self.formality)
        + Clusivity.allCases.map(Self.clusivity)
        + Animacy.allCases.map(Self.animacy)
        + Phonetic.allCases.map(Self.phonetic)

    public static var allValues: [Self] { allCases }

    /// Decodes a canonical file-format token such as `CARDINALITY_ONE`.
    public init?(rawValue: String) {
        guard let form = Self.allValues.first(where: { CatalogExactText.equals($0.rawValue, rawValue) }) else {
            return nil
        }
        self = form
    }

    public var rawValue: String {
        switch self {
        case .cardinality(let form): form.rawValue
        case .ordinality(let form): form.rawValue
        case .gender(let form): form.rawValue
        case .grammaticalCase(let form): form.rawValue
        case .definiteness(let form): form.rawValue
        case .classifier(let form): form.rawValue
        case .formality(let form): form.rawValue
        case .clusivity(let form): form.rawValue
        case .animacy(let form): form.rawValue
        case .phonetic(let form): form.rawValue
        }
    }

    public var axis: LanguageFormAxis {
        switch self {
        case .cardinality: .cardinality
        case .ordinality: .ordinality
        case .gender: .gender
        case .grammaticalCase: .grammaticalCase
        case .definiteness: .definiteness
        case .classifier: .classifier
        case .formality: .formality
        case .clusivity: .clusivity
        case .animacy: .animacy
        case .phonetic: .phonetic
        }
    }

    public var displayName: String {
        switch self {
        case .cardinality(let form): form.displayName
        case .ordinality(let form): form.displayName
        case .gender(let form): form.displayName
        case .grammaticalCase(let form): form.displayName
        case .definiteness(let form): form.displayName
        case .classifier(let form): form.displayName
        case .formality(let form): form.displayName
        case .clusivity(let form): form.displayName
        case .animacy(let form): form.displayName
        case .phonetic(let form): form.displayName
        }
    }

    public var description: String { displayName }
}
