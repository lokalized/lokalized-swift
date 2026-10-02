/// One validated catalog, or a merge of same-locale shards. Origins and warning
/// order are retained independently from definition equality.
public struct ParsedStringsFile: Sendable {
    public let locale: String
    public let sources: [String]
    public let strings: [LocalizedString]
    public let originsByKey: [ExactString: [String]]
    public let warnings: [LocalizedStringWarning]

    package init(locale: String, sources: [String], strings: [LocalizedString],
                 originsByKey: [ExactString: [String]], warnings: [LocalizedStringWarning]) {
        self.locale = locale
        self.sources = sources
        self.strings = strings
        self.originsByKey = originsByKey
        self.warnings = warnings
    }
}
