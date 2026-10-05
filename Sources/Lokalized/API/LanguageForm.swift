/// The ten language-form axes recognized by the Lokalized file format.
public enum LanguageFormAxis: String, CaseIterable, Hashable, Sendable {
    case cardinality = "CARDINALITY"
    case ordinality = "ORDINALITY"
    case gender = "GENDER"
    case grammaticalCase = "CASE"
    case definiteness = "DEFINITENESS"
    case classifier = "CLASSIFIER"
    case formality = "FORMALITY"
    case clusivity = "CLUSIVITY"
    case animacy = "ANIMACY"
    case phonetic = "PHONETIC"
}

/// A language form with its canonical file-format token and portable display name.
///
/// For example, `Gender.masculine` has the raw value `GENDER_MASCULINE` and the
/// display name `MASCULINE`. Swift case names follow Swift naming conventions.
public protocol LanguageForm: RawRepresentable, Hashable, Sendable, CustomStringConvertible
where RawValue == String {
    static var axis: LanguageFormAxis { get }
    var displayName: String { get }
}

public extension LanguageForm {
    var axis: LanguageFormAxis { Self.axis }

    var displayName: String {
        String(rawValue.dropFirst(Self.axis.rawValue.utf8.count + 1))
    }

    var description: String { displayName }
}

/// CLDR cardinal categories for quantities. Category names are locale-specific;
/// use `forNumber` or `forOperands` to select a category with the pinned rules.
public enum Cardinality: String, CaseIterable, LanguageForm {
    case zero = "CARDINALITY_ZERO"
    case one = "CARDINALITY_ONE"
    case two = "CARDINALITY_TWO"
    case few = "CARDINALITY_FEW"
    case many = "CARDINALITY_MANY"
    case other = "CARDINALITY_OTHER"

    public static var axis: LanguageFormAxis { .cardinality }
}

/// CLDR ordinal categories for positions such as first, second, and third.
/// Use `forNumber` or `forOperands` to select a category for a locale.
public enum Ordinality: String, CaseIterable, LanguageForm {
    case zero = "ORDINALITY_ZERO"
    case one = "ORDINALITY_ONE"
    case two = "ORDINALITY_TWO"
    case few = "ORDINALITY_FEW"
    case many = "ORDINALITY_MANY"
    case other = "ORDINALITY_OTHER"

    public static var axis: LanguageFormAxis { .ordinality }
}

/// Grammatical gender supplied by the application to select a placeholder form.
public enum Gender: String, CaseIterable, LanguageForm {
    case masculine = "GENDER_MASCULINE"
    case feminine = "GENDER_FEMININE"
    case common = "GENDER_COMMON"
    case neuter = "GENDER_NEUTER"

    public static var axis: LanguageFormAxis { .gender }
}

/// Grammatical case supplied by the application to select a placeholder form.
public enum GrammaticalCase: String, CaseIterable, LanguageForm {
    case nominative = "CASE_NOMINATIVE"
    case accusative = "CASE_ACCUSATIVE"
    case genitive = "CASE_GENITIVE"
    case dative = "CASE_DATIVE"
    case instrumental = "CASE_INSTRUMENTAL"
    case locative = "CASE_LOCATIVE"
    case prepositional = "CASE_PREPOSITIONAL"
    case vocative = "CASE_VOCATIVE"
    case ablative = "CASE_ABLATIVE"

    public static var axis: LanguageFormAxis { .grammaticalCase }
}

/// Definiteness supplied by the application to select a placeholder form.
public enum Definiteness: String, CaseIterable, LanguageForm {
    case definite = "DEFINITENESS_DEFINITE"
    case indefinite = "DEFINITENESS_INDEFINITE"
    case construct = "DEFINITENESS_CONSTRUCT"

    public static var axis: LanguageFormAxis { .definiteness }
}

/// Noun classifier supplied by the application to select a placeholder form.
public enum Classifier: String, CaseIterable, LanguageForm {
    case general = "CLASSIFIER_GENERAL"
    case person = "CLASSIFIER_PERSON"
    case animal = "CLASSIFIER_ANIMAL"
    case longThin = "CLASSIFIER_LONG_THIN"
    case flat = "CLASSIFIER_FLAT"
    case bound = "CLASSIFIER_BOUND"
    case machine = "CLASSIFIER_MACHINE"
    case vehicle = "CLASSIFIER_VEHICLE"

    public static var axis: LanguageFormAxis { .classifier }
}

/// Register or level of formality supplied by the application.
public enum Formality: String, CaseIterable, LanguageForm {
    case casual = "FORMALITY_CASUAL"
    case informal = "FORMALITY_INFORMAL"
    case formal = "FORMALITY_FORMAL"
    case humble = "FORMALITY_HUMBLE"
    case honorific = "FORMALITY_HONORIFIC"

    public static var axis: LanguageFormAxis { .formality }
}

/// Whether a plural first-person form includes the person being addressed.
public enum Clusivity: String, CaseIterable, LanguageForm {
    case inclusive = "CLUSIVITY_INCLUSIVE"
    case exclusive = "CLUSIVITY_EXCLUSIVE"

    public static var axis: LanguageFormAxis { .clusivity }
}

/// Grammatical animacy supplied by the application to select a placeholder form.
public enum Animacy: String, CaseIterable, LanguageForm {
    case animate = "ANIMACY_ANIMATE"
    case inanimate = "ANIMACY_INANIMATE"

    public static var axis: LanguageFormAxis { .animacy }
}

/// Phonetic categories used to select forms based on a term's pronunciation.
/// A `PhoneticResolver` provides these language-specific decisions.
public enum Phonetic: String, CaseIterable, LanguageForm {
    case vowel = "PHONETIC_VOWEL"
    case consonant = "PHONETIC_CONSONANT"
    case hSilent = "PHONETIC_H_SILENT"
    case hAspirated = "PHONETIC_H_ASPIRATED"
    case sImpure = "PHONETIC_S_IMPURE"
    case z = "PHONETIC_Z"
    case gn = "PHONETIC_GN"
    case ps = "PHONETIC_PS"
    case pn = "PHONETIC_PN"
    case x = "PHONETIC_X"
    case glideY = "PHONETIC_GLIDE_Y"
    case glideW = "PHONETIC_GLIDE_W"
    case stressedA = "PHONETIC_STRESSED_A"
    case solar = "PHONETIC_SOLAR"
    case lunar = "PHONETIC_LUNAR"
    case other = "PHONETIC_OTHER"

    public static var axis: LanguageFormAxis { .phonetic }
}

/// Controls isolation of interpolated placeholders with Unicode bidi isolates.
///
/// The raw values match the JavaScript serialized settings. The Swift spelling
/// `disabled` avoids confusing this mode with `Optional.none` in override APIs.
public enum BidiIsolation: String, CaseIterable, Hashable, Sendable {
    case disabled = "none"
    case rtlLocales = "rtl-locales"
    case always = "always"
}

/// Describes how locale negotiation selected a catalog locale.
public enum LocaleMatchType: String, CaseIterable, Hashable, Sendable {
    case noMatch = "none"
    case exact = "exact"
    case canonical = "canonical"
    case cldrFallback = "cldr-fallback"
    case likelySubtag = "likely-subtag"
    case extendedRange = "extended-range"
    case primaryLanguage = "primary-language"
    case wildcard = "wildcard"
}
