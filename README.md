<a href="https://lokalized.com">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://cdn.lokalized.com/lokalized-gh-logo-dark-v6.png">
        <img alt="Lokalized" src="https://cdn.lokalized.com/lokalized-gh-logo-light-v6.png" width="300" height="93">
    </picture>
</a>


Lokalized facilitates natural-sounding software translations on iOS and macOS.

It is both a file format...

```json
{
  "I read {{bookCount}} books.": {
    "translation": "I read {{bookCount}} {{books}}.",
    "placeholders": {
      "books": {
        "value": "bookCount",
        "translations": {
          "CARDINALITY_ONE": "book",
          "CARDINALITY_OTHER": "books"
        }
      }
    },
    "alternatives": [
      {
        "bookCount == 0": "I didn't read any books."
      }
    ]
  }
}
```

...and a library that operates on it:

```swift
let message = try strings.get("I read {{bookCount}} books.",
    placeholders: ["bookCount": .integer(0)])
// "I didn't read any books." in an English instance
```

Lokalized has proudly powered production systems since 2017. The Java, JavaScript, and Swift libraries share the same translation-file format; platform APIs adapt how applications supply values and load files.

**Note: this README provides a high-level overview of Lokalized.**<br/>
**For details, see the [official documentation](https://www.lokalized.com/?platform=swift) and [Swift API reference](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/).**

## Why Lokalized?

- **Keep language rules out of application code:** locale-specific grammar and wording live with the translations instead of being scattered through conditionals.
- **Give translators expressive control:** placeholders, language forms, and ordered alternatives can rewrite a fragment or an entire message when natural copy requires it.
- **Model more than simple plurals:** cardinality, ordinality, ranges, gender, grammatical case, definiteness, classifiers, formality, clusivity, animacy, and phonetics are first-class concepts.
- **Solve agreement problems many localization formats do not model directly:** a small expression language supports compound conditions over runtime facts; [see how Lokalized compares](#comparing-localization-formats).
- **Match locales predictably:** BCP 47 tags, CLDR parent locales, likely scripts, language preferences, and explicit tiebreakers produce deterministic results; [see the matching order](#locale-matching-behavior).
- **Fail safely:** bounded loading and evaluation, explicit fallback policies, and structured diagnostics make malformed or incomplete translations observable.
- **Stay lightweight:** immutable translation instances with **zero runtime dependencies**.

## Non-Goals

- Date/time, number, percentage, and currency formatting or parsing: use Foundation formatters.
- Collation: use Foundation string comparison with an explicit locale.
- HTTP loading: applications acquire remote content and pass the resulting bytes to Lokalized.
- Non-Apple platforms: this port currently supports Swift 6.2+, iOS 15+, and macOS 12+.

## Do Zero-Dependency Libraries Interest You?

Similarly flavored, commercially friendly OSS libraries are available for Java:

- [Pyranid](https://www.pyranid.com) — a modern JDBC interface that embraces SQL.
- [Soklet](https://www.soklet.com) — an HTTP/1.1 server with support for virtual threads, Server-Sent Events, and Model Context Protocol.

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0). See [LICENSE](LICENSE), [NOTICE](NOTICE), and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for project and generated-data attribution.

## Swift Package Manager Installation

Use Swift 6.2 or later in Swift 6 language mode. This complete macOS command-line package also declares the iOS 15 and macOS 12 deployment targets used by the library:

<!-- lokalized-example: quickstart manifest -->
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuickStart",
    platforms: [.iOS(.v15), .macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/lokalized/lokalized-swift", from: "1.0.0")
    ],
    targets: [.executableTarget(name: "QuickStart", dependencies: [
        .product(name: "Lokalized", package: "lokalized-swift")
    ], resources: [.copy("Lokalized")])],
    swiftLanguageModes: [.v6]
)
```

## iOS and macOS

In Xcode, choose **File → Add Package Dependencies**, enter `https://github.com/lokalized/lokalized-swift`, select version 1.0.0 or later, and add the `Lokalized` product to your target. The [iOS and macOS integration example](#ios-and-macos-integration) below covers bundled files and SwiftUI. The same runtime also works in macOS command-line tools.

Consumer builds require only the checked-in Swift sources and Apple SDKs. There are no package plugins, generation steps, or downloads during a consumer build. [Deployment evidence](Documentation/DEPLOYMENT.md) distinguishes compilation for an OS target from execution on that OS.

## Getting Started

We will start with hands-on examples to illustrate the same features shown by the Java library.

### 1. Create Localized Strings Files

Filenames follow the IETF BCP 47 language-tag format, optionally suffixed with `.json`. This Brazilian Portuguese (`pt-BR`) file uses English source text as the lookup key:

Save this as `Examples/Readme/books/pt-BR.json` (or `Sources/QuickStart/Lokalized/pt-BR.json` for the SwiftPM walkthrough):

<!-- lokalized-example: quickstart catalog-pt-BR -->
```json
{
  "I read {{bookCount}} books.": {
    "translation": "Li {{bookCount}} {{books}}.",
    "placeholders": {
      "books": {
        "value": "bookCount",
        "translations": {
          "CARDINALITY_ONE": "livro",
          "CARDINALITY_OTHER": "livros"
        }
      }
    },
    "alternatives": [
      {
        "bookCount == 0": "Não li nenhum livro."
      }
    ]
  }
}
```

The abbreviated book example covers `ONE` and `OTHER`. Portuguese also defines `MANY`, so loading reports an incomplete-cardinality warning. Production files should define every required form; [`ParsedStringsFile.warnings`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/parsedstringsfile/warnings/) and the loader's `warningHandler` expose these gaps.

### 2. Create a Strings Instance

Save the following Swift blocks, in order, as `Sources/QuickStart/main.swift`. The factory reads the resource-owning target's bundle once and accepts a synchronous, thread-safe getter for the app's language settings:

<!-- lokalized-example: quickstart source -->
```swift
import Foundation
import Lokalized

func makeStrings(in bundle: Bundle,
                 currentLocale: @escaping @Sendable () -> LocaleTag) throws -> any Strings {
    let files = try LocalizedStringLoader.loadFromBundle(bundle)
    let catalogs = files.mapValues { LocalizedCatalog(strings: $0.strings) }
    return try DefaultStrings(configuration: StringsConfiguration(
        localizedStringSupplier: { catalogs },
        localeSupplier: { _ in currentLocale() },
        fallbackLocale: LocaleTag("pt-BR")))
}

// A demo setting; an app supplies a getter for its own language settings.
let locale = try LocaleTag("pt-BR")
let strings = try makeStrings(in: .module, currentLocale: { locale })
```

Use `.main` in an Xcode app and `.module` from a SwiftPM target that owns copied resources. The locale supplier reads your getter on each applicable lookup; it must be safe for concurrent calls. For actor-isolated settings, read the locale on that actor and pass a per-invocation option instead.

The factory returns [`any Strings`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/strings/), the public translation and locale-matching protocol, while constructing a [`DefaultStrings`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/defaultstrings/) implementation. This keeps app callers coupled to the API they use. The protocol is [`Sendable`](https://developer.apple.com/documentation/swift/sendable), so its values can be shared across concurrency boundaries.

A macOS tool can use [`LocalizedStringLoader.loadFromDirectory`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/localizedstringloader/loadfromdirectory%28_:warninghandler:loadingoptions:%29/) for caller-chosen files; [see local loading](#loading-localized-strings).

By default, exhausted lookups return the key with available placeholders interpolated into it. Failure handlers can throw instead, or keep the key while reporting structured telemetry; [see failure handling](#translation-failure-handling). Load files and create the immutable instance once, then share it. To reload files, construct a new instance and let your application replace the shared snapshot.

### 3. Ask Strings Instance For Translations

<!-- lokalized-example: quickstart source -->
```swift
print(try strings.get("I read {{bookCount}} books.", placeholders: ["bookCount": .integer(3)]))
print(try strings.get("I read {{bookCount}} books.", placeholders: ["bookCount": .integer(1)]))
print(try strings.get("I read {{bookCount}} books.", placeholders: ["bookCount": .integer(0)]))
```

Run `swift run QuickStart`. The complete program prints:

<!-- lokalized-example: quickstart output -->
```text
Li 3 livros.
Li 1 livro.
Não li nenhum livro.
```

Lokalized selects `CARDINALITY_ONE` for 1 and `CARDINALITY_OTHER` for 3 in Brazilian Portuguese. The ordered alternative replaces the whole sentence at zero. None of those wording decisions belong in application conditionals.

#### Formatting Placeholder Values

Lokalized selects wording and interpolates values; it does not format dates, times, currency, or localized numbers. When a number drives selection and needs display formatting, pass a raw numeric placeholder and a separate formatted string.

```swift
let count: Int32 = 12_345
let formatter = NumberFormatter()
formatter.locale = Locale(identifier: "en_US")
formatter.numberStyle = .decimal
let formattedCount = formatter.string(from: NSNumber(value: count))!
// Supply ["count": .integer(count), "formattedCount": .text(formattedCount)]
// to a message whose rules use count and whose text uses {{formattedCount}}.
```

#### 4. Ensure Determinism via Tiebreakers

Suppose you load `en-US` and `en-GB`, and a user asks for `en-CA`. If no earlier exact, canonical, or CLDR-parent match applies, the configured English order decides which file wins. Construction rejects ambiguous primary languages unless the tiebreaker list includes every loaded locale for that language exactly once.

```swift
let enUS = try LocaleTag("en-US"), enGB = try LocaleTag("en-GB")
let usFile = try LocalizedStringLoader.parse(#"{"welcome":"Hello!"}"#, locale: "en-US")
let gbFile = try LocalizedStringLoader.parse(#"{"welcome":"Welcome!"}"#, locale: "en-GB")
let regionalCatalogs = [enUS: LocalizedCatalog(strings: usFile.strings),
                        enGB: LocalizedCatalog(strings: gbFile.strings)]
let regionalStrings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { regionalCatalogs },
    localeSupplier: { _ in try LocaleTag("en-CA") },
    fallbackLocale: enUS,
    tiebreakerLocalesByLanguageCode: ["en": [enUS, enGB]]))
// try regionalStrings.get("welcome") returns "Hello!"
```

#### 5. Respect User Language Preferences

A web request might carry `Accept-Language: en-GB;q=1.0,en;q=0.75,fr-FR;q=0.25`. Lokalized can evaluate the weighted preference list against the loaded files. Missing, malformed, blank, or over-limit raw headers fall back safely; they are never truncated into a different preference list.

```swift
let options = try TranslationOptions.forAcceptLanguage("pt-BR,pt;q=0.8", using: strings)
let message = try strings.get("I read {{bookCount}} books.",
    placeholders: ["bookCount": .integer(1)], options: options)
// "Li 1 livro."
```

In an iOS or macOS app, use [`PreferredLanguageChooser.chooseAppleLocale(using:)`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/preferredlanguagechooser/chooseapplelocale%28using:%29/) to sample Apple's current ordered preferences, or pass app-owned preferences with [`chooseLocaleForPreferredLanguages(_:using:)`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/preferredlanguagechooser/chooselocaleforpreferredlanguages%28_:using:%29/). Existing instances do not subscribe to system changes or mutate a process-wide language.

### Locale Matching Behavior

Matching is deterministic and follows the same broad rules across ports:

- Exact loaded tags win before CLDR-canonical-equivalent tags and legacy aliases.
- CLDR parent locales are considered before looser language-only matches: `en-AU` can prefer `en-001` before `en`.
- Matching is script-aware: `zh-TW` can match `zh-Hant`; `sr-Latn` and `sr-Cyrl` remain distinct.
- Norwegian `no` and Bokmål `nb` bridge as a compatibility fallback; exact files still win. Nynorsk `nn` is independent.
- Complete tiebreaker orders resolve otherwise ambiguous files for the same primary language.
- Weighted language ranges honor `q=0` exclusions when an acceptable loaded candidate remains.
- Unmatched requests, `und`, wildcard-only preferences, and empty lists resolve to the configured fallback.

| Request | Loaded files | Result |
|---|---|---|
| `en-AU` | `en-001`, `en` | `en-001` |
| `zh-TW` | `zh-Hant`, `zh-Hans` | `zh-Hant` |
| `en-CA` | `en-US`, `en-GB` | First configured English tiebreaker |

Parsed range lists are bounded at 32 entries. The raw-header helper bounds input at 4,096 UTF-16 code units. Pinned IANA equivalents may add ranges beyond the ones literally written in a header. Language-range equivalence comes from the IANA Language Subtag Registry snapshot (`File-Date: 2026-09-17`), rather than the host's locale database.

## Loading Localized Strings

Load synchronous local inputs: [`String`](https://developer.apple.com/documentation/swift/string), [`Data`](https://developer.apple.com/documentation/foundation/data), a caller-owned [`InputStream`](https://developer.apple.com/documentation/foundation/inputstream), local file URLs, directories, [`Bundle`](https://developer.apple.com/documentation/foundation/bundle) resources, or explicit resource maps. Streams remain caller-owned and are never closed by Lokalized. A directory load does not recursively scan child directories:

```swift
let files = try LocalizedStringLoader.loadFromDirectory(
    URL(fileURLWithPath: "Examples/Readme/books", isDirectory: true))
let catalogs = files.mapValues { LocalizedCatalog(strings: $0.strings) }
// Provide catalogs through localizedStringSupplier when constructing DefaultStrings.
```

For an app, use [`loadFromBundle(.main)`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/localizedstringloader/loadfrombundle%28_:directory:warninghandler:loadingoptions:%29/); for SwiftPM resources, use `.module` from the resource-owning target. `loadFromResources` and `resourcePathsByLocale` provide explicit mappings. Applications own remote acquisition; no loader starts an HTTP request. Manifest APIs validate, compute identity, and plan references without reading catalog bodies. See [local loading](Documentation/LOCAL-LOADING.md) and [Apple local delivery](Documentation/APPLE-LOCAL-DELIVERY.md).

Loading is bounded per input and per aggregate load. Malformed UTF-8/JSON, duplicate members, invalid expressions, and invalid localized strings fail validation. A blank or BOM-only file is invalid; use `{}` for an intentionally empty file. Missing locale-specific plural forms produce structured warnings; they are not silently filled from an unrelated language.

## Per-Invocation Options

The configured locale supplier is useful for an app's shared language settings. For independent views, requests, batch jobs, or alternate output sinks, override the language for one call:

```swift
let message = try strings.get("I read {{bookCount}} books.",
    placeholders: ["bookCount": .integer(1)], options: .forLocale("pt-BR"))
// "Li 1 livro."
```

[`TranslationOptions`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/translationoptions/) can also override language ranges, an existing match, bidi isolation, fallback policy, failure handling, or successful-fallback observation. An explicit locale or match bypasses the configured locale supplier for that call. A per-call observer replaces the instance observer; omission inherits it.

## Runtime Safety Limits

Evaluation bounds cover numeric precision and scale, expression length and nesting, generated-fragment depth, interpolated output, and cumulative expansion per locale attempt. Defaults include 1,024 numeric digits, 2,048 expression characters, 256 expression tokens, 32 nested groups, 32 fragment levels, and 262,144 UTF-16 units for an interpolated result.

Swift supports `TranslationRuntimeLimits` to lower or raise defaults within hard ceilings. Loading checks hard ceilings; runtime construction checks the selected policy, so a file can parse successfully yet exceed your configured runtime limits. See [runtime semantics](Documentation/RUNTIME-SEMANTICS.md).

## A More Complex Example

Lokalized handles phrases whose wording changes according to several language rules. In English, gender affects the subject fragment. In Spanish, it also changes words such as `uno`/`una`, `los`/`las`, and `jugadores`/`jugadoras`. A common-gender alternative can rewrite the phrase naturally, rather than inventing one opaque flag per combination.

### English Localized Strings File

Save this as `Examples/Readme/players/en.json`:

```json
{
  "{{heOrShe}} was one of the {{groupSize}} best baseball players.": {
    "translation": "{{heOrShe}} was one of the {{groupSize}} best baseball players.",
    "placeholders": {
      "heOrShe": {
        "value": "heOrShe",
        "translations": {
          "GENDER_MASCULINE": "He",
          "GENDER_FEMININE": "She",
          "GENDER_COMMON": "This person"
        }
      }
    },
    "alternatives": [
      {
        "groupSize <= 1": "{{heOrShe}} was the best baseball player."
      }
    ]
  }
}
```

### Spanish Localized Strings File

Save this as `Examples/Readme/players/es-MX.json`:

```json
{
  "{{heOrShe}} was one of the {{groupSize}} best baseball players.": {
    "translation": "Fue {{uno}} de {{los}} {{groupSize}} mejores {{jugadores}} de béisbol.",
    "placeholders": {
      "uno": {
        "value": "heOrShe",
        "translations": {
          "GENDER_MASCULINE": "uno",
          "GENDER_FEMININE": "una"
        }
      },
      "los": {
        "value": "heOrShe",
        "translations": {
          "GENDER_MASCULINE": "los",
          "GENDER_FEMININE": "las"
        }
      },
      "jugadores": {
        "value": "heOrShe",
        "translations": {
          "GENDER_MASCULINE": "jugadores",
          "GENDER_FEMININE": "jugadoras"
        }
      }
    },
    "alternatives": [
      {
        "heOrShe == GENDER_COMMON && groupSize <= 1": "Esta persona era quien mejor jugaba al béisbol."
      },
      {
        "heOrShe == GENDER_COMMON": "Esta persona estaba entre las {{groupSize}} personas que mejor jugaban al béisbol."
      },
      {
        "heOrShe == GENDER_MASCULINE && groupSize <= 1": "Él era el mejor jugador de béisbol."
      },
      {
        "heOrShe == GENDER_FEMININE && groupSize <= 1": "Ella era la mejor jugadora de béisbol."
      }
    ]
  }
}
```

### The Rules, Exercised

The application supplies gender and group size. The files own the wording decisions:

For the following macOS file examples, this helper loads one folder and creates a runtime. An iOS app uses the same files through its resource bundle instead:

```swift
func stringsFromDirectory(_ path: String, fallbackLocale: String = "en") throws -> DefaultStrings {
    let files = try LocalizedStringLoader.loadFromDirectory(URL(fileURLWithPath: path, isDirectory: true))
    let catalogs = files.mapValues { LocalizedCatalog(strings: $0.strings) }
    let locale = try LocaleTag(fallbackLocale)
    return try DefaultStrings(configuration: StringsConfiguration(
        localizedStringSupplier: { catalogs }, localeSupplier: { _ in locale }, fallbackLocale: locale))
}

let playersStrings = try stringsFromDirectory("Examples/Readme/players")
let key: ExactString = "{{heOrShe}} was one of the {{groupSize}} best baseball players."
let english = try playersStrings.get(key,
    placeholders: ["heOrShe": .languageForm(.gender(.feminine)), "groupSize": .integer(1)])
let spanish = try playersStrings.get(key,
    placeholders: ["heOrShe": .languageForm(.gender(.feminine)), "groupSize": .integer(10)], options: .forLocale("es-MX"))
// english: "She was the best baseball player."
// spanish: "Fue una de las 10 mejores jugadoras de béisbol."
```

## Cardinality Ranges

A range has its own plural agreement. The result is selected from the start and end categories using pinned CLDR plural-range rules; selecting from the end alone can be wrong. English `0–1` selects `OTHER`, even though the ending value alone selects `ONE`. French selects `ONE` for the same range.

### French Localized Strings File

Save this as `Examples/Readme/ranges/fr.json`:

```json
{
  "The meeting will be {{minHours}}-{{maxHours}} hours long.": {
    "translation": "La réunion aura une durée de {{minHours}} à {{maxHours}} {{heures}}.",
    "placeholders": {
      "heures": {
        "range": {
          "start": "minHours",
          "end": "maxHours"
        },
        "translations": {
          "CARDINALITY_ONE": "heure",
          "CARDINALITY_OTHER": "heures"
        }
      }
    }
  }
}
```

### English Localized Strings File

Save this as `Examples/Readme/ranges/en.json`:

```json
{
  "The meeting will be {{minHours}}-{{maxHours}} hours long.": {
    "translation": "The meeting will be {{minHours}}-{{maxHours}} {{hours}} long.",
    "placeholders": {
      "hours": {
        "range": {
          "start": "minHours",
          "end": "maxHours"
        },
        "translations": {
          "CARDINALITY_ONE": "hour",
          "CARDINALITY_OTHER": "hours"
        }
      }
    }
  }
}
```

### Cardinality Ranges, Exercised

```swift
let rangeStrings = try stringsFromDirectory("Examples/Readme/ranges")
let message = try rangeStrings.get("The meeting will be {{minHours}}-{{maxHours}} hours long.",
    placeholders: ["minHours": .integer(0), "maxHours": .integer(1)], options: .forLocale("fr"))
// "La réunion aura une durée de 0 à 1 heure."
```

## Ordinal Forms

Ordinality describes position: English distinguishes `1st`, `2nd`, `3rd`, and `4th`. Languages can combine ordinal choice with gender and whole-message alternatives.

### English Localized Strings File

Save this as `Examples/Readme/ordinals/en.json`:

```json
{
  "{{hisOrHer}} {{year}}th birthday party is next week.": {
    "translation": "{{hisOrHer}} {{year}}{{ordinal}} birthday party is next week.",
    "placeholders": {
      "hisOrHer": {
        "value": "hisOrHer",
        "translations": {
          "GENDER_MASCULINE": "His",
          "GENDER_FEMININE": "Her"
        }
      },
      "ordinal": {
        "value": "year",
        "translations": {
          "ORDINALITY_ONE": "st",
          "ORDINALITY_TWO": "nd",
          "ORDINALITY_FEW": "rd",
          "ORDINALITY_OTHER": "th"
        }
      }
    }
  }
}
```

### Spanish Localized Strings File

Save this as `Examples/Readme/ordinals/es.json`:

```json
{
  "{{hisOrHer}} {{year}}th birthday party is next week.": {
    "translation": "Su fiesta de cumpleaños número {{year}} es la próxima semana.",
    "alternatives": [
      {
        "year == 1": "Su primera fiesta de cumpleaños es la próxima semana."
      },
      {
        "hisOrHer == GENDER_FEMININE && year == 15": "Su quinceañera es la próxima semana."
      }
    ]
  }
}
```

### Ordinals, Exercised

```swift
let ordinalStrings = try stringsFromDirectory("Examples/Readme/ordinals")
let message = try ordinalStrings.get("{{hisOrHer}} {{year}}th birthday party is next week.",
    placeholders: ["hisOrHer": .languageForm(.gender(.feminine)), "year": .integer(2)])
// "Her 2nd birthday party is next week."
```

## Language Forms

Language forms are typed runtime values. The JSON tokens are shared across every port:

| Axis | Example catalog token | What it controls |
|---|---|---|
| Gender | `GENDER_FEMININE` | Gender agreement |
| Grammatical case | `CASE_DATIVE` | A noun's role in a sentence |
| Definiteness | `DEFINITENESS_DEFINITE` | Definite, indefinite, or construct forms |
| Classifier | `CLASSIFIER_PERSON` | Counting categories |
| Formality | `FORMALITY_FORMAL` | Register and address |
| Clusivity | `CLUSIVITY_INCLUSIVE` | Whether “we” includes the listener |
| Animacy | `ANIMACY_ANIMATE` | Animate or inanimate agreement |
| Plural cardinality | `CARDINALITY_ONE` | Quantity-dependent wording |
| Plural cardinality range | Start/end cardinality pair | Agreement for a numeric range |
| Phonetics | `PHONETIC_VOWEL` | Pronunciation-sensitive wording |
| Ordinality | `ORDINALITY_TWO` | Position-dependent wording |

Ranges combine cardinalities; there are ten distinct language-form axes. Numeric values automatically select cardinal or ordinal categories when required. Gender, case, formality, and the other authored forms come from the application; Lokalized does not infer them from a person's name or identity.

```swift
let values: PlaceholderValues = [
    "gender": .languageForm(.gender(.feminine)),
    "recipientCase": .languageForm(.grammaticalCase(.dative)),
    "register": .languageForm(.formality(.formal)),
    "count": .integer(3)
]
// Catalogs still use GENDER_FEMININE, CASE_DATIVE, and FORMALITY_FORMAL.
// String variables used as keys must be wrapped in ExactString to preserve Unicode identity.
```

Written decimals and explicit plural operands retain numeric meaning, including visible fraction digits and compact exponents. English `1` selects `ONE`, while a decimal written as `1.00` selects `OTHER`. Keep raw numeric inputs separate from localized display strings.

### Gender

Gender is a grammatical input, supplied explicitly as a typed value. The baseball example above combines it with a group size so the file can rewrite both a pronoun and a whole sentence.

The following examples reuse `stringsFromDirectory` from the baseball example. iOS apps load the same JSON from their bundle.

### Grammatical Case

Case selects the form required by the sentence. This Russian example supplies a dative recipient instead of teaching the application how to inflect a name.

Save this as `Examples/Readme/case/ru.json`:

```json
{
  "Send a message to the recipient.": {
    "translation": "Отправить сообщение {{recipientForm}}.",
    "placeholders": {
      "recipientForm": {
        "value": "grammaticalCase",
        "translations": {
          "CASE_NOMINATIVE": "Иван",
          "CASE_DATIVE": "Ивану",
          "CASE_ACCUSATIVE": "Ивана"
        }
      }
    }
  }
}
```

```swift
let caseStrings = try stringsFromDirectory("Examples/Readme/case", fallbackLocale: "ru")
let message = try caseStrings.get("Send a message to the recipient.",
    placeholders: ["grammaticalCase": .languageForm(.grammaticalCase(.dative))])
// "Отправить сообщение Ивану."
```

### Definiteness

Definiteness distinguishes definite, indefinite, and construct forms. The file owns the Arabic noun phrase. This plain-text demonstration disables bidi isolation; normal UI lookups retain the default isolation policy.

Save this as `Examples/Readme/definiteness/ar.json`:

```json
{
  "Open the document.": {
    "translation": "افتح {{documentForm}}.",
    "placeholders": {
      "documentForm": {
        "value": "definiteness",
        "translations": {
          "DEFINITENESS_DEFINITE": "الكتاب",
          "DEFINITENESS_INDEFINITE": "كتابًا",
          "DEFINITENESS_CONSTRUCT": "كتاب"
        }
      }
    }
  }
}
```

```swift
let definiteStrings = try stringsFromDirectory("Examples/Readme/definiteness", fallbackLocale: "ar")
let message = try definiteStrings.get("Open the document.",
    placeholders: ["definiteness": .languageForm(.definiteness(.definite))],
    options: TranslationOptions(bidiIsolation: BidiIsolation.disabled))
// "افتح الكتاب."
```

### Classifiers

Many languages count objects with a classifier or counter. The application identifies the kind of object; the Japanese file chooses the counter for bound items such as books.

Save this as `Examples/Readme/classifiers/ja.json`:

```json
{
  "I bought {{count}} items.": {
    "translation": "{{count}}{{counter}}買いました。",
    "placeholders": {
      "counter": {
        "value": "classifier",
        "translations": {
          "CLASSIFIER_GENERAL": "つ",
          "CLASSIFIER_BOUND": "冊",
          "CLASSIFIER_MACHINE": "台"
        }
      }
    }
  }
}
```

```swift
let classifierStrings = try stringsFromDirectory("Examples/Readme/classifiers", fallbackLocale: "ja")
let message = try classifierStrings.get("I bought {{count}} items.",
    placeholders: ["count": .integer(3), "classifier": .languageForm(.classifier(.bound))])
// "3冊買いました。"
```

### Formality

Formality selects the appropriate register without a switch statement in the calling code. These labels describe authored wording; they are not universal rules about when to address someone formally.

Save this as `Examples/Readme/formality/en.json`:

```json
{
  "Hello, {{name}}.": {
    "translation": "{{greeting}}, {{name}}.",
    "placeholders": {
      "greeting": {
        "value": "formality",
        "translations": {
          "FORMALITY_CASUAL": "Hey",
          "FORMALITY_INFORMAL": "Hi",
          "FORMALITY_FORMAL": "Hello",
          "FORMALITY_HUMBLE": "I humbly greet you",
          "FORMALITY_HONORIFIC": "Greetings"
        }
      }
    }
  }
}
```

```swift
let formalStrings = try stringsFromDirectory("Examples/Readme/formality")
let casual = try formalStrings.get("Hello, {{name}}.",
    placeholders: ["name": .text("Ada"), "formality": .languageForm(.formality(.casual))])
let formal = try formalStrings.get("Hello, {{name}}.",
    placeholders: ["name": .text("Ada"), "formality": .languageForm(.formality(.formal))])
// casual: "Hey, Ada."; formal: "Hello, Ada."
```

### Clusivity

Inclusive “we” includes the listener; exclusive “we” does not. Malay distinguishes these with different words, selected here from the same key.

Save this as `Examples/Readme/clusivity/ms.json`:

```json
{
  "We will meet at noon.": {
    "translation": "{{we}} akan bertemu pada tengah hari.",
    "placeholders": {
      "we": {
        "value": "clusivity",
        "translations": {
          "CLUSIVITY_INCLUSIVE": "Kita",
          "CLUSIVITY_EXCLUSIVE": "Kami"
        }
      }
    }
  }
}
```

```swift
let clusiveStrings = try stringsFromDirectory("Examples/Readme/clusivity", fallbackLocale: "ms")
let inclusive = try clusiveStrings.get("We will meet at noon.",
    placeholders: ["clusivity": .languageForm(.clusivity(.inclusive))])
let exclusive = try clusiveStrings.get("We will meet at noon.",
    placeholders: ["clusivity": .languageForm(.clusivity(.exclusive))])
// inclusive: "Kita akan bertemu pada tengah hari."
// exclusive: "Kami akan bertemu pada tengah hari."
```

### Animacy

Animacy affects agreement and inflection in languages such as Russian. The caller supplies the grammatical category; the translation selects the corresponding phrase.

Save this as `Examples/Readme/animacy/ru.json`:

```json
{
  "I see {{object}}.": {
    "translation": "Я вижу {{object}}.",
    "placeholders": {
      "object": {
        "value": "animacy",
        "translations": {
          "ANIMACY_ANIMATE": "брата",
          "ANIMACY_INANIMATE": "стол"
        }
      }
    }
  }
}
```

```swift
let animacyStrings = try stringsFromDirectory("Examples/Readme/animacy", fallbackLocale: "ru")
let animate = try animacyStrings.get("I see {{object}}.",
    placeholders: ["animacy": .languageForm(.animacy(.animate))])
let inanimate = try animacyStrings.get("I see {{object}}.",
    placeholders: ["animacy": .languageForm(.animacy(.inanimate))])
// animate: "Я вижу брата."; inanimate: "Я вижу стол."
```

### Plural Cardinality

Numeric quantities select `ZERO`, `ONE`, `TWO`, `FEW`, `MANY`, or `OTHER` according to the locale's CLDR rules. Languages use different subsets: Japanese uses only `OTHER`, English uses `ONE` and `OTHER`, and Russian distinguishes `ONE`, `FEW`, `MANY`, and `OTHER`. Never assume that a language has only singular and plural forms.

### Plural Cardinality Ranges

Range agreement uses both endpoint categories. See the [French and English examples](#cardinality-ranges); do not substitute the ending number's category for the range's category.

### Phonetics

For phrases such as *a gift* and *an honor*, an application-supplied resolver maps runtime text to a typed pronunciation category. The translation file decides the article:

Save this as `Examples/Readme/phonetics/en.json`:

```json
{
  "I received a {{noun}}.": {
    "translation": "I received {{article}} {{noun}}.",
    "placeholders": {
      "article": {
        "value": "noun",
        "translations": {
          "PHONETIC_VOWEL": "an",
          "PHONETIC_CONSONANT": "a"
        }
      }
    }
  }
}
```

```swift
let phoneticFiles = try LocalizedStringLoader.loadFromDirectory(
    URL(fileURLWithPath: "Examples/Readme/phonetics", isDirectory: true))
let phoneticCatalogs = phoneticFiles.mapValues { LocalizedCatalog(strings: $0.strings) }
let en = try LocaleTag("en")
let phoneticStrings = try DefaultStrings(configuration: StringsConfiguration(
    localizedStringSupplier: { phoneticCatalogs }, localeSupplier: { _ in en }, fallbackLocale: en,
    // This demo knows two terms. Production resolvers use pronunciation data.
    phoneticResolver: { term, _ in term == "honor" ? .vowel : .consonant }))
// try phoneticStrings.get("I received a {{noun}}.", placeholders: ["noun": .text("honor")])
// returns "I received an honor."
```

The resolver receives the term and locale. Categories also cover silent/aspirated *h*, Italian initial clusters, Spanish stressed *a*, and Arabic sun/moon letters. Pronunciation is not reliably determined by a naive first-letter test.

### Ordinals

Ordinals express position rather than quantity. English uses `ONE`, `TWO`, `FEW`, and `OTHER` for suffixes such as 1st, 2nd, 3rd, and 4th; Spanish uses only `OTHER` in its ordinal rules. See the [birthday example](#ordinal-forms) for both files and the calling API.

## CLDR Data

Cardinal, ordinal, range, matching, and bidi behavior use pinned CLDR 48.2 data. Updating the host's formatting libraries does not silently change Lokalized's plural decisions. IANA locale equivalence and Unicode data are pinned as well. Generated runtime data is checked in; applications do not run generators or download reference archives.

For development, see [data generation](Documentation/DEVELOPMENT.md#data-and-reference-integrity), [NOTICE](NOTICE), [API mappings](Documentation/API-MAPPING.md), and [native compatibility contracts](Documentation/NATIVE-CONTRACTS.md). Platform adaptations are tracked separately from exact behavioral agreement.

## Translation Failure Handling

The default handler returns the key after an exhausted lookup. Fail-fast applications can throw; fail-soft applications can record telemetry while returning the key. Parser, configuration, and application callback errors still propagate rather than being turned into successful translations.

```swift
let options = try TranslationOptions(translationFailureHandler: .throwException())
do {
    _ = try strings.get("not-authored", options: options)
} catch is MissingTranslationError {
    // Report the missing key or apply an explicit UI error policy.
}

let telemetry = TranslationFailureHandler.returnKey(observer: { failure in
    print("Translation failure:", failure.reason.rawValue)
})
```

Fallback policy decides whether a failed candidate permits trying another locale. The default continues for a missing translation or unmatched alternative and stops on resolution failure. A permissive policy can try another locale for any failure; a never-fallback policy stops after the first attempt.

### Observing Successful Fallback

A successful translation from a later candidate is not an exhausted failure. Attach a `translationFallbackObserver` to record this separately. The event identifies the lookup locale, retained match, attempted locales, resolved locale, key, and preceding failures. Observer errors propagate directly; they do not resume the fallback walk.

### Failure Reasons

- `missing-translation`: the candidate has no entry for the key.
- `no-matching-alternative`: an alternatives-only entry has no selected branch.
- `resolution-failure`: a selected entry cannot be evaluated or rendered.

## Translation Diagnostics

[`get`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/strings/get%28_:placeholders:options:%29/) returns text. [`getResult`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/strings/getresult%28_:placeholders:options:%29/) also reports how the key was resolved, including the matched and resolved locales, fallback status, outcome status, and any retained failure. Negotiation and per-key fallback are separate: the file chosen for the user may lack a key that exists in a later candidate.

```swift
let result = try strings.getResult("I read {{bookCount}} books.",
    placeholders: ["bookCount": .integer(3)])
// result.translation == "Li 3 livros."
// result.resolvedLocale?.tag == "pt-BR"
// result.status == .translated; result.isFallback == false
```

Structured load warnings include source, locale, key, placeholder, missing forms, and a human-readable message where applicable. Render translated values using your UI's normal text and escaping APIs. Lokalized does not escape HTML, create markup, or choose page-level `lang` and `dir` for your application. Bidi isolation protects interpolated fragments without changing the language-selection API.

## Localized Strings File Format

### Structure

- UTF-8, with a BCP 47 filename such as `en.json` or `zh-TW.json`; do not provide both suffixed and unsuffixed files for one locale.
- One top-level JSON object whose keys are translation keys.
- A value can be a string or an object with `translation`, `commentary`, `placeholders`, and `alternatives`.
- An object needs a `translation` or at least one alternative. A default translation is optional when every valid outcome is selected by alternatives.

The shorthand `"welcome": "Hello!"` is equivalent to `"welcome": { "translation": "Hello!" }`.

### JSON Schema

The shared [JSON Schema](https://github.com/lokalized/lokalized-java/blob/master/src/main/resources/schema/lokalized-strings.schema.json) documents file structure and language-form names. Runtime parsing additionally validates expressions and resource budgets. A missing locale-specific plural form produces a warning and may later cause a resolution failure; it is not evidence that the locale needs only the forms the author happened to include.

### Commentary

`commentary` holds translator-facing context and is never rendered. Document where a message appears and what each application-supplied placeholder means.

### Placeholders

Write `{{bookCount}}`, with no spaces inside the braces. Names start with a Unicode letter or underscore and continue with letters, numbers, combining marks, underscores, or hyphens. The ASCII subset `[A-Za-z_][A-Za-z0-9_-]*` is portable across the ports and schema engines.

A generated placeholder can select by language form, use a start/end pair for a cardinality range, or select an expression-driven fragment. Generated placeholders can refer to other generated fragments. Parent definitions are inherited by selected alternatives unless the child replaces them. Authored keys and placeholder identifiers retain exact Unicode identity.

Swift's ordinary [`String`](https://developer.apple.com/documentation/swift/string) equality treats canonically equivalent strings as equal. Use [`ExactString`](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/exactstring/) and Lokalized's exact collection types when building keys programmatically; ordinary dictionaries can collapse distinct keys before the runtime receives them. JSON catalogs preserve the authored identities. See [exact Unicode keys](Documentation/USAGE.md#keep-authored-unicode-keys-exact).

#### Alternatives

Alternatives are ordered: the first true predicate wins. They can replace a whole message or a generated fragment. This search message combines a result count, a runtime limit, and elapsed time without making the app compute wording buckets:

Save this as `Examples/Readme/search/en.json`:

```json
{
  "Search completed.": {
    "translation": "Found {{resultSummary}} {{timing}}.",
    "placeholders": {
      "resultSummary": {
        "translation": "{{formattedResultCount}} {{resultNoun}}",
        "alternatives": [
          {
            "resultCount == 0": "no results"
          },
          {
            "resultCount >= resultLimit": "at least {{formattedResultLimit}} results"
          }
        ]
      },
      "timing": {
        "translation": "in {{formattedDuration}}",
        "alternatives": [
          {
            "elapsedMilliseconds < 1000": "instantly"
          }
        ]
      },
      "resultNoun": {
        "value": "resultCount",
        "translations": {
          "CARDINALITY_ONE": "result",
          "CARDINALITY_OTHER": "results"
        }
      }
    }
  }
}
```

```swift
let searchStrings = try stringsFromDirectory("Examples/Readme/search")
let message = try searchStrings.get("Search completed.", placeholders: [
    "resultCount": .integer(100), "resultLimit": .integer(100), "elapsedMilliseconds": .integer(250),
    "formattedResultCount": .text("100"), "formattedResultLimit": .text("100"),
    "formattedDuration": .text("0.25 seconds")
])
// "Found at least 100 results instantly."
```

#### Placeholder Scope and Inheritance

A selected child alternative inherits generated-placeholder definitions from its ancestors and overrides same-named definitions locally. Generated values become available to other fragments as they are resolved; missing data or cycles produce structured resolution failures. Local rules can override a fragment while retaining the surrounding sentence.

### Recursive Alternatives

An alternative can contain another translation object, including its own placeholders and alternatives. This lets translators express sparse exceptions and nested agreement without duplicating every complete sentence. Nesting and cumulative expansion remain bounded.

#### Expression Language

```text
gender == GENDER_MASCULINE && (bookCount > 10 || magazineCount > 20)
resultCount >= resultLimit && elapsedMilliseconds < 1000
```

Numeric comparisons support `<`, `>`, `<=`, `>=`, `==`, and `!=`. Language-form comparisons support `==` and `!=`. `&&` binds more tightly than `||`; parentheses override precedence. Numbers can be compared with plural categories when the expression requires cardinality or ordinality. Built-in language-form names are reserved constants.

#### What Expressions Currently Support

- Bounded infix expressions and nested groups.
- Comparisons between numeric literals, supported language forms, and runtime variables.
- Cross-field comparisons and compound predicates over raw application facts.

#### What Expressions Do Not Currently Support

- Unary `!`, string or Boolean literals, or explicit `null` operands.
- Textual equality between raw strings.
- Functions or arbitrary computed return values.
- A range-expression construct; use a start/end placeholder definition for plural-range selection.

## Inspection

Immutable inspection APIs expose the fallback and supported locales, tiebreaker orders, configured callbacks/policies, plural-data identity, and authored localized strings. Use these for auditing and tooling rather than mutating a runtime after construction.

## Keying Strategy

### Natural Language Keys

`"I read {{bookCount}} books."` is readable in application code, carries translator context, and makes the default return-key behavior useful. Editing the source copy changes the key, so translations need coordinated updates.

### Contextual Keys

`"Checkout.Title"` is stable when visible copy changes and distinguishes product contexts. Add commentary so translators understand its meaning; a returned contextual key is usually an obvious failure.

### Or — Mix Both!

Use natural-language keys where they help, and contextual keys for legal copy, reused wording, or other surfaces that need stable identifiers.

## Comparing Localization Formats

Lokalized, [ICU MessageFormat](https://unicode-org.github.io/icu/userguide/format_parse/messages/), [MessageFormat 2](https://messageformat.unicode.org/docs/reference/matchers/), [Fluent](https://projectfluent.org/fluent/guide/selectors.html), and [gettext](https://www.gnu.org/software/gettext/manual/gettext.html) handle variable substitution and ordinary plurals. The differences become useful when several runtime facts jointly control wording.

### A Common Baseline: Plural Selection

```text
{bookCount, plural, one {I read # book.} other {I read # books.}}
```

Every compared format handles this ordinary case. Lokalized separates the sentence shape from the plural fragment, using the same JSON files across languages and platforms.

### Where Lokalized Goes Further Out of the Box

| Concern | Lokalized's built-in approach |
|---|---|
| Sparse compound rules | Ordered predicates combine thresholds, typed forms, parentheses, and cross-field comparisons. |
| Grammatical vocabulary | Ten typed axes shared by the files and application APIs. |
| Cardinality ranges | Pinned CLDR agreement selected from both endpoints. |
| Phonetic agreement | An application resolver supplies a typed onset category; the file owns the wording. |
| Runtime guarantees | Bounded evaluation, structured diagnostics, deterministic matching, immutable catalogs, reusable runtimes, and zero runtime dependencies. |

ICU uses nested selectors, MF2 supports multi-selector variants, Fluent uses select expressions, and gettext supplies plural selection and contextual keys. Equivalent output is possible through extensions or application logic. Cross-field inequalities such as `resultCount >= resultLimit` typically require precomputed selectors, a custom function, or branching outside those formats' stock selectors.

### Where Lokalized's Approach Shines

- Several raw runtime facts control wording, as in the search example above.
- A normal default translation needs a few compound exceptions or whole-phrase rewrites.
- Case, gender, register, phonetics, or range agreement are part of the product's actual copy requirements.
- Translators should own those language rules while the application supplies facts and owns business decisions.

See the [website's worked comparisons](https://www.lokalized.com/?platform=swift#lokalized-approach-shines) for search limits, inventory conditions, and duration ranges.

## Language Reference

The [language reference](https://www.lokalized.com/languages/?platform=swift) covers canonical CLDR plural-rule locales and common exact-tag profiles. It explains cardinalities, cardinality ranges, ordinalities, inherited rule sources, and localized strings filenames. `pt-PT`, for example, can have different rules from `pt`; tags such as `en-US` inherit the applicable plural rules while still allowing regional wording.

Plural categories do not translate words. Supply idiomatic copy for each category and keep incomplete-form warnings visible during authoring.

## About

Lokalized was created by [Mark Allen](https://www.revetkn.com). Development is sponsored by [Transmogrify LLC](https://www.xmog.com) and [Revetware LLC](https://www.revetware.com).

## iOS and macOS Integration

Preserve a `Lokalized` folder containing all locale-named JSON files in Copy Bundle Resources. These are ordinary resources; Apple `.lproj` or `.xcstrings` selection does not choose the Lokalized file. In an Xcode app, call the `makeStrings` factory above with `.main` and your app's thread-safe language-settings getter.

For SwiftPM resources, use `.copy("Lokalized")` as in the walkthrough and pass `.module` from the target that owns the resources. Frameworks pass their own bundle. For Apple's language preferences, configure `localeMatchSupplier` to call `PreferredLanguageChooser.chooseAppleLocale(using:)` instead of the app-locale supplier.

```swift
import SwiftUI
import Lokalized

struct WelcomeView: View {
    let strings: DefaultStrings
    let locale: LocaleTag // Supplied by the app's observable language settings.

    var body: some View {
        Text(verbatim: greeting)
    }

    private var greeting: String {
        do {
            return try strings.get("welcome", placeholders: ["name": .text("Ada")],
                                   options: .forLocale(locale))
        } catch {
            return "…" // This application's explicit display policy.
        }
    }
}
```

This view assumes the loaded app catalogs define `welcome`. [`Text(verbatim:)`](https://developer.apple.com/documentation/swiftui/text/init%28verbatim:%29) displays the resolved value without treating it as an Apple localization key. The app's observable language state must trigger view updates; the supplier does not redraw SwiftUI views. UIKit and AppKit assign the same resolved string to a label's text or string value.

See the [usage guide](Documentation/USAGE.md), [runnable Apple examples](Examples/README.md), [runtime API](Documentation/RUNTIME-API.md), [locale matching](Documentation/LOCALE-MATCHING.md), and [development guide](Documentation/DEVELOPMENT.md). Browse the [Swift API reference](https://swiftdoc.lokalized.com/1.0.0/documentation/lokalized/) or read how the [generated documentation](Documentation/API-REFERENCE.md) is built. The [changelog](CHANGELOG.md) and [implementation status](Documentation/IMPLEMENTATION-STATUS.md) record release scope and native compatibility evidence.
