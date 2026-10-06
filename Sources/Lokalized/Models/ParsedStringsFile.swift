/// One validated catalog, or a merge of same-locale shards. Origins and warning
/// order are retained independently from definition equality.
public struct ParsedStringsFile: Sendable {
    /// The normalized catalog locale tag.
    public let locale: String
    /// The source labels of the catalog or merged shards, in input order.
    public let sources: [String]
    /// The validated localized entries in declaration order.
    public let strings: [LocalizedString]
    /// The source labels contributing each exact key, including equal definitions merged from shards.
    public let originsByKey: [ExactString: [String]]
    /// The collected construction warnings in delivery order.
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
