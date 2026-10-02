/// An immutable localized entry, or one whole-message alternative of an entry.
///
/// An alternative's `key` is its expression text. Alternatives retain order.
/// Construction requires a translation or at least one alternative; catalog
/// validation separately checks templates, expressions, generated placeholders,
/// and alternative depth. Swift value semantics prevent identity cycles.
public struct LocalizedString: Hashable, Sendable {
    // Immutable storage keeps public value semantics while making shared
    // subtrees identifiable for worklist memoization. Sendable is checked.
    private final class Storage: Sendable {
        let key: ExactString
        let translation: String?
        let commentary: String?
        let placeholderDefinitions: [ExactString: PlaceholderDefinition]
        let placeholderDefinitionOrder: [ExactString]
        let alternatives: [LocalizedString]

        init(key: ExactString, translation: String?, commentary: String?,
             placeholderDefinitions: [ExactString: PlaceholderDefinition], placeholderDefinitionOrder: [ExactString],
             alternatives: [LocalizedString]) {
            self.key = key
            self.translation = translation
            self.commentary = commentary
            self.placeholderDefinitions = placeholderDefinitions
            self.placeholderDefinitionOrder = placeholderDefinitionOrder
            self.alternatives = alternatives
        }
    }

    private let storage: Storage

    /// Identity for internal graph-validation memoization; public equality is by value.
    package var storageIdentity: ObjectIdentifier { ObjectIdentifier(storage) }
    /// Authored parse order, or exact UTF-16 order for native map construction.
    /// This provenance affects diagnostics, not definition equality or hashing.
    package var placeholderDefinitionOrder: [ExactString] { storage.placeholderDefinitionOrder }

    public var key: ExactString { storage.key }
    public var translation: String? { storage.translation }
    public var commentary: String? { storage.commentary }
    public var placeholderDefinitions: [ExactString: PlaceholderDefinition] { storage.placeholderDefinitions }
    public var alternatives: [LocalizedString] { storage.alternatives }

    public init(
        key: ExactString,
        translation: String? = nil,
        commentary: String? = nil,
        placeholderDefinitions: [ExactString: PlaceholderDefinition] = [:],
        alternatives: [LocalizedString] = []
    ) throws {
        try self.init(key: key, translation: translation, commentary: commentary,
                      placeholderDefinitions: placeholderDefinitions,
                      placeholderDefinitionOrder: placeholderDefinitions.keys.sorted(), alternatives: alternatives)
    }

    package init(key: ExactString, translation: String? = nil, commentary: String? = nil,
                 placeholderDefinitions: [ExactString: PlaceholderDefinition],
                 placeholderDefinitionOrder: [ExactString], alternatives: [LocalizedString] = []) throws {
        precondition(placeholderDefinitionOrder.count == placeholderDefinitions.count
                     && Set(placeholderDefinitionOrder) == Set(placeholderDefinitions.keys),
                     "Internal placeholder order must identify every definition once")
        guard translation != nil || !alternatives.isEmpty else {
            throw CatalogModelError(reason: .missingTranslationOrAlternative(key: key))
        }
        storage = Storage(key: key, translation: translation, commentary: commentary,
                          placeholderDefinitions: placeholderDefinitions, placeholderDefinitionOrder: placeholderDefinitionOrder,
                          alternatives: alternatives)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Constructor-created values can exceed the catalog depth ceiling.
        // A worklist keeps equality safe before catalog validation occurs.
        var pending = [(lhs.storage, rhs.storage)]
        var compared: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
        while let (left, right) = pending.popLast() {
            if left === right { continue }
            let leftID = ObjectIdentifier(left)
            let rightID = ObjectIdentifier(right)
            if compared[leftID, default: []].contains(rightID) { continue }
            compared[leftID, default: []].insert(rightID)
            guard left.key == right.key,
                  CatalogExactText.equalsOptional(left.translation, right.translation),
                  CatalogExactText.equalsOptional(left.commentary, right.commentary),
                  left.placeholderDefinitions == right.placeholderDefinitions,
                  left.alternatives.count == right.alternatives.count else { return false }
            for index in left.alternatives.indices.reversed() {
                pending.append((left.alternatives[index].storage, right.alternatives[index].storage))
            }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        // Postorder memoization avoids recursive hashing and exponential work
        // when an application reuses a subtree in several alternative slots.
        var computed: [ObjectIdentifier: Int] = [:]
        var pending = [(node: storage, ready: false)]
        while let frame = pending.popLast() {
            let identifier = ObjectIdentifier(frame.node)
            if computed[identifier] != nil { continue }
            if !frame.ready {
                pending.append((frame.node, true))
                for alternative in frame.node.alternatives.reversed() {
                    if computed[ObjectIdentifier(alternative.storage)] == nil {
                        pending.append((alternative.storage, false))
                    }
                }
                continue
            }
            var nodeHasher = Hasher()
            nodeHasher.combine(frame.node.key)
            CatalogExactText.hashOptional(frame.node.translation, into: &nodeHasher)
            CatalogExactText.hashOptional(frame.node.commentary, into: &nodeHasher)
            nodeHasher.combine(frame.node.placeholderDefinitions)
            nodeHasher.combine(frame.node.alternatives.count)
            for alternative in frame.node.alternatives {
                nodeHasher.combine(computed[ObjectIdentifier(alternative.storage)]!)
            }
            computed[identifier] = nodeHasher.finalize()
        }
        hasher.combine(computed[ObjectIdentifier(storage)]!)
    }
}
