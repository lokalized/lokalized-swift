/// Immutable synchronous localization runtime backed by caller-supplied catalogs.
/// Catalogs are validated and compiled once; all lookup state is per invocation.
public final class DefaultStrings: Strings, Sendable {
    public let configuration: StringsConfiguration
    public var fallbackLocale: String { matcher.fallbackLocale }
    public var fallbackLocaleTag: LocaleTag { matcher.fallbackTag }
    public var supportedLocales: Set<LocaleTag> { Set(matcher.supportedTags) }
    public var tiebreakerLocalesByLanguageCode: [String: [LocaleTag]] { matcher.tiebreakerLocaleTagsByLanguageCode }
    public let runtimeLimits: TranslationRuntimeLimits
    public let bidiIsolation: BidiIsolation
    public let translationFailureHandler: TranslationFailureHandler
    public let translationFallbackPolicy: TranslationFallbackPolicy
    public let translationFallbackObserver: TranslationFallbackObserver?
    public let languageRangeEquivalents: LanguageRangeEquivalents
    private let matcher: DefaultLocaleMatcher
    private let catalogs: [LocaleTag: CompiledCatalogResolution]
    private let keysByLocale: [LocaleTag: Set<ExactString>]

    /// Validates configuration, invokes the catalog supplier once, and compiles
    /// translations. Share the resulting immutable instance across callers;
    /// captured application state in suppliers and callbacks must be thread-safe.
    ///
    /// - Throws: Configuration or catalog errors, or an error from the supplier.
    public init(configuration: StringsConfiguration) throws {
        // Construction order is observable when a supplier or catalog is invalid.
        do { try JDKLocaleTag.requireWellFormed(configuration.fallbackLocale, description: "Fallback locale") }
        catch { throw Self.configurationError(error) }
        guard let supplier = configuration.localizedStringSupplier else {
            throw ConfigurationError(kind: .invalidArgument,
                message: "You must specify a 'localizedStringSupplier' when creating a DefaultStrings instance")
        }
        guard (configuration.localeSupplier == nil) != (configuration.localeMatchSupplier == nil) else {
            throw ConfigurationError(kind: .invalidArgument,
                message: "You must specify exactly one of 'localeSupplier' or 'localeMatchSupplier' when creating a DefaultStrings instance")
        }
        let supplied = try supplier()
        // Swift dictionaries have no authored order. Locale ordering is stable;
        // LocalizedCatalog preserves authored root order without hashing graphs.
        let locales = supplied.keys.sorted {
            $0.tag == $1.tag ? $0.javaIdentifier < $1.javaIdentifier : $0.tag < $1.tag
        }
        var seen: [String: LocaleTag] = [:]
        do {
            for locale in locales {
                try JDKLocaleTag.requireWellFormed(locale, description: "Localized strings locale")
                if let prior = seen.updateValue(locale, forKey: locale.tag.lowercased()) {
                    throw ConfigurationError(kind: .invalidArgument,
                        message: "Localized strings locales '\(prior.javaIdentifier)' and '\(locale.javaIdentifier)' both use IETF BCP 47 language tag '\(locale.tag)'")
                }
                let catalog = supplied[locale]!
                for (index, model) in catalog.orderedStrings.enumerated() {
                    if let labels = catalog.suppliedKeys, labels[index] != model.key {
                        throw ConfigurationError(kind: .invalidArgument,
                            message: "Catalog entry key '\(labels[index])' does not match localized string key '\(model.key)' for locale '\(locale.tag)'")
                    }
                    var validator = RuntimeCatalogValidator(locale: locale, rootKey: model.key)
                    try validator.validate(model)
                }
            }
        } catch { throw Self.configurationError(error) }
        let matcher: DefaultLocaleMatcher
        do {
            matcher = try DefaultLocaleMatcher(supportedLocales: locales, fallbackLocale: configuration.fallbackLocale,
                tiebreakerLocalesByLanguageCode: configuration.tiebreakerLocalesByLanguageCode ?? [:],
                languageRangeEquivalents: configuration.languageRangeEquivalents ?? .ianaRegistry)
        } catch { throw Self.configurationError(error) }
        let limits = configuration.runtimeLimits ?? .defaults
        var compiled: [LocaleTag: CompiledCatalogResolution] = [:]
        var keys: [LocaleTag: Set<ExactString>] = [:]
        do {
            for locale in locales {
                let roots = supplied[locale]!.orderedStrings
                let parsed = ParsedStringsFile(locale: locale.tag, sources: [], strings: roots,
                    originsByKey: [:], warnings: [])
                compiled[locale] = try CompiledCatalogResolution(parsed, locale: locale, runtimeLimits: limits,
                    phoneticResolver: configuration.phoneticResolver ?? PhoneticResolvers.failFast)
                keys[locale] = Set(roots.map(\.key))
            }
        } catch { throw Self.configurationError(error) }
        self.configuration = configuration
        self.matcher = matcher; catalogs = compiled; keysByLocale = keys
        runtimeLimits = limits; bidiIsolation = configuration.bidiIsolation ?? .rtlLocales
        translationFailureHandler = configuration.translationFailureHandler ?? .returnKey()
        translationFallbackPolicy = configuration.translationFallbackPolicy ?? .fallbackOnMissingTranslationOrNoMatchingAlternative()
        translationFallbackObserver = configuration.translationFallbackObserver
        languageRangeEquivalents = matcher.languageRangeEquivalents
    }

    /// Negotiates one requested tag and returns its selection diagnostics.
    public func matchFor(_ locale: String) throws -> LocaleMatchResult { try matcher.matchFor(locale) }
    /// Negotiates weighted language ranges against the loaded catalog locales.
    public func matchFor(_ languageRanges: [LanguageRange]) throws -> LocaleMatchResult { try matcher.matchFor(languageRanges) }
    /// Parses language ranges using this instance's configured equivalence data.
    public func parseLanguageRanges(_ ranges: String) throws -> [LanguageRange] { try matcher.parseLanguageRanges(ranges) }

    /// Returns exact keys in a loaded locale without performing locale negotiation.
    public func getKeysForLocale(_ locale: LocaleTag) throws -> Set<ExactString> {
        try JDKLocaleTag.requireWellFormed(locale, description: "Locale")
        guard let keys = keysByLocale[locale] else { throw Self.unsupported(locale) }
        return keys
    }
    /// Returns source keys absent from the target catalog; both locales must be loaded.
    public func getMissingKeys(sourceLocale: LocaleTag, targetLocale: LocaleTag) throws -> Set<ExactString> {
        try JDKLocaleTag.requireWellFormed(sourceLocale, description: "Source locale")
        try JDKLocaleTag.requireWellFormed(targetLocale, description: "Target locale")
        guard let source = keysByLocale[sourceLocale] else {
            throw TranslationEvaluationError(kind: .invalidArgument, message: "Source locale '\(sourceLocale.tag)' is not supported")
        }
        guard let target = keysByLocale[targetLocale] else {
            throw TranslationEvaluationError(kind: .invalidArgument, message: "Target locale '\(targetLocale.tag)' is not supported")
        }
        return source.subtracting(target)
    }

    /// Resolves an exact key using typed values and optional per-call overrides.
    ///
    /// - Parameters:
    ///   - key: Localized string identifier, preserving exact UTF-16 identity.
    ///   - placeholders: Values for expression evaluation and interpolation.
    ///   - options: Locale, bidi, and callback overrides; omitted settings inherit this instance.
    /// - Returns: Text and diagnostic outcome, including attempted and resolved locales.
    /// - Throws: Unhandled evaluation errors or errors from application callbacks.
    public func getResult(_ key: ExactString, placeholders: PlaceholderValues, options: TranslationOptions) throws -> TranslationResult {
        let (lookupLocale, match) = try localeLookup(options)
        let isolation = options.bidiIsolation ?? bidiIsolation
        let handler = options.translationFailureHandler ?? translationFailureHandler
        let policy = options.translationFallbackPolicy ?? translationFallbackPolicy
        let observer = options.translationFallbackObserver ?? translationFallbackObserver
        let values = placeholders.dictionary
        let candidates = candidateChain(lookupLocale)
        var attempted: [LocaleTag] = []
        var firstCause: (any Error)?
        var sawNoMatchingAlternative = false
        // Raw attempt snapshots defer public event validation until success.
        // Enabling an observer must not alter an unsuccessful candidate walk.
        var preceding: [(LocaleTag, TranslationFailureReason, (any Error)?)] = []
        for (index, candidate) in candidates.enumerated() {
            attempted.append(candidate)
            var reason = TranslationFailureReason.missingTranslation
            var attemptCause: (any Error)?
            var success: TranslationResult?
            if let catalog = catalogs[candidate] {
                do {
                    switch try catalog.resolve(key, placeholders: values, callerValueRendererFactory: {
                        let renderer = BidiRenderer(locale: candidate, isolation: isolation, limits: self.runtimeLimits)
                        return { name, value, remaining in
                            try renderer.render(name: name, value: value, remaining: remaining)
                        }
                    }) {
                    case .missingTranslation: break
                    case .noMatchingAlternative:
                        reason = .noMatchingAlternative; sawNoMatchingAlternative = true
                    case .translation(let text, _):
                        // The frozen reference treats result validation as an
                        // attempt failure. Observer callbacks remain outside it.
                        success = try TranslationResult(key: key, translation: text, lookupLocale: lookupLocale,
                            localeMatchResult: match, resolvedLocale: candidate, attemptedLocales: attempted,
                            status: .translated)
                    }
                } catch {
                    reason = .resolutionFailure; attemptCause = error
                    if firstCause == nil { firstCause = error }
                }
            }
            if let success {
                if let observer, !preceding.isEmpty {
                    let failures = try preceding.map {
                        try TranslationFallbackEvent.PrecedingFailure(locale: $0.0, reason: $0.1, cause: $0.2)
                    }
                    try observer.observe(TranslationFallbackEvent(translationResult: success, precedingFailures: failures))
                }
                return success
            }
            if observer != nil { preceding.append((candidate, reason, attemptCause)) }
            if index + 1 == candidates.count { break }
            if try !policy.shouldTryNextLocale(reason: reason, attemptedLocale: candidate, cause: attemptCause) { break }
        }
        let reason: TranslationFailureReason = firstCause != nil ? .resolutionFailure
            : sawNoMatchingAlternative ? .noMatchingAlternative : .missingTranslation
        let failure = TranslationFailure(key: key, lookupLocale: lookupLocale, localeMatchResult: match,
            attemptedLocales: attempted, placeholders: placeholders, reason: reason, cause: firstCause)
        let response = try handler.handle(failure)
        let text: String
        let status: TranslationResultStatus
        switch response {
        case .returnKey:
            text = BidiRenderer.failureKey(key, values: values, locale: lookupLocale, isolation: isolation, limits: runtimeLimits)
            status = .returnedKey
        case .returnString(let value): text = value; status = .returnedString
        case .throwException:
            if let firstCause { throw firstCause }
            throw try MissingTranslationError(message: "No match for '\(key)' was found for locale '\(lookupLocale.tag)'.",
                key: key, placeholders: placeholders, lookupLocale: lookupLocale, localeMatchResult: match,
                reason: reason, attemptedLocales: attempted)
        }
        return try TranslationResult(key: key, translation: text, lookupLocale: lookupLocale,
            localeMatchResult: match, resolvedLocale: nil, attemptedLocales: attempted, status: status,
            failureReason: reason, cause: firstCause)
    }

    private func localeLookup(_ options: TranslationOptions) throws -> (LocaleTag, LocaleMatchResult) {
        if let locale = options.locale { return (locale, try matchFor(locale)) }
        if let ranges = options.languageRanges {
            let match = try matchFor(ranges)
            return (match.selectedTag ?? matcher.fallbackTag, match)
        }
        if let match = options.localeMatchResult {
            try validateSuppliedMatch(match, source: "localeMatchResult")
            return (match.selectedTag ?? match.fallbackTag, match)
        }
        if let supplier = configuration.localeMatchSupplier {
            let match = try supplier(self)
            try validateSuppliedMatch(match, source: "localeMatchSupplier")
            return (match.selectedTag ?? match.fallbackTag, match)
        }
        let locale = try configuration.localeSupplier!(self)
        try JDKLocaleTag.requireWellFormed(locale, description: "localeSupplier result")
        return (locale, try matchFor(locale))
    }
    private func validateSuppliedMatch(_ result: LocaleMatchResult, source: String) throws {
        guard result.fallbackTag == matcher.fallbackTag else {
            throw LocaleMatcherError("\(source) returned a result for a different fallback locale")
        }
        guard Set(result.consideredTags) == Set(matcher.supportedTags) else {
            throw LocaleMatcherError("\(source) returned a result for different supported locales")
        }
    }
    private func candidateChain(_ locale: LocaleTag) -> [LocaleTag] {
        var proposed: [LocaleTag] = [], proposedSet = Set<LocaleTag>()
        func add(_ value: LocaleTag) { if proposedSet.insert(value).inserted { proposed.append(value) } }
        for parent in matcher.fallbackLocalesFor(locale.tag) { add(parent) }
        if let likely = matcher.likelyMatch(locale.tag, candidates: matcher.supportedLocales),
           let loaded = matcher.supportedTags.first(where: { $0.tag == likely }) { add(loaded) }
        let primary = MatchingLocale.primary(locale.tag)
        if !primary.isEmpty {
            let requestedScript = matcher.likelyLanguageScriptFor(locale.tag)
            for tie in matcher.tiebreakerLocaleTagsByLanguageCode[primary] ?? [] {
                if MatchingLocale.compatible(requestedScript, matcher.likelyLanguageScriptFor(tie.tag)) { add(tie) }
            }
        }
        add(matcher.fallbackTag)
        var result: [LocaleTag] = [], seen = Set<LocaleTag>()
        for value in proposed {
            let attempted: LocaleTag
            if catalogs[value] != nil { attempted = value }
            else {
                let equivalents = matcher.supportedTags.filter { MatchingLocale.equivalent($0.tag, value.tag) }
                if let preferred = matcher.preferred(value.tag, candidates: equivalents.map(\.tag)),
                   let loaded = equivalents.first(where: { $0.tag == preferred }) { attempted = loaded }
                else { attempted = value }
            }
            if seen.insert(attempted).inserted { result.append(attempted) }
        }
        return result
    }
    private static func unsupported(_ locale: LocaleTag) -> TranslationEvaluationError {
        .init(kind: .invalidArgument, message: "Locale '\(locale.tag)' is not supported")
    }
    private static func configurationError(_ error: any Error) -> any Error {
        if error is ConfigurationError { return error }
        if let error = error as? TranslationEvaluationError {
            if error.kind == .expression { return error }
            return ConfigurationError(kind: error.kind == .invalidState ? .invalidState : .invalidArgument,
                message: error.message, cause: error.cause)
        }
        if let error = error as? LocaleMatcherError {
            return ConfigurationError(kind: .invalidArgument, message: error.message)
        }
        if let error = error as? LocaleTagError {
            return ConfigurationError(kind: .invalidArgument, message: error.description)
        }
        return error
    }
}
