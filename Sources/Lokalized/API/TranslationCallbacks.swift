/// Immutable callback wrapper. Equality and hashing retain callback identity.
public final class TranslationFailureHandler: Hashable, Sendable {
    private let callback: @Sendable (TranslationFailure) throws -> TranslationFailureResponse
    public init(_ callback: @escaping @Sendable (TranslationFailure) throws -> TranslationFailureResponse) { self.callback = callback }
    public func handle(_ failure: TranslationFailure) throws -> TranslationFailureResponse { try callback(failure) }
    public static func returnKey() -> TranslationFailureHandler { TranslationFailureHandler { _ in .returnKey } }
    public static func returnKey(observer: @escaping @Sendable (TranslationFailure) throws -> Void) -> TranslationFailureHandler {
        TranslationFailureHandler { failure in try observer(failure); return .returnKey }
    }
    public static func throwException() -> TranslationFailureHandler { TranslationFailureHandler { _ in .throwException } }
    public static func == (lhs: TranslationFailureHandler, rhs: TranslationFailureHandler) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Decides whether a failed locale attempt advances to the next candidate.
public final class TranslationFallbackPolicy: Hashable, Sendable {
    private let callback: @Sendable (TranslationFailureReason, LocaleTag, (any Error)?) throws -> Bool
    public init(_ callback: @escaping @Sendable (TranslationFailureReason, LocaleTag, (any Error)?) throws -> Bool) { self.callback = callback }
    public func shouldTryNextLocale(reason: TranslationFailureReason, attemptedLocale: LocaleTag, cause: (any Error)?) throws -> Bool {
        try callback(reason, attemptedLocale, cause)
    }
    public static func fallbackOnMissingTranslationOrNoMatchingAlternative() -> TranslationFallbackPolicy { missingOrNoMatch }
    public static func fallbackOnAnyFailure() -> TranslationFallbackPolicy { anyFailure }
    public static func neverFallback() -> TranslationFallbackPolicy { never }
    private static let missingOrNoMatch = TranslationFallbackPolicy { reason, _, _ in reason != .resolutionFailure }
    private static let anyFailure = TranslationFallbackPolicy { _, _, _ in true }
    private static let never = TranslationFallbackPolicy { _, _, _ in false }
    public static func == (lhs: TranslationFallbackPolicy, rhs: TranslationFallbackPolicy) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Runs once before a translation from a later locale candidate is returned.
/// Thrown errors propagate directly; observation never resumes locale fallback.
public final class TranslationFallbackObserver: Hashable, Sendable {
    private let callback: @Sendable (TranslationFallbackEvent) throws -> Void
    public init(_ callback: @escaping @Sendable (TranslationFallbackEvent) throws -> Void) { self.callback = callback }
    public func observe(_ event: TranslationFallbackEvent) throws { try callback(event) }
    public static func == (lhs: TranslationFallbackObserver, rhs: TranslationFallbackObserver) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
