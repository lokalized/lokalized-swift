/// Immutable limits for parsing and loading catalogs. Byte limits apply to Data;
/// UTF-16 character limits apply to String input. Model/file/warning budgets span
/// one load. Discovery limits are reserved for native resource enumeration.
public struct LocalizedStringLoadingOptions: Hashable, Sendable {
    public static let defaultMaximumInputBytes = 8_388_608
    public static let defaultMaximumReaderCharacters = 8_388_608
    public static let defaultMaximumJsonNestingDepth = 64
    public static let maximumJsonNestingDepth = 128
    public static let defaultMaximumTotalInputBytes = 33_554_432
    public static let defaultMaximumLocalizedStringsFiles = 256
    public static let defaultMaximumTranslationNodes = 100_000
    public static let defaultMaximumWarnings = 1_000
    public static let defaultMaximumDiscoveryEntries = 100_000
    public static let maximumDiscoveryEntries = 1_000_000
    public static let defaults = Self()

    public let maximumInputBytes: Int
    public let maximumReaderCharacters: Int
    public let maximumJsonNestingDepth: Int
    public let maximumTotalInputBytes: Int
    public let maximumLocalizedStringsFiles: Int
    public let maximumTranslationNodes: Int
    public let maximumWarnings: Int
    public let maximumDiscoveryEntries: Int

    public init() {
        maximumInputBytes = Self.defaultMaximumInputBytes
        maximumReaderCharacters = Self.defaultMaximumReaderCharacters
        maximumJsonNestingDepth = Self.defaultMaximumJsonNestingDepth
        maximumTotalInputBytes = Self.defaultMaximumTotalInputBytes
        maximumLocalizedStringsFiles = Self.defaultMaximumLocalizedStringsFiles
        maximumTranslationNodes = Self.defaultMaximumTranslationNodes
        maximumWarnings = Self.defaultMaximumWarnings
        maximumDiscoveryEntries = Self.defaultMaximumDiscoveryEntries
    }

    public init(
        maximumInputBytes: Int = Self.defaultMaximumInputBytes,
        maximumReaderCharacters: Int = Self.defaultMaximumReaderCharacters,
        maximumJsonNestingDepth: Int = Self.defaultMaximumJsonNestingDepth,
        maximumTotalInputBytes: Int = Self.defaultMaximumTotalInputBytes,
        maximumLocalizedStringsFiles: Int = Self.defaultMaximumLocalizedStringsFiles,
        maximumTranslationNodes: Int = Self.defaultMaximumTranslationNodes,
        maximumWarnings: Int = Self.defaultMaximumWarnings,
        maximumDiscoveryEntries: Int = Self.defaultMaximumDiscoveryEntries
    ) throws {
        try Self.validate("maximumInputBytes", maximumInputBytes, minimum: 1, maximum: 2_147_483_646,
                          reason: "maximumInputBytes must be between 1 and Integer.MAX_VALUE - 1")
        try Self.validate("maximumReaderCharacters", maximumReaderCharacters, minimum: 1, maximum: 2_147_483_647,
                          reason: "maximumReaderCharacters must be positive")
        try Self.validate("maximumJsonNestingDepth", maximumJsonNestingDepth, minimum: 1, maximum: Self.maximumJsonNestingDepth,
                          reason: "maximumJsonNestingDepth must be between 1 and 128")
        try Self.validate("maximumTotalInputBytes", maximumTotalInputBytes, minimum: 1, maximum: Int.max,
                          reason: "maximumTotalInputBytes must be positive")
        try Self.validate("maximumLocalizedStringsFiles", maximumLocalizedStringsFiles, minimum: 1, maximum: 2_147_483_647,
                          reason: "maximumLocalizedStringsFiles must be positive")
        try Self.validate("maximumTranslationNodes", maximumTranslationNodes, minimum: 0, maximum: 2_147_483_647,
                          reason: "maximumTranslationNodes must be nonnegative")
        try Self.validate("maximumWarnings", maximumWarnings, minimum: 0, maximum: 2_147_483_647,
                          reason: "maximumWarnings must be nonnegative")
        try Self.validate("maximumDiscoveryEntries", maximumDiscoveryEntries, minimum: 1, maximum: Self.maximumDiscoveryEntries,
                          reason: "maximumDiscoveryEntries must be between 1 and 1000000")
        self.maximumInputBytes = maximumInputBytes
        self.maximumReaderCharacters = maximumReaderCharacters
        self.maximumJsonNestingDepth = maximumJsonNestingDepth
        self.maximumTotalInputBytes = maximumTotalInputBytes
        self.maximumLocalizedStringsFiles = maximumLocalizedStringsFiles
        self.maximumTranslationNodes = maximumTranslationNodes
        self.maximumWarnings = maximumWarnings
        self.maximumDiscoveryEntries = maximumDiscoveryEntries
    }

    public struct ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
        public let field: String
        public let value: Int
        public let description: String
    }

    private static func validate(_ field: String, _ value: Int, minimum: Int, maximum: Int, reason: String) throws {
        guard (minimum...maximum).contains(value) else {
            throw ValidationError(field: field, value: value, description: reason)
        }
    }
}
