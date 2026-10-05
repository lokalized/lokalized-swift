/// Whether a lookup produced a translation or the final failure handler's text.
public enum TranslationResultStatus: String, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    case translated
    case returnedKey = "returned-key"
    case returnedString = "returned-string"
    public var displayName: String {
        switch self { case .translated: "TRANSLATED"; case .returnedKey: "RETURNED_KEY"; case .returnedString: "RETURNED_STRING" }
    }
    public var description: String { displayName }
}
