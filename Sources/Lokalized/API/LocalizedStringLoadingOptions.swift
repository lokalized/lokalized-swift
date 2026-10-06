/// Immutable limits for parsing and loading catalogs. Byte limits apply to Data;
/// UTF-16 character limits apply to String input. Model/file/warning budgets span
/// one load. Discovery limits are reserved for native resource enumeration.
public struct LocalizedStringLoadingOptions: Hashable, Sendable {
    /// The default maximum bytes in one Data or stream resource: 8,388,608.
    public static let defaultMaximumInputBytes = 8_388_608
    /// The default maximum UTF-16 code units in one String resource: 8,388,608.
    public static let defaultMaximumReaderCharacters = 8_388_608
    /// The default maximum nested JSON arrays and objects: 64.
    public static let defaultMaximumJsonNestingDepth = 64
    /// The largest configurable JSON nesting depth: 128.
    public static let maximumJsonNestingDepth = 128
    /// The default maximum aggregate input bytes across one load: 33,554,432.
    public static let defaultMaximumTotalInputBytes = 33_554_432
    /// The default maximum catalog resources across one load: 256.
    public static let defaultMaximumLocalizedStringsFiles = 256
    /// The default maximum root entries, alternatives, and generated translation nodes across one load: 100,000.
    public static let defaultMaximumTranslationNodes = 100_000
    /// The default maximum collected warnings across one load: 1,000.
    public static let defaultMaximumWarnings = 1_000
    /// The default maximum entries examined during local resource discovery: 100,000.
    public static let defaultMaximumDiscoveryEntries = 100_000
    /// The largest configurable discovery-entry count: 1,000,000.
    public static let maximumDiscoveryEntries = 1_000_000
    /// The default parsing, loading, and discovery limits.
    public static let defaults = Self()

    /// The maximum bytes in one Data or stream resource. Allowed range: 1 through 2,147,483,646.
    public let maximumInputBytes: Int
    /// The maximum UTF-16 code units in one String resource. Allowed range: 1 through 2,147,483,647.
    public let maximumReaderCharacters: Int
    /// The maximum nested JSON arrays and objects. Allowed range: 1 through 128.
    public let maximumJsonNestingDepth: Int
    /// The maximum aggregate input bytes across one load. Allowed range: 1 through Int.max.
    public let maximumTotalInputBytes: Int
    /// The maximum catalog resources across one load. Allowed range: 1 through 2,147,483,647.
    public let maximumLocalizedStringsFiles: Int
    /// The maximum root entries, alternatives, and generated translation nodes across one load. Allowed range: 0 through 2,147,483,647.
    public let maximumTranslationNodes: Int
    /// The maximum collected warnings across one load. Allowed range: 0 through 2,147,483,647.
    public let maximumWarnings: Int
    /// The maximum entries examined during local resource discovery. Allowed range: 1 through 1,000,000.
    public let maximumDiscoveryEntries: Int

    /// Creates the default parsing, loading, and discovery limits.
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

    /// Creates loading limits with library defaults for omitted arguments.
    /// Invalid values throw `ValidationError` in initializer parameter order; values are not clamped.
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

    /// The first invalid loading option encountered in initializer parameter order.
    public struct ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
        /// The name of the rejected loading-option field.
        public let field: String
        /// The rejected option value.
        public let value: Int
        /// The explanation of the rejected option.
        public let description: String
    }

    private static func validate(_ field: String, _ value: Int, minimum: Int, maximum: Int, reason: String) throws {
        guard (minimum...maximum).contains(value) else {
            throw ValidationError(field: field, value: value, description: reason)
        }
    }
}
