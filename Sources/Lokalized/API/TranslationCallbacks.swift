/// Immutable callback wrapper. Equality and hashing retain callback identity.
public final class TranslationFailureHandler: Hashable, Sendable {
    private let callback: @Sendable (TranslationFailure) throws -> TranslationFailureResponse
    /// Creates a final failure callback. It runs once after locale candidates are exhausted or the fallback policy stops lookup.
    /// Captured state must support concurrent, reentrant calls; callback errors propagate to the caller.
    public init(_ callback: @escaping @Sendable (TranslationFailure) throws -> TranslationFailureResponse) { self.callback = callback }
    /// Invokes this handler with the final failed-lookup snapshot. Errors thrown by the callback propagate unchanged.
    public func handle(_ failure: TranslationFailure) throws -> TranslationFailureResponse { try callback(failure) }
    /// Creates the default handler, which returns the requested key using bounded key interpolation and bidi handling.
    public static func returnKey() -> TranslationFailureHandler { TranslationFailureHandler { _ in .returnKey } }
    /// Creates a key-returning handler that first observes the final failure. An observer error propagates instead of returning the key.
    public static func returnKey(observer: @escaping @Sendable (TranslationFailure) throws -> Void) -> TranslationFailureHandler {
        TranslationFailureHandler { failure in try observer(failure); return .returnKey }
    }
    /// Creates a handler that throws the retained resolution cause, or `MissingTranslationError` when no cause exists.
    public static func throwException() -> TranslationFailureHandler { TranslationFailureHandler { _ in .throwException } }
    /// Compares callback-wrapper identity. Separately constructed wrappers are distinct even when their callbacks behave alike.
    public static func == (lhs: TranslationFailureHandler, rhs: TranslationFailureHandler) -> Bool { lhs === rhs }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Decides whether a failed locale attempt advances to the next candidate.
public final class TranslationFallbackPolicy: Hashable, Sendable {
    private let callback: @Sendable (TranslationFailureReason, LocaleTag, (any Error)?) throws -> Bool
    /// Creates a policy called after a failed locale attempt when another candidate remains.
    /// Return `true` to continue. Callback errors propagate and captured state must support concurrent, reentrant calls.
    public init(_ callback: @escaping @Sendable (TranslationFailureReason, LocaleTag, (any Error)?) throws -> Bool) { self.callback = callback }
    /// Invokes the continuation policy for a failed locale candidate. Returns `true` to try the next candidate; callback errors propagate.
    public func shouldTryNextLocale(reason: TranslationFailureReason, attemptedLocale: LocaleTag, cause: (any Error)?) throws -> Bool {
        try callback(reason, attemptedLocale, cause)
    }
    /// Creates the default policy, which continues for missing entries or unmatched alternatives and stops on resolution errors.
    public static func fallbackOnMissingTranslationOrNoMatchingAlternative() -> TranslationFallbackPolicy { missingOrNoMatch }
    /// Creates a policy that continues after every failed locale candidate, including resolution errors.
    public static func fallbackOnAnyFailure() -> TranslationFallbackPolicy { anyFailure }
    /// Creates a policy that stops after the first failed locale candidate.
    public static func neverFallback() -> TranslationFallbackPolicy { never }
    private static let missingOrNoMatch = TranslationFallbackPolicy { reason, _, _ in reason != .resolutionFailure }
    private static let anyFailure = TranslationFallbackPolicy { _, _, _ in true }
    private static let never = TranslationFallbackPolicy { _, _, _ in false }
    /// Compares callback-wrapper identity. Separately constructed wrappers are distinct even when their callbacks behave alike.
    public static func == (lhs: TranslationFallbackPolicy, rhs: TranslationFallbackPolicy) -> Bool { lhs === rhs }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// Runs once before a translation from a later locale candidate is returned.
/// Thrown errors propagate directly; observation never resumes locale fallback.
public final class TranslationFallbackObserver: Hashable, Sendable {
    private let callback: @Sendable (TranslationFallbackEvent) throws -> Void
    /// Creates an observer called once before a successful translation from a later candidate is returned.
    /// Callback errors propagate; captured state must support concurrent, reentrant calls.
    public init(_ callback: @escaping @Sendable (TranslationFallbackEvent) throws -> Void) { self.callback = callback }
    /// Invokes this observer with the successful fallback event. Errors thrown by the callback propagate unchanged.
    public func observe(_ event: TranslationFallbackEvent) throws { try callback(event) }
    /// Compares callback-wrapper identity. Separately constructed wrappers are distinct even when their callbacks behave alike.
    public static func == (lhs: TranslationFallbackObserver, rhs: TranslationFallbackObserver) -> Bool { lhs === rhs }
    /// Hashes the values used by equality. Hash values are process-specific and must not be used as persistent catalog identifiers.
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
