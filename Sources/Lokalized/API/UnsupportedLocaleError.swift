/// A classifier was asked to evaluate a locale without pinned plural rules.
public struct UnsupportedLocaleError: Error, Hashable, Sendable, CustomStringConvertible {
    public let locale: String
    public var message: String { "Unsupported locale '\(locale)' was provided" }
    public var description: String { message }

    public init(locale: String) { self.locale = locale }
}
