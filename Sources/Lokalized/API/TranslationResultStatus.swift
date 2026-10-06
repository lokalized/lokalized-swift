/// Whether a lookup produced a translation or the final failure handler's text.
public enum TranslationResultStatus: String, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    /// The text was rendered from a catalog entry.
    case translated
    /// The final failure handler returned the requested key.
    case returnedKey = "returned-key"
    /// The final failure handler returned replacement text.
    case returnedString = "returned-string"
    /// The uppercase diagnostic name of the result status.
    public var displayName: String {
        switch self { case .translated: "TRANSLATED"; case .returnedKey: "RETURNED_KEY"; case .returnedString: "RETURNED_STRING" }
    }
    /// The uppercase diagnostic name of the result status.
    public var description: String { displayName }
}
