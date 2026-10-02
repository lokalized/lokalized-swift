public extension LocalizedStringLoader {
    /// Projects the complete validated manifest. Explicit tiebreakers are kept;
    /// private singleton-language orders do not become authored configuration.
    static func localeConfigurationForManifest(_ manifest: StringsManifestV1,
        loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> ManifestLocaleConfiguration {
        let validated = try validateStringsManifest(manifest, loadingOptions: loadingOptions)
        return manifestConfiguration(validated)
    }
    /// The complete candidate walk, including candidates with no declared file.
    static func chain(_ manifest: StringsManifestV1, lookupLocale: String,
        loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> [String] {
        let validated = try validateStringsManifest(manifest, loadingOptions: loadingOptions)
        let lookup = try ManifestLocale.normalizeTag(lookupLocale)
        let config = manifestConfiguration(validated)
        return try ManifestCandidateResolver(supported: config.supportedLocales, fallback: config.fallbackLocale,
            tiebreakers: config.tiebreakerLocalesByLanguageCode).chain(lookup)
    }
    /// Manifest-backed files in first-use locale order. Shared URLs are retained
    /// for distinct locales. Every entry already carries its resolved URL.
    static func fetchSet(_ manifest: StringsManifestV1, lookupLocale: String,
        loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> [FetchEntry] {
        let validated = try validateStringsManifest(manifest, loadingOptions: loadingOptions)
        _ = try ManifestURL.resolve(validated.baseUrl)
        return try chain(validated, lookupLocale: lookupLocale, loadingOptions: loadingOptions).compactMap { tag in
            guard let file = validated.files[ExactString(tag)] else { return nil }
            return try manifestFetchEntry(tag, file: file, base: validated.baseUrl)
        }
    }
    /// Internal complete-catalog projection; performs no catalog I/O.
    package static func wholeManifestPlan(_ manifest: StringsManifestV1,
        loadingOptions: LocalizedStringLoadingOptions = .defaults) throws -> [FetchEntry] {
        let validated = try validateStringsManifest(manifest, loadingOptions: loadingOptions)
        return try validated.files.keys.sorted().map { key in
            try manifestFetchEntry(key.string, file: validated.files[key]!, base: validated.baseUrl)
        }
    }
}

private func manifestConfiguration(_ manifest: StringsManifestV1) -> ManifestLocaleConfiguration {
    .init(fallbackLocale: manifest.fallbackLocale, supportedLocales: manifest.files.keys.sorted().map(\.string),
        tiebreakerLocalesByLanguageCode: Dictionary(manifest.tiebreakerLocalesByLanguageCode.map { ($0.key.string, $0.value) }, uniquingKeysWith: { _, last in last }))
}
private func manifestFetchEntry(_ locale: String, file: StringsManifestFile, base: String) throws -> FetchEntry {
    .init(locale: locale, url: try ManifestURL.resolve(file.url, relativeTo: base), sha256: file.sha256,
        expectedDecodedBytes: file.decodedBytes)
}
