import CryptoKit
import Foundation
import Lokalized

/// Full public-runtime observations. Fixture inputs alone configure the native
/// instance; expected fields are consumed only by ConformanceRunner's comparison.
/// Native nonoptional inputs are never simulated with invented Java null errors.
enum RuntimeObservations {
    final class Session {
        private struct Prepared {
            let strings: DefaultStrings
            let recorder: Recorder
        }
        private var cache: [String: Prepared] = [:]
        private let directoryLoader = LoaderObservations.Session()
        private(set) var pendingGuards: [RuntimeAdapterPendingGuard] = []

        func execute(_ row: BehavioralCase) throws -> JSONValue? {
            guard ["get", "getResult", "construct"].contains(row.operation), let fixture = row.fixture else {
                throw ConformanceError("Runtime operation has no fixture or is unregistered")
            }
            let fields = try fixture.checkedObject(at: "runtime.fixture")
            let input = try row.input.checkedObject(at: "runtime.input", allowed: row.operation == "construct"
                ? ["probeKey"] : ["key", "locale", "placeholders", "nullPlaceholderName", "languageRanges",
                    "translationFailureHandler", "translationFallbackPolicy", "bidiIsolation", "perCallOverrideOrder"])
            pendingGuards = try nativePendingGuards(fields, input: input)
            guard pendingGuards.isEmpty else { return nil }
            if row.operation == "construct" {
                let recorder = Recorder()
                // A model that cannot be authored is a malformed fixture, not a
                // successful observation of DefaultStrings construction refusal.
                let configuration = try configuration(fields, materialized: row.materializedFiles, recorder: recorder,
                    loadedFiles: nativeDirectoryCatalogs(row))
                do {
                    let strings = try DefaultStrings(configuration: configuration)
                    var probe: JSONValue = .null
                    if let key = try optionalString(input["probeKey"], at: "runtime.input.probeKey") {
                        do { probe = .object([.test("value", .string(try strings.get(ExactString(key)))), .test("threwType", .null)]) }
                        catch { probe = .object([.test("value", .null), .test("threwType", .string(try errorFields(error).type))]) }
                    }
                    return .object([.test("construct", .object([
                        .test("constructed", .bool(true)), .test("failureType", .null),
                        .test("failureMessage", .null), .test("probe", probe)
                    ]))])
                } catch {
                    let described = try errorFields(error)
                    return .object([.test("construct", .object([
                        .test("constructed", .bool(false)), .test("failureType", .string(described.type)),
                        .test("failureMessage", .string(described.message)), .test("probe", .null)
                    ]))])
                }
            }
            let key = try input.string("key", at: "runtime.input")
            let identity = try fixtureIdentity(fixture, materialized: row.materializedFiles)
            let prepared: Prepared
            if let prior = cache[identity] { prepared = prior }
            else {
                let recorder = Recorder()
                let config = try configuration(fields, materialized: row.materializedFiles, recorder: recorder,
                    loadedFiles: nativeDirectoryCatalogs(row))
                // Ordinary runtime fixtures must construct; their constructor
                // refusal is not the subject of a get/getResult case.
                let strings: DefaultStrings
                do { strings = try DefaultStrings(configuration: config) }
                catch { throw ConformanceError("Runtime fixture could not construct: \(try errorFields(error).message)") }
                prepared = Prepared(strings: strings, recorder: recorder)
                cache[identity] = prepared
            }
            prepared.recorder.reset()
            do {
                let values = PlaceholderValues(try placeholders(input["placeholders"]))
                let options = try options(input, matcher: prepared.strings, recorder: prepared.recorder)
                var observed: [JSONMember]
                let result: TranslationResult?
                if row.operation == "getResult" {
                    let returned = try prepared.strings.getResult(ExactString(key), placeholders: values, options: options)
                    result = returned
                    observed = [.test("result", try resultObservation(returned))]
                } else {
                    result = nil
                    observed = [.test("translation", .string(try prepared.strings.get(ExactString(key), placeholders: values, options: options)))]
                }
                // An absent finite mapping is native-unrepresentable only if
                // the callback actually consults it. This is input driven.
                if prepared.recorder.nativeUnavailable {
                    pendingGuards = prepared.recorder.unavailableGuards; return nil
                }
                try addChannels(to: &observed, recorder: prepared.recorder, result: result)
                if row.operation == "getResult", let locale = try optionalString(input["locale"], at: "runtime.input.locale") {
                    observed.append(.test("match", try matchObservation(prepared.strings.matchFor(LocaleTag.forLanguageTag(locale)))))
                }
                return .object(observed)
            } catch {
                if prepared.recorder.nativeUnavailable {
                    pendingGuards = prepared.recorder.unavailableGuards; return nil
                }
                // Conformance authoring/decoder errors may never impersonate an
                // observed library/application exception.
                if error is ConformanceError { throw error }
                var observed: [JSONMember] = [.test("thrown", try thrownObservation(error, recorder: prepared.recorder))]
                try addChannels(to: &observed, recorder: prepared.recorder, result: nil)
                return .object(observed)
            }
        }

        private func nativeDirectoryCatalogs(_ row: BehavioralCase) throws -> [LocaleTag: ParsedStringsFile]? {
            guard let fixture = row.fixture,
                  case .string("directory") = try fixture.checkedObject(at: "runtime.fixture")["pathShape"] else { return nil }
            return try directoryLoader.load(row)
        }
    }

    static func execute(_ row: BehavioralCase) throws -> JSONValue? { try Session().execute(row) }

    private static func fixtureIdentity(_ fixture: JSONValue, materialized: [ExactString: Data]?) throws -> String {
        var hash = SHA256()
        hash.update(data: try FixtureJSONWriter.bytes(fixture))
        guard let materialized else { throw ConformanceError("Runtime fixture lacks pinned materialized source bytes") }
        for name in materialized.keys.sorted() {
            hash.update(data: Data(FixtureJSONWriter.quote(name.string).utf8))
            let bytes = materialized[name]!
            hash.update(data: Data(String(bytes.count).utf8)); hash.update(data: Data([0]))
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func nativePendingGuards(_ fixture: [ExactString: JSONValue], input: [ExactString: JSONValue]) throws -> [RuntimeAdapterPendingGuard] {
        var guards: [RuntimeAdapterPendingGuard] = []
        if let value = input["nullPlaceholderName"] {
            guard case .bool(let present) = value else { throw ConformanceError("nullPlaceholderName must be a Boolean") }
            if present { guards.append(.init(category: "placeholder-name-null", inputPath: "input.nullPlaceholderName",
                evidence: "true requests a null key; PlaceholderValues keys are nonoptional ExactString")) }
        }
        let overrides = try overrideFields(fixture["constructionOverrides"])
        if let source = try optionalString(overrides["catalogSource"], at: "catalogSource"),
           ["returnsNull", "nullLocaleKey", "nullCatalogValue", "nullEntry"].contains(source) {
            guards.append(.init(category: "catalog-null-shape", inputPath: "fixture.constructionOverrides.catalogSource",
                evidence: "\(source) is not representable by supplier -> [LocaleTag:LocalizedCatalog] and nonoptional catalog entries"))
        }
        if let source = try optionalString(overrides["tiebreakerSource"], at: "tiebreakerSource"),
           ["nullList", "nullEntry", "nullLanguageCode"].contains(source) {
            guards.append(.init(category: "tiebreaker-null-shape", inputPath: "fixture.constructionOverrides.tiebreakerSource",
                evidence: "\(source) is not representable by [String:[LocaleTag]]"))
        }
        for name in ["translationFailureHandler", "translationFallbackPolicy", "phoneticResolver"] {
            for (path, value) in [("fixture", fixture[ExactString(name)]), ("input", input[ExactString(name)])] {
                if let value, case .object = value {
                    let allowed: Set<String>
                    switch name {
                    case "translationFailureHandler": allowed = ["behavior", "text", "message"]
                    case "translationFallbackPolicy": allowed = ["behavior", "locales", "reasons", "message"]
                    default: allowed = ["behavior", "phonetic", "mapping", "default", "message"]
                    }
                    let fields = try value.checkedObject(at: name, allowed: allowed)
                    if try optionalString(fields["behavior"], at: name + ".behavior") == "return-null" {
                        guards.append(.init(category: "callback-null-configuration", inputPath: path + "." + name + ".behavior",
                            evidence: "return-null is not representable by the nonoptional native callback return type; no runtime null diagnostic is synthesized"))
                    }
                }
            }
        }
        return guards
    }

    private static func overrideFields(_ value: JSONValue?) throws -> [ExactString: JSONValue] {
        guard let value, !isNull(value) else { return [:] }
        return try value.checkedObject(at: "constructionOverrides", allowed: ["catalogSource", "definedCatalog", "localeSource", "tiebreakerSource", "instanceCallbacks"])
    }

    private static func configuration(_ fixture: [ExactString: JSONValue], materialized: [ExactString: Data]?, recorder: Recorder,
                                      loadedFiles: [LocaleTag: ParsedStringsFile]? = nil) throws -> StringsConfiguration {
        let overrides = try overrideFields(fixture["constructionOverrides"])
        let fallback = LocaleTag.forLanguageTag(try fixture.string("fallbackLocale", at: "runtime.fixture"))
        var names = Set<ExactString>()
        for name in ["files", "rawFiles", "rawFilesBase64"] {
            names.formUnion(try fixture.value(name, at: "runtime.fixture").checkedObject(at: name).keys)
        }
        var loaded: [LocaleTag: LocalizedCatalog] = [:]
        if let loadedFiles { loaded = loadedFiles.mapValues { LocalizedCatalog(strings: $0.strings) } }
        else {
            // Only non-directory fixture carriers keep the earlier explicit
            // parser projection; no native directory load is claimed for them.
            let loadingOptions = try CatalogObservations.loadingOptions(fixture["loadingOptions"])
            for filename in names.sorted() {
                let name = filename.string
                let tag = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
                guard JDKLocaleTag.isCatalogLanguageTag(tag) else { continue }
                let locale = try LocaleTag(tag)
                let parsed = try LocalizedStringLoader.parse(CatalogObservations.fileBytes(name, fixture: fixture, materialized: materialized),
                    locale: locale.tag, source: name, loadingOptions: loadingOptions)
                guard loaded[locale] == nil else { throw ConformanceError("Runtime fixture needs unimplemented transport merging: \(name)") }
                loaded[locale] = LocalizedCatalog(strings: parsed.strings)
            }
        }
        let firstCatalog = loaded.keys.sorted { ExactString($0.tag) < ExactString($1.tag) }.first.flatMap { loaded[$0] } ?? LocalizedCatalog(strings: [])
        let supplier: LocalizedStringSupplier?
        switch try optionalString(overrides["catalogSource"], at: "catalogSource") {
        case nil: let catalog = loaded; supplier = { catalog }
        case "omit": supplier = nil
        case "duplicateNormalizedTag":
            let catalog = [LocaleTag.forLanguageTag("en-US-POSIX"): firstCatalog, LocaleTag.forLanguageTag("en-US-posix"): firstCatalog]
            supplier = { catalog }
        case "duplicateKey":
            let catalog = [LocaleTag.forLanguageTag("en"): LocalizedCatalog(strings: firstCatalog.strings.first.map { [$0, $0] } ?? [])]
            supplier = { catalog }
        case "defined":
            guard case .array(let nodes) = overrides["definedCatalog"] else { throw ConformanceError("Defined catalog override needs an array") }
            let strings: [LocalizedString]
            do { strings = try nodes.map { try CatalogObservations.buildLocalizedString($0) } }
            catch { throw ConformanceError("Defined catalog model cannot be authored: \(error)") }
            let catalog = [fallback: LocalizedCatalog(strings: strings)]; supplier = { catalog }
        default: throw ConformanceError("Unknown or unrepresentable catalogSource override")
        }
        let localeSource = try optionalString(overrides["localeSource"], at: "localeSource")
        var localeSupplier: LocaleSupplier?, matchSupplier: LocaleMatchSupplier?
        switch localeSource {
        case "omit": break
        case "explicitNullLocaleSupplier": matchSupplier = try localeMatchSupplier(fixture["localeMatchSupplier"], recorder: recorder)
        case "explicitNullMatchSupplier": localeSupplier = try ambientLocaleSupplier(fixture["localeSupplier"], recorder: recorder)
        case nil:
            if let match = fixture["localeMatchSupplier"], !isNull(match) {
                if let locale = fixture["localeSupplier"], !isNull(locale) { throw ConformanceError("Fixture declares both ambient suppliers") }
                matchSupplier = try localeMatchSupplier(match, recorder: recorder)
            } else if let locale = fixture["localeSupplier"], !isNull(locale) {
                localeSupplier = try ambientLocaleSupplier(locale, recorder: recorder)
            } else {
                let tag = LocaleTag.forLanguageTag(try fixture.string("instanceLocale", at: "runtime.fixture"))
                localeSupplier = { _ in tag }
            }
        default: throw ConformanceError("Unknown localeSource override")
        }
        if overrides["tiebreakerSource"] != nil { throw ConformanceError("Unknown or unrepresentable tiebreakerSource override") }
        var tiebreakers: [String: [LocaleTag]]?
        if let value = fixture["tiebreakers"], !isNull(value) {
            var pairs: [String: [LocaleTag]] = [:]
            for (language, value) in try value.checkedObject(at: "runtime.tiebreakers") {
                guard case .array(let tags) = value else { throw ConformanceError("Tiebreaker value is not an array") }
                pairs[language.string] = try tags.map { value in
                    guard case .string(let tag) = value else { throw ConformanceError("Tiebreaker locale is not a string") }
                    return LocaleTag.forLanguageTag(tag)
                }
            }
            tiebreakers = pairs
        }
        let handler: TranslationFailureHandler?, fallbackPolicy: TranslationFallbackPolicy?
        switch try optionalString(overrides["instanceCallbacks"], at: "instanceCallbacks") {
        case "libraryDefaults":
            guard fixture["translationFailureHandler"].map(isNull) ?? true,
                  fixture["translationFallbackPolicy"].map(isNull) ?? true else { throw ConformanceError("libraryDefaults conflicts with named callbacks") }
            handler = nil; fallbackPolicy = nil
        case nil:
            handler = try failureHandler(fixture["translationFailureHandler"], recorder: recorder)
            fallbackPolicy = try policy(fixture["translationFallbackPolicy"], recorder: recorder)
        default: throw ConformanceError("Unknown instanceCallbacks override")
        }
        return StringsConfiguration(localizedStringSupplier: supplier, localeSupplier: localeSupplier, localeMatchSupplier: matchSupplier,
            fallbackLocale: fallback, tiebreakerLocalesByLanguageCode: tiebreakers, translationFailureHandler: handler,
            translationFallbackPolicy: fallbackPolicy, runtimeLimits: try limits(fixture["runtimeLimits"]),
            phoneticResolver: try resolver(fixture["phoneticResolver"], recorder: recorder), bidiIsolation: try bidi(fixture["bidiIsolation"]))
    }

    private static func options(_ input: [ExactString: JSONValue], matcher: any LocaleMatcher, recorder: Recorder) throws -> TranslationOptions {
        let locale = try optionalString(input["locale"], at: "runtime.input.locale").map(LocaleTag.forLanguageTag)
        let ranges = try input["languageRanges"].flatMap { try languageRanges($0, matcher: matcher) }
        var selectedLocale = locale, selectedRanges = ranges
        if locale != nil && ranges != nil {
            guard case .array(let values) = input["perCallOverrideOrder"] else { throw ConformanceError("Both overrides require perCallOverrideOrder") }
            let order = try values.map { value -> String in
                guard case .string(let name) = value else { throw ConformanceError("Override order item is not a string") }; return name
            }
            guard order.count == 2, Set(order) == ["locale", "languageRanges"] else { throw ConformanceError("Override order is not an exact permutation") }
            if order.last == "locale" { selectedRanges = nil } else { selectedLocale = nil }
        } else if input["perCallOverrideOrder"] != nil { throw ConformanceError("Override order is declared but decides nothing") }
        let handler = try input["translationFailureHandler"].flatMap { isNull($0) ? nil : try failureHandler($0, recorder: recorder) }
        let fallbackPolicy = try input["translationFallbackPolicy"].flatMap { isNull($0) ? nil : try policy($0, recorder: recorder) }
        return try TranslationOptions(locale: selectedLocale, languageRanges: selectedRanges,
            bidiIsolation: bidi(input["bidiIsolation"]), translationFailureHandler: handler, translationFallbackPolicy: fallbackPolicy)
    }

    private static func languageRanges(_ value: JSONValue, matcher: any LocaleMatcher) throws -> [LanguageRange]? {
        if isNull(value) { return nil }
        if case .string(let text) = value { return try matcher.parseLanguageRanges(text) }
        guard case .array(let values) = value else { throw ConformanceError("Language ranges are not a header or array") }
        return try values.map { value in
            if case .string(let range) = value { return try LanguageRange(range) }
            let fields = try value.checkedObject(at: "runtime.languageRange", allowed: ["range", "weight"])
            let weight: Double
            if let value = fields["weight"] {
                guard case .number(let literal) = value, let number = LanguageRangeWeight.parse(literal) else { throw ConformanceError("Invalid language range weight") }
                weight = number
            } else { weight = 1 }
            return try LanguageRange(fields.string("range", at: "runtime.languageRange"), weight: weight)
        }
    }

    private static func ambientLocaleSupplier(_ value: JSONValue?, recorder: Recorder) throws -> LocaleSupplier {
        guard let value, !isNull(value) else { throw ConformanceError("Named locale supplier is absent") }
        let fields = try value.checkedObject(at: "runtime.localeSupplier", allowed: ["behavior", "locale", "ranges"])
        let behavior = try fields.string("behavior", at: "runtime.localeSupplier")
        guard ["constant", "match-ranges"].contains(behavior) else { throw ConformanceError("Unknown locale supplier behavior") }
        return { matcher in
            let result: LocaleTag
            if behavior == "constant" { result = LocaleTag.forLanguageTag(try fields.string("locale", at: "runtime.localeSupplier")) }
            else {
                let ranges = try languageRanges(fields.value("ranges", at: "runtime.localeSupplier"), matcher: matcher) ?? []
                let match = try matcher.matchFor(ranges)
                result = match.localeTag ?? match.fallbackLocaleTag
            }
            recorder.appendSupplier(.object([.test("kind", .string("localeSupplier")), .test("returnedLocale", .string(result.tag)), .test("returnedMatchType", .null)]))
            return result
        }
    }

    private static func localeMatchSupplier(_ value: JSONValue?, recorder: Recorder) throws -> LocaleMatchSupplier {
        guard let value, !isNull(value) else { throw ConformanceError("Named match supplier is absent") }
        let fields = try value.checkedObject(at: "runtime.localeMatchSupplier", allowed: ["behavior", "locale", "ranges", "range", "weight", "matchType", "fallbackLocale", "consideredLocales"])
        let behavior = try fields.string("behavior", at: "runtime.localeMatchSupplier")
        guard ["match-ranges", "match-locale", "fabricated"].contains(behavior) else { throw ConformanceError("Unknown match supplier behavior") }
        return { matcher in
            let result: LocaleMatchResult
            switch behavior {
            case "match-ranges": result = try matcher.matchFor(languageRanges(fields.value("ranges", at: "runtime.localeMatchSupplier"), matcher: matcher) ?? [])
            case "match-locale": result = try matcher.matchFor(LocaleTag.forLanguageTag(fields.string("locale", at: "runtime.localeMatchSupplier")))
            default:
                let ranges = try fields["ranges"].flatMap { try languageRanges($0, matcher: matcher) } ?? []
                let locale = try optionalString(fields["locale"], at: "fabricated.locale").map(LocaleTag.forLanguageTag)
                let range = try optionalString(fields["range"], at: "fabricated.range").map { try LanguageRange($0) }
                let weight: Double?
                switch fields["weight"] {
                case nil, .some(.null): weight = nil
                case .some(.number(let literal)):
                    guard let value = LanguageRangeWeight.parse(literal) else { throw ConformanceError("Invalid fabricated weight") }; weight = value
                case .some(.string("infinity")): weight = .infinity
                case .some(.string("nan")): weight = .nan
                default: throw ConformanceError("Unknown fabricated weight sentinel")
                }
                var considered: [LocaleTag] = []
                if let value = fields["consideredLocales"] {
                    guard case .array(let values) = value else { throw ConformanceError("Fabricated considered locales are not an array") }
                    considered = try values.map { value in
                        guard case .string(let tag) = value else { throw ConformanceError("Fabricated considered locale is not a string") }; return LocaleTag.forLanguageTag(tag)
                    }
                }
                result = try LocaleMatchResult(requestedLanguageRanges: ranges, locale: locale, languageRange: range,
                    effectiveWeight: weight, matchType: matchType(try optionalString(fields["matchType"], at: "fabricated.matchType") ?? "NONE"),
                    fallbackLocale: LocaleTag.forLanguageTag(try optionalString(fields["fallbackLocale"], at: "fabricated.fallbackLocale") ?? "en"), consideredLocales: considered)
            }
            recorder.appendSupplier(.object([.test("kind", .string("localeMatchSupplier")), .test("returnedLocale", result.locale.map(JSONValue.string) ?? .null),
                .test("returnedMatchType", .string(matchTypeName(result.matchType)))]))
            return result
        }
    }

    private static func failureHandler(_ value: JSONValue?, recorder: Recorder) throws -> TranslationFailureHandler {
        let fields = try value.flatMap { isNull($0) ? nil : try $0.checkedObject(at: "runtime.handler", allowed: ["behavior", "text", "message"]) } ?? [:]
        let behavior = try optionalString(fields["behavior"], at: "runtime.handler.behavior") ?? "return-key"
        guard ["return-key", "throw", "return-string", "throw-in-handler"].contains(behavior) else { throw ConformanceError("Unknown or unrepresentable handler behavior") }
        let text = try optionalString(fields["text"], at: "runtime.handler.text")
        let message = try optionalString(fields["message"], at: "runtime.handler.message") ?? "handler failed deliberately"
        if behavior == "return-string", text == nil { throw ConformanceError("Return-string handler has no text") }
        return TranslationFailureHandler { failure in
            recorder.appendFailure(failure)
            switch behavior {
            case "throw": return .throwException
            case "return-string": return .returnString(text!)
            case "throw-in-handler": throw TranslationEvaluationError(kind: .invalidState, message: message)
            default: return .returnKey
            }
        }
    }

    private static func policy(_ value: JSONValue?, recorder: Recorder) throws -> TranslationFallbackPolicy {
        let delegate: TranslationFallbackPolicy
        switch value {
        case nil, .some(.null), .some(.string("missing-or-no-match")): delegate = .fallbackOnMissingTranslationOrNoMatchingAlternative()
        case .some(.string("any-failure")): delegate = .fallbackOnAnyFailure()
        case .some(.string("never")): delegate = .neverFallback()
        case .some(let value):
            let fields = try value.checkedObject(at: "runtime.policy", allowed: ["behavior", "locales", "reasons", "message"])
            switch try fields.string("behavior", at: "runtime.policy") {
            case "continue-for-locales", "continue-for-reasons":
                let locales = fields["locales"] != nil
                guard case .array(let values) = fields[locales ? "locales" : "reasons"] else { throw ConformanceError("Custom policy requires values") }
                let accepted = try Set(values.map { value -> ExactString in
                    guard case .string(let text) = value else { throw ConformanceError("Custom policy value is not a string") }; return ExactString(text)
                })
                delegate = TranslationFallbackPolicy { reason, locale, _ in accepted.contains(ExactString(locales ? locale.tag : reason.displayName)) }
            case "throw-in-policy":
                let message = try optionalString(fields["message"], at: "runtime.policy.message") ?? "fallback policy failed deliberately"
                delegate = TranslationFallbackPolicy { _, _, _ in throw TranslationEvaluationError(kind: .invalidState, message: message) }
            default: throw ConformanceError("Unknown or unrepresentable fallback policy behavior")
            }
        }
        return TranslationFallbackPolicy { reason, locale, cause in
            let causeType = try cause.map { .string(try errorFields($0).type) } ?? JSONValue.null
            var call: [JSONMember] = [.test("reason", .string(reason.displayName)), .test("locale", .string(locale.tag)),
                .test("causeType", causeType), .test("decision", .null)]
            let index = recorder.appendPolicy(.object(call))
            do {
                let result = try delegate.shouldTryNextLocale(reason: reason, attemptedLocale: locale, cause: cause)
                call[3] = .test("decision", .bool(result)); recorder.replacePolicy(index, .object(call)); return result
            } catch {
                call.append(.test("threw", .string(try errorFields(error).type))); recorder.replacePolicy(index, .object(call)); throw error
            }
        }
    }

    private static func addChannels(to observation: inout [JSONMember], recorder: Recorder, result: TranslationResult?) throws {
        let snapshot = recorder.snapshot
        if !snapshot.failures.isEmpty { observation.append(.test("failures", .array(try snapshot.failures.map { try failureObservation($0, result: result) }))) }
        if !snapshot.resolvers.isEmpty { observation.append(.test("resolverCalls", .array(snapshot.resolvers))) }
        if !snapshot.policies.isEmpty { observation.append(.test("policyCalls", .array(snapshot.policies))) }
        if !snapshot.suppliers.isEmpty { observation.append(.test("supplierCalls", .array(snapshot.suppliers))) }
    }

    private static func resultObservation(_ result: TranslationResult) throws -> JSONValue {
        .object([.test("key", .string(result.key.string)), .test("translation", .string(result.translation)),
            .test("status", .string(result.status.displayName)), .test("lookupLocale", .string(result.lookupLocale.tag)),
            .test("resolvedLocale", result.resolvedLocale.map { .string($0.tag) } ?? .null),
            .test("attemptedLocales", tags(result.attemptedLocales)), .test("isFallback", .bool(result.isFallback)),
            .test("failureReason", result.failureReason.map { .string($0.displayName) } ?? .null),
            .test("failureCause", try result.cause.map(causeObservation) ?? .null),
            .test("localeMatchResult", try result.localeMatchResult.map(matchObservation) ?? .null)])
    }

    private static func failureObservation(_ failure: TranslationFailure, result: TranslationResult?) throws -> JSONValue {
        let cause = try failure.cause.map(errorFields)
        let identity: JSONValue = result?.localeMatchResult.map { match in .bool(failure.localeMatchResult === match) } ?? .null
        return .object([.test("key", .string(failure.key.string)), .test("reason", .string(failure.reason.displayName)),
            .test("lookupLocale", .string(failure.lookupLocale.tag)), .test("attemptedLocales", tags(failure.attemptedLocales)),
            .test("message", .string(failure.message)), .test("placeholderNames", .array(failure.placeholders.keys.sorted().map { .string($0.string) })),
            .test("causeType", cause.map { .string($0.type) } ?? .null), .test("causeMessage", cause.map { .string($0.message) } ?? .null),
            .test("localeMatchResult", try failure.localeMatchResult.map(matchObservation) ?? .null),
            .test("matchObjectIdenticalToResult", identity)])
    }

    private static func causeObservation(_ error: any Error) throws -> JSONValue {
        let fields = try errorFields(error), cause = try fields.cause.map(errorFields)
        return .object([.test("type", .string(fields.type)), .test("message", .string(fields.message)),
            .test("causeType", cause.map { .string($0.type) } ?? .null), .test("causeMessage", cause.map { .string($0.message) } ?? .null)])
    }

    private static func thrownObservation(_ error: any Error, recorder: Recorder) throws -> JSONValue {
        let fields = try errorFields(error)
        let retained = recorder.snapshot.failures.last?.cause
        return .object([.test("type", .string(fields.type)), .test("message", .string(fields.message)),
            .test("causeType", try fields.cause.map { .string(try errorFields($0).type) } ?? .null),
            .test("identicalToRetainedCause", retained.map { .bool((error as AnyObject) === ($0 as AnyObject)) } ?? .null)])
    }

    private static func errorFields(_ error: any Error) throws -> (type: String, message: String, cause: (any Error)?) {
        switch error {
        case let error as TranslationEvaluationError:
            let type: String
            switch error.kind { case .expression: type = "com.lokalized.ExpressionEvaluationException"; case .invalidArgument: type = "java.lang.IllegalArgumentException"; case .invalidState: type = "java.lang.IllegalStateException" }
            return (type, error.message, error.cause)
        case let error as ConfigurationError:
            return (error.kind == .invalidArgument ? "java.lang.IllegalArgumentException" : "java.lang.IllegalStateException", error.message, error.cause)
        case let error as MissingTranslationError: return ("com.lokalized.MissingTranslationException", error.message, nil)
        case let error as ExpressionCompilationError: return ("com.lokalized.ExpressionEvaluationException", error.message, error.cause)
        case let error as NumericError:
            let type: String
            switch error.kind { case .invalidArgument: type = "java.lang.IllegalArgumentException"; case .invalidDecimal: type = "java.lang.NumberFormatException"; case .roundingNecessary: type = "java.lang.ArithmeticException" }
            return (type, error.message, nil)
        case let error as UnsupportedLocaleError: return ("com.lokalized.UnsupportedLocaleException", error.message, nil)
        case let error as LocaleMatcherError: return ("java.lang.IllegalArgumentException", error.message, nil)
        case let error as LocaleTagError:
            // The native malformedLocale category represents Locale.Builder's
            // checked rebuildability refusal retained as an immediate cause.
            return (error.kind == .malformedLocale ? "java.util.IllformedLocaleException" : "java.lang.IllegalArgumentException", error.message, nil)
        case let error as LanguageRangeError:
            return (error.kind == .indexOutOfBounds ? "java.lang.ArrayIndexOutOfBoundsException" : "java.lang.IllegalArgumentException", error.message, nil)
        case let error as TranslationRuntimeLimits.ValidationError: return ("java.lang.IllegalArgumentException", error.description, nil)
        default: throw ConformanceError("Unregistered runtime error type: \(String(reflecting: type(of: error)))")
        }
    }

    private static func matchObservation(_ result: LocaleMatchResult) throws -> JSONValue {
        .object([.test("consideredLocales", .array(result.consideredLocales.map(JSONValue.string))),
            .test("effectiveWeight", try result.effectiveWeight.map(number) ?? .null), .test("fallbackLocale", .string(result.fallbackLocale)),
            .test("isMatch", .bool(result.isMatch)), .test("languageRange", result.languageRange.map { .string($0.range) } ?? .null),
            .test("locale", result.locale.map(JSONValue.string) ?? .null), .test("matchType", .string(matchTypeName(result.matchType))),
            .test("requestedLanguageRanges", .array(try result.requestedLanguageRanges.map { range in
                .object([.test("range", .string(range.range)), .test("weight", try number(range.weight))])
            }))])
    }
    private static func number(_ value: Double) throws -> JSONValue {
        guard value.isFinite else { throw ConformanceError("Nonfinite match weight cannot be observed in JSON") }
        let decimal = try ExactDecimal(JavaFloatingPoint.decimalString(value)).strippingTrailingZeros()
        let exponent = decimal.precision - 1 - decimal.scale
        if exponent >= -6 && exponent < 21 { return .number(decimal.plainString) }
        let digits = String(decoding: decimal.digits, as: UTF8.self)
        let mantissa = String(digits.prefix(1)) + (digits.count > 1 ? "." + digits.dropFirst() : "")
        return .number((decimal.signum < 0 ? "-" : "") + mantissa + "e" + (exponent >= 0 ? "+" : "") + String(exponent))
    }
    private static func matchTypeName(_ value: LocaleMatchType) -> String {
        switch value { case .noMatch: "NONE"; case .exact: "EXACT"; case .canonical: "CANONICAL"; case .cldrFallback: "CLDR_FALLBACK"; case .likelySubtag: "LIKELY_SUBTAG"; case .extendedRange: "EXTENDED_RANGE"; case .primaryLanguage: "PRIMARY_LANGUAGE"; case .wildcard: "WILDCARD" }
    }
    private static func matchType(_ text: String) throws -> LocaleMatchType {
        switch text { case "NONE": .noMatch; case "EXACT": .exact; case "CANONICAL": .canonical; case "CLDR_FALLBACK": .cldrFallback; case "LIKELY_SUBTAG": .likelySubtag; case "EXTENDED_RANGE": .extendedRange; case "PRIMARY_LANGUAGE": .primaryLanguage; case "WILDCARD": .wildcard; default: throw ConformanceError("Unknown fabricated match type") }
    }
    private static func tags(_ values: [LocaleTag]) -> JSONValue { .array(values.map { .string($0.tag) }) }
    private static func isNull(_ value: JSONValue) -> Bool { if case .null = value { true } else { false } }
    private static func optionalString(_ value: JSONValue?, at path: String) throws -> String? {
        guard let value, !isNull(value) else { return nil }
        guard case .string(let text) = value else { throw ConformanceError("Expected string or null at \(path)") }; return text
    }
    private static func bidi(_ value: JSONValue?) throws -> BidiIsolation? {
        switch value { case nil, .some(.null): nil; case .some(.string("NONE")): .disabled; case .some(.string("ALWAYS")): .always; case .some(.string("RTL_LOCALES")): .rtlLocales; default: throw ConformanceError("Unknown bidi isolation") }
    }

    private static func placeholders(_ value: JSONValue?) throws -> [ExactString: PlaceholderValue] {
        guard let value else { return [:] }
        let fields = try value.checkedObject(at: "runtime.placeholders")
        var result: [ExactString: PlaceholderValue] = [:]
        for key in fields.keys.sorted() { result[key] = try placeholder(fields[key]!) }
        return result
    }
    private static func placeholder(_ value: JSONValue) throws -> PlaceholderValue {
        switch value {
        case .null: return .null
        case .string(let text): return .text(text)
        case .bool(let value): return .boolean(value)
        case .number(let text):
            if text.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }) {
                if let value = Int32(text) { return .integer(value) }
                if let value = Int64(text) { return .number(.integer(value)) }
                return .number(try .forBigInteger(text, runtimeLimits: .numericHardCeilings))
            }
            guard let value = LanguageRangeWeight.parse(text) else { throw ConformanceError("Invalid JSON double carrier") }
            return .number(.double(value))
        case .object:
            let fields = try value.checkedObject(at: "runtime.taggedPlaceholder", allowed: ["$lokalized", "value", "axis", "name", "renderName", "visibleDecimalPlaces", "compactExponent"])
            switch try fields.string("$lokalized", at: "runtime.taggedPlaceholder") {
            case "decimal": return .number(try .forDecimal(fields.string("value", at: "carrier"), runtimeLimits: .numericHardCeilings))
            case "bigint": return .number(try .forBigInteger(fields.string("value", at: "carrier"), runtimeLimits: .numericHardCeilings))
            case "integer":
                guard let value = Int32(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Integer carrier") }
                return .integer(value)
            case "long":
                guard let value = Int64(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Long carrier") }
                return .number(.integer(value))
            case "double":
                guard let value = LanguageRangeWeight.parse(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Double carrier") }
                return .number(.double(value))
            case "float":
                guard let value = Float(try fields.string("value", at: "carrier")) else { throw ConformanceError("Invalid Float carrier") }
                return .number(.float(value))
            case "plural-operands":
                return .pluralOperands(try PluralOperands(.forDecimal(fields.string("value", at: "carrier"), runtimeLimits: .numericHardCeilings),
                    visibleDecimalPlaces: integer(fields["visibleDecimalPlaces"]), compactExponent: integer(fields["compactExponent"])))
            case "language-form":
                let name = try fields.string("name", at: "carrier"), axis = try fields.string("axis", at: "carrier")
                guard let form = LanguageFormValue(rawValue: name), axisName(form.axis) == axis else { throw ConformanceError("Invalid language form carrier") }
                if let renderName = fields["renderName"] {
                    guard case .string(let text) = renderName, ExactString(text) == ExactString(form.displayName) else { throw ConformanceError("Invalid language form renderName") }
                }
                return .languageForm(form)
            default: throw ConformanceError("Unknown tagged placeholder carrier")
            }
        default: throw ConformanceError("Unsupported placeholder carrier shape")
        }
    }
    private static func axisName(_ axis: LanguageFormAxis) -> String {
        switch axis {
        case .grammaticalCase: "grammatical-case"
        default: axis.rawValue.lowercased()
        }
    }
    private static func integer(_ value: JSONValue?) throws -> Int? {
        guard let value else { return nil }
        guard case .number(let text) = value, let number = Int(text) else { throw ConformanceError("Invalid integer component option") }
        return number
    }
    private static func limits(_ value: JSONValue?) throws -> TranslationRuntimeLimits {
        if value == nil { return .defaults }
        if case .null = value { return .defaults }
        let fields = try value!.checkedObject(at: "runtime.runtimeLimits", allowed: [
            "maximumNumberPrecision", "maximumAbsoluteNumberScale", "maximumVisibleDecimalPlaces", "maximumCompactExponent",
            "maximumExpressionCharacters", "maximumExpressionTokens", "maximumExpressionNestingDepth", "maximumGeneratedPlaceholderDepth",
            "maximumInterpolatedOutputCharacters", "maximumGeneratedExpansionCharacters"
        ])
        let defaults = TranslationRuntimeLimits.defaults
        return try .init(maximumNumberPrecision: integer(fields["maximumNumberPrecision"]) ?? defaults.maximumNumberPrecision,
            maximumAbsoluteNumberScale: integer(fields["maximumAbsoluteNumberScale"]) ?? defaults.maximumAbsoluteNumberScale,
            maximumVisibleDecimalPlaces: integer(fields["maximumVisibleDecimalPlaces"]) ?? defaults.maximumVisibleDecimalPlaces,
            maximumCompactExponent: integer(fields["maximumCompactExponent"]) ?? defaults.maximumCompactExponent,
            maximumExpressionCharacters: integer(fields["maximumExpressionCharacters"]) ?? defaults.maximumExpressionCharacters,
            maximumExpressionTokens: integer(fields["maximumExpressionTokens"]) ?? defaults.maximumExpressionTokens,
            maximumExpressionNestingDepth: integer(fields["maximumExpressionNestingDepth"]) ?? defaults.maximumExpressionNestingDepth,
            maximumGeneratedPlaceholderDepth: integer(fields["maximumGeneratedPlaceholderDepth"]) ?? defaults.maximumGeneratedPlaceholderDepth,
            maximumInterpolatedOutputCharacters: integer(fields["maximumInterpolatedOutputCharacters"]) ?? defaults.maximumInterpolatedOutputCharacters,
            maximumGeneratedExpansionCharacters: integer(fields["maximumGeneratedExpansionCharacters"]) ?? defaults.maximumGeneratedExpansionCharacters)
    }


    private static func resolver(_ value: JSONValue?, recorder: Recorder) throws -> PhoneticResolver? {
        guard let value, !isNull(value) else { return nil }
        let fields = try value.checkedObject(at: "runtime.resolver", allowed: ["behavior", "phonetic", "mapping", "default", "message"])
        let behavior = try fields.string("behavior", at: "runtime.resolver")
        func phonetic(_ name: String) throws -> Phonetic {
            guard let form = Phonetic(rawValue: name) else { throw ConformanceError("Unknown phonetic resolver form") }; return form
        }
        let delegate: PhoneticResolver
        switch behavior {
        case "constant":
            let form = try phonetic(fields.string("phonetic", at: "runtime.resolver")); delegate = { _, _ in form }
        case "by-term", "by-locale":
            let source = try fields.value("mapping", at: "runtime.resolver").checkedObject(at: "runtime.resolver.mapping")
            var mapping: [ExactString: Phonetic] = [:]
            for (key, value) in source {
                guard case .string(let name) = value else { throw ConformanceError("Invalid phonetic resolver mapping") }
                mapping[key] = try phonetic(name)
            }
            let fixedMapping = mapping
            let fallback = try optionalString(fields["default"], at: "runtime.resolver.default").map(phonetic)
            delegate = { term, locale in
                if let form = fixedMapping[ExactString(behavior == "by-term" ? term : locale.tag)] ?? fallback { return form }
                recorder.markNativeUnavailable(term: term, locale: locale.tag, selector: behavior)
                throw NativeUnavailable()
            }
        case "first-letter-vowel":
            delegate = { term, _ in term.utf16.first.map { [65, 69, 73, 79, 85, 97, 101, 105, 111, 117].contains($0) } == true ? .vowel : .consonant }
        case "throw":
            let message = try optionalString(fields["message"], at: "runtime.resolver.message") ?? "phonetic resolver failed deliberately"
            delegate = { _, _ in throw TranslationEvaluationError(kind: .invalidState, message: message) }
        default: throw ConformanceError("Unknown or unrepresentable phonetic resolver behavior")
        }
        return { term, locale in
            do {
                let result = try delegate(term, locale)
                recorder.appendResolver(.object([.test("term", .string(term)), .test("locale", .string(locale.tag)),
                    .test("returned", .string(result.displayName)), .test("threw", .null)]))
                return result
            } catch {
                // This marker only changes the row's disposition to pending;
                // it can never be serialized as a plausible runtime failure.
                if error is NativeUnavailable { throw error }
                recorder.appendResolver(.object([.test("term", .string(term)), .test("locale", .string(locale.tag)),
                    .test("returned", .null), .test("threw", .string(try errorFields(error).type))]))
                throw error
            }
        }
    }

    private struct NativeUnavailable: Error {}
    /// Development observation only. Each instance belongs to a serial audit
    /// fixture; the lock protects all mutable storage and no callback runs under it.
    private final class Recorder: @unchecked Sendable {
        struct Snapshot {
            let failures: [TranslationFailure]
            let resolvers: [JSONValue]
            let policies: [JSONValue]
            let suppliers: [JSONValue]
        }
        private let lock = NSLock()
        private var failures: [TranslationFailure] = []
        private var resolvers: [JSONValue] = []
        private var policies: [JSONValue] = []
        private var suppliers: [JSONValue] = []
        private var unavailable = false
        private var unavailableEvidence: [RuntimeAdapterPendingGuard] = []
        var nativeUnavailable: Bool { lock.lock(); defer { lock.unlock() }; return unavailable }
        var unavailableGuards: [RuntimeAdapterPendingGuard] { lock.lock(); defer { lock.unlock() }; return unavailableEvidence }
        func markNativeUnavailable(term: String, locale: String, selector: String) {
            lock.lock(); defer { lock.unlock() }; unavailable = true
            unavailableEvidence.append(.init(category: "phonetic-unmapped-null-return", inputPath: "fixture.phoneticResolver.mapping/default",
                evidence: "Actual \(selector) consultation has term=\(FixtureJSONWriter.quote(term)), locale=\(FixtureJSONWriter.quote(locale)); no mapping/default exists and native Phonetic is nonoptional"))
        }
        func appendFailure(_ value: TranslationFailure) { lock.lock(); defer { lock.unlock() }; failures.append(value) }
        func appendResolver(_ value: JSONValue) { lock.lock(); defer { lock.unlock() }; resolvers.append(value) }
        func appendSupplier(_ value: JSONValue) { lock.lock(); defer { lock.unlock() }; suppliers.append(value) }
        @discardableResult func appendPolicy(_ value: JSONValue) -> Int {
            lock.lock(); defer { lock.unlock() }; policies.append(value); return policies.count - 1
        }
        func replacePolicy(_ index: Int, _ value: JSONValue) { lock.lock(); defer { lock.unlock() }; policies[index] = value }
        func reset() {
            lock.lock(); defer { lock.unlock() }
            failures.removeAll(keepingCapacity: true); resolvers.removeAll(keepingCapacity: true)
            policies.removeAll(keepingCapacity: true); suppliers.removeAll(keepingCapacity: true); unavailable = false
            unavailableEvidence.removeAll(keepingCapacity: true)
        }
        var snapshot: Snapshot {
            lock.lock(); defer { lock.unlock() }
            return Snapshot(failures: failures, resolvers: resolvers, policies: policies, suppliers: suppliers)
        }
    }
}
