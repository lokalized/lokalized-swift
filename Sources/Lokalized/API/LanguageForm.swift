/// The ten language-form axes recognized by the Lokalized file format.
public enum LanguageFormAxis: String, CaseIterable, Hashable, Sendable {
    /// Quantity-based plural categories.
    case cardinality = "CARDINALITY"
    /// Position-based ordinal categories.
    case ordinality = "ORDINALITY"
    /// Grammatical gender.
    case gender = "GENDER"
    /// Grammatical case.
    case grammaticalCase = "CASE"
    /// Definiteness and construct state.
    case definiteness = "DEFINITENESS"
    /// Noun classification.
    case classifier = "CLASSIFIER"
    /// Register and politeness.
    case formality = "FORMALITY"
    /// Whether the addressee is included.
    case clusivity = "CLUSIVITY"
    /// Grammatical animacy.
    case animacy = "ANIMACY"
    /// Language-specific pronunciation categories.
    case phonetic = "PHONETIC"
}

/// A language form with its canonical file-format token and portable display name.
///
/// For example, `Gender.masculine` has the raw value `GENDER_MASCULINE` and the
/// display name `MASCULINE`. Swift case names follow Swift naming conventions.
public protocol LanguageForm: RawRepresentable, Hashable, Sendable, CustomStringConvertible
where RawValue == String {
    /// The grammatical or plural axis represented by this type.
    static var axis: LanguageFormAxis { get }
    /// The uppercase form name without its axis prefix, such as `MASCULINE`.
    var displayName: String { get }
}

public extension LanguageForm {
    /// The grammatical or plural axis represented by this type.
    var axis: LanguageFormAxis { Self.axis }

    /// The uppercase form name without its axis prefix, such as `MASCULINE`.
    var displayName: String {
        String(rawValue.dropFirst(Self.axis.rawValue.utf8.count + 1))
    }

    /// The display name of the language form.
    var description: String { displayName }
}

/// CLDR cardinal categories for quantities. Category names are locale-specific;
/// use `forNumber` or `forOperands` to select a category with the pinned rules.
public enum Cardinality: String, CaseIterable, LanguageForm {
    /// The CLDR `zero` category. Its numeric meaning depends on the locale's cardinal rules.
    case zero = "CARDINALITY_ZERO"
    /// The CLDR `one` category. Its numeric meaning depends on the locale's cardinal rules.
    case one = "CARDINALITY_ONE"
    /// The CLDR `two` category. Its numeric meaning depends on the locale's cardinal rules.
    case two = "CARDINALITY_TWO"
    /// The CLDR `few` category. Its numeric meaning depends on the locale's cardinal rules.
    case few = "CARDINALITY_FEW"
    /// The CLDR `many` category. Its numeric meaning depends on the locale's cardinal rules.
    case many = "CARDINALITY_MANY"
    /// The CLDR `other` category. Its numeric meaning depends on the locale's cardinal rules.
    case other = "CARDINALITY_OTHER"

    /// The `cardinality` language-form axis.
    public static var axis: LanguageFormAxis { .cardinality }
}

/// CLDR ordinal categories for positions such as first, second, and third.
/// Use `forNumber` or `forOperands` to select a category for a locale.
public enum Ordinality: String, CaseIterable, LanguageForm {
    /// The CLDR `zero` category. Its numeric meaning depends on the locale's ordinal rules.
    case zero = "ORDINALITY_ZERO"
    /// The CLDR `one` category. Its numeric meaning depends on the locale's ordinal rules.
    case one = "ORDINALITY_ONE"
    /// The CLDR `two` category. Its numeric meaning depends on the locale's ordinal rules.
    case two = "ORDINALITY_TWO"
    /// The CLDR `few` category. Its numeric meaning depends on the locale's ordinal rules.
    case few = "ORDINALITY_FEW"
    /// The CLDR `many` category. Its numeric meaning depends on the locale's ordinal rules.
    case many = "ORDINALITY_MANY"
    /// The CLDR `other` category. Its numeric meaning depends on the locale's ordinal rules.
    case other = "ORDINALITY_OTHER"

    /// The `ordinality` language-form axis.
    public static var axis: LanguageFormAxis { .ordinality }
}

/// Grammatical gender supplied by the application to select a placeholder form.
public enum Gender: String, CaseIterable, LanguageForm {
    /// Masculine grammatical gender.
    case masculine = "GENDER_MASCULINE"
    /// Feminine grammatical gender.
    case feminine = "GENDER_FEMININE"
    /// Common grammatical gender.
    case common = "GENDER_COMMON"
    /// Neuter grammatical gender.
    case neuter = "GENDER_NEUTER"

    /// The `gender` language-form axis.
    public static var axis: LanguageFormAxis { .gender }
}

/// Grammatical case supplied by the application to select a placeholder form.
public enum GrammaticalCase: String, CaseIterable, LanguageForm {
    /// The subject or citation form.
    case nominative = "CASE_NOMINATIVE"
    /// The direct-object form.
    case accusative = "CASE_ACCUSATIVE"
    /// The possession or relationship form.
    case genitive = "CASE_GENITIVE"
    /// The indirect-object or recipient form.
    case dative = "CASE_DATIVE"
    /// The instrument or means form.
    case instrumental = "CASE_INSTRUMENTAL"
    /// The location form.
    case locative = "CASE_LOCATIVE"
    /// The form governed by a preposition.
    case prepositional = "CASE_PREPOSITIONAL"
    /// The direct-address form.
    case vocative = "CASE_VOCATIVE"
    /// The separation, origin, or source form.
    case ablative = "CASE_ABLATIVE"

    /// The `grammaticalCase` language-form axis.
    public static var axis: LanguageFormAxis { .grammaticalCase }
}

/// Definiteness supplied by the application to select a placeholder form.
public enum Definiteness: String, CaseIterable, LanguageForm {
    /// A definite noun phrase.
    case definite = "DEFINITENESS_DEFINITE"
    /// An indefinite noun phrase.
    case indefinite = "DEFINITENESS_INDEFINITE"
    /// The construct-state form used in a noun relationship.
    case construct = "DEFINITENESS_CONSTRUCT"

    /// The `definiteness` language-form axis.
    public static var axis: LanguageFormAxis { .definiteness }
}

/// Noun classifier supplied by the application to select a placeholder form.
public enum Classifier: String, CaseIterable, LanguageForm {
    /// A general-purpose noun classifier.
    case general = "CLASSIFIER_GENERAL"
    /// The classifier for people.
    case person = "CLASSIFIER_PERSON"
    /// The classifier for animals.
    case animal = "CLASSIFIER_ANIMAL"
    /// The classifier for long, thin objects.
    case longThin = "CLASSIFIER_LONG_THIN"
    /// The classifier for flat objects.
    case flat = "CLASSIFIER_FLAT"
    /// The classifier for bound items such as books.
    case bound = "CLASSIFIER_BOUND"
    /// The classifier for machines.
    case machine = "CLASSIFIER_MACHINE"
    /// The classifier for vehicles.
    case vehicle = "CLASSIFIER_VEHICLE"

    /// The `classifier` language-form axis.
    public static var axis: LanguageFormAxis { .classifier }
}

/// Register or level of formality supplied by the application.
public enum Formality: String, CaseIterable, LanguageForm {
    /// Casual register.
    case casual = "FORMALITY_CASUAL"
    /// Informal register.
    case informal = "FORMALITY_INFORMAL"
    /// Formal register.
    case formal = "FORMALITY_FORMAL"
    /// Humble register referring to the speaker or their group.
    case humble = "FORMALITY_HUMBLE"
    /// Honorific register referring to a respected person.
    case honorific = "FORMALITY_HONORIFIC"

    /// The `formality` language-form axis.
    public static var axis: LanguageFormAxis { .formality }
}

/// Whether a plural first-person form includes the person being addressed.
public enum Clusivity: String, CaseIterable, LanguageForm {
    /// A first-person plural form that includes the addressee.
    case inclusive = "CLUSIVITY_INCLUSIVE"
    /// A first-person plural form that excludes the addressee.
    case exclusive = "CLUSIVITY_EXCLUSIVE"

    /// The `clusivity` language-form axis.
    public static var axis: LanguageFormAxis { .clusivity }
}

/// Grammatical animacy supplied by the application to select a placeholder form.
public enum Animacy: String, CaseIterable, LanguageForm {
    /// An animate grammatical category.
    case animate = "ANIMACY_ANIMATE"
    /// An inanimate grammatical category.
    case inanimate = "ANIMACY_INANIMATE"

    /// The `animacy` language-form axis.
    public static var axis: LanguageFormAxis { .animacy }
}

/// Phonetic categories used to select forms based on a term's pronunciation.
/// A `PhoneticResolver` provides these language-specific decisions.
public enum Phonetic: String, CaseIterable, LanguageForm {
    /// A vowel sound.
    case vowel = "PHONETIC_VOWEL"
    /// A consonant sound.
    case consonant = "PHONETIC_CONSONANT"
    /// A silent initial h.
    case hSilent = "PHONETIC_H_SILENT"
    /// An aspirated initial h that blocks elision.
    case hAspirated = "PHONETIC_H_ASPIRATED"
    /// An initial s followed by a consonant.
    case sImpure = "PHONETIC_S_IMPURE"
    /// An initial z sound.
    case z = "PHONETIC_Z"
    /// An initial gn sound.
    case gn = "PHONETIC_GN"
    /// An initial ps sound.
    case ps = "PHONETIC_PS"
    /// An initial pn sound.
    case pn = "PHONETIC_PN"
    /// An initial x sound.
    case x = "PHONETIC_X"
    /// An initial y glide.
    case glideY = "PHONETIC_GLIDE_Y"
    /// An initial w glide.
    case glideW = "PHONETIC_GLIDE_W"
    /// An initial stressed a sound.
    case stressedA = "PHONETIC_STRESSED_A"
    /// A solar consonant category.
    case solar = "PHONETIC_SOLAR"
    /// A lunar consonant category.
    case lunar = "PHONETIC_LUNAR"
    /// Any pronunciation category not covered by the specific forms.
    case other = "PHONETIC_OTHER"

    /// The `phonetic` language-form axis.
    public static var axis: LanguageFormAxis { .phonetic }
}

/// Controls isolation of interpolated placeholders with Unicode bidi isolates.
///
/// The default is `.rtlLocales`. Set `.disabled` to omit isolation or `.always`
/// to isolate caller values regardless of the translation locale.
public enum BidiIsolation: String, CaseIterable, Hashable, Sendable {
    /// Do not add Unicode bidi isolates around interpolated caller values.
    case disabled = "none"
    /// Isolate interpolated caller values when rendering in a right-to-left locale. This is the default mode.
    case rtlLocales = "rtl-locales"
    /// Isolate interpolated caller values in every locale.
    case always = "always"
}

/// Describes how locale negotiation selected a catalog locale.
public enum LocaleMatchType: String, CaseIterable, Hashable, Sendable {
    /// No requested preference selected a supported locale.
    case noMatch = "none"
    /// The requested tag matched a supported tag directly.
    case exact = "exact"
    /// The requested and supported tags matched after canonical alias resolution.
    case canonical = "canonical"
    /// A CLDR parent or truncated locale tag selected the supported locale.
    case cldrFallback = "cldr-fallback"
    /// CLDR likely-subtag inference selected a compatible language and script.
    case likelySubtag = "likely-subtag"
    /// An RFC 4647 extended range matched the supported locale.
    case extendedRange = "extended-range"
    /// The primary language selected a supported locale when a more specific match was unavailable.
    case primaryLanguage = "primary-language"
    /// A wildcard language preference selected a supported locale.
    case wildcard = "wildcard"
}
