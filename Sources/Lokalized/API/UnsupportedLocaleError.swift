/// A classifier was asked to evaluate a locale without pinned plural rules.
public struct UnsupportedLocaleError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The locale tag that could not be evaluated.
    public let locale: String
    /// The diagnostic explanation of the locale failure.
    public var message: String { "Unsupported locale '\(locale)' was provided" }
    /// The diagnostic message.
    public var description: String { message }

    /// Creates an error identifying the locale without supported plural rules.
    public init(locale: String) { self.locale = locale }
}
