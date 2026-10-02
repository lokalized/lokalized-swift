/// The original lookup inputs and error passed to a nonthrowing display policy.
/// A class error retains its identity; caller values are a value-semantic snapshot.
public struct TranslationDisplayFailure: Sendable {
    public let key: ExactString
    public let placeholders: PlaceholderValues
    public let options: TranslationOptions
    public let error: any Error
}

/// An explicit decision about how a UI displays an error from `Strings.get`.
/// A throwing failure handler is still invoked by the underlying runtime; its
/// error is then delivered to this policy rather than silently discarded.
public enum TranslationErrorDisplayPolicy: Sendable {
    /// Display the original key verbatim, without interpolation or bidi changes.
    case returnKey
    /// Display the supplied text verbatim.
    case returnString(String)
    /// Let the application inspect the original error and choose display text.
    case custom(@Sendable (TranslationDisplayFailure) -> String)

    fileprivate func display(_ failure: TranslationDisplayFailure) -> String {
        switch self {
        case .returnKey: failure.key.string
        case .returnString(let value): value
        case .custom(let display): display(failure)
        }
    }
}

/// A portable synchronous adapter for rendering in a nonthrowing UI callback.
/// No UIKit, SwiftUI or host locale negotiation is required.
public struct StringsDisplayAdapter: Sendable {
    public let strings: any Strings
    public let errorDisplayPolicy: TranslationErrorDisplayPolicy

    public init(_ strings: any Strings, errorDisplayPolicy: TranslationErrorDisplayPolicy) {
        self.strings = strings
        self.errorDisplayPolicy = errorDisplayPolicy
    }

    public func get(_ key: ExactString, placeholders: PlaceholderValues = [:],
                    options: TranslationOptions = TranslationOptions()) -> String {
        do {
            return try strings.get(key, placeholders: placeholders, options: options)
        } catch {
            return errorDisplayPolicy.display(.init(key: key, placeholders: placeholders,
                                                    options: options, error: error))
        }
    }
}
