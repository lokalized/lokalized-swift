/// One independently attempted catalog. Locale negotiation, per-key fallback,
/// failure handlers, result construction and bidi policy are integrated in M5.
package struct CompiledCatalogResolution: Sendable {
    package let locale: LocaleTag
    package let runtimeLimits: TranslationRuntimeLimits
    package let phoneticResolver: PhoneticResolver?
    private let nodes: [ExactString: CompiledCatalogNode]

    package init(_ catalog: ParsedStringsFile, locale: LocaleTag,
                 runtimeLimits: TranslationRuntimeLimits = .defaults,
                 phoneticResolver: PhoneticResolver? = nil) throws {
        try JDKLocaleTag.requireWellFormed(locale, description: "Locale")
        guard ExactString(catalog.locale) == ExactString(locale.tag) else {
            throw TranslationEvaluationError(kind: .invalidArgument,
                                             message: "Compiled catalog locale '\(catalog.locale)' does not match evaluation locale '\(locale.tag)'")
        }
        var compiler = CatalogResolutionCompiler(locale: locale, limits: runtimeLimits)
        var nodes: [ExactString: CompiledCatalogNode] = [:]
        for model in catalog.strings {
            guard nodes[model.key] == nil else {
                throw TranslationEvaluationError(kind: .invalidArgument,
                    message: "Duplicate localized string key '\(model.key)' encountered for locale '\(locale.tag)'")
            }
            nodes[model.key] = try compiler.node(model, rootKey: model.key, path: model.key.string)
        }
        self.locale = locale
        self.runtimeLimits = runtimeLimits
        self.phoneticResolver = phoneticResolver
        self.nodes = nodes
    }

    package func resolve(_ key: ExactString, placeholders: [ExactString: PlaceholderValue],
                         callerValueRenderer: ((ExactString, PlaceholderValue, Int) throws -> String?)? = nil,
                         callerValueRendererFactory: (() -> ((ExactString, PlaceholderValue, Int) throws -> String?))? = nil) throws -> CatalogResolutionOutcome {
        guard let node = nodes[key] else { return .missingTranslation }
        let attempt = CatalogResolutionAttempt(key: key, locale: locale, values: placeholders,
                                               limits: runtimeLimits, phoneticResolver: phoneticResolver,
                                               callerValueRenderer: callerValueRenderer,
                                               callerValueRendererFactory: callerValueRendererFactory)
        guard let selected = try attempt.select(node, inherited: [:], path: key.string) else { return .noMatchingAlternative }
        return .translation(try attempt.render(selected), selectedPath: selected.path)
    }
}

package enum CatalogResolutionOutcome: Sendable {
    case missingTranslation
    case noMatchingAlternative
    case translation(String, selectedPath: String)
}

package final class CompiledCatalogNode: Sendable {
    package let translation: String?
    package let placeholders: [ExactString: CompiledPlaceholderDefinition]
    package let placeholderOrder: [ExactString]
    package let alternatives: [CompiledWholeAlternative]
    package init(translation: String?, placeholders: [ExactString: CompiledPlaceholderDefinition],
                 placeholderOrder: [ExactString], alternatives: [CompiledWholeAlternative]) {
        self.translation = translation; self.placeholders = placeholders
        self.placeholderOrder = placeholderOrder; self.alternatives = alternatives
    }
}
package struct CompiledWholeAlternative: Sendable {
    package let expression: CompiledExpression
    package let node: CompiledCatalogNode
}
package struct CompiledFragmentAlternative: Sendable {
    package let expression: CompiledExpression
    package let translation: String
}
package enum CompiledPlaceholderDefinition: Sendable {
    case languageForm(LanguageFormTranslation)
    case expression(translation: String, alternatives: [CompiledFragmentAlternative])
    package var kindName: String {
        switch self { case .languageForm: "LanguageFormTranslation"; case .expression: "ExpressionTranslation" }
    }
}

private struct CatalogResolutionCompiler {
    let locale: LocaleTag
    let limits: TranslationRuntimeLimits
    var nodes: [ObjectIdentifier: CompiledCatalogNode] = [:]
    var alternatives: [ObjectIdentifier: CompiledExpression] = [:]

    mutating func node(_ model: LocalizedString, rootKey: ExactString, path: String) throws -> CompiledCatalogNode {
        if let cached = nodes[model.storageIdentity] { return cached }
        let order = model.placeholderDefinitionOrder
        var placeholders: [ExactString: CompiledPlaceholderDefinition] = [:]
        for name in order {
            switch model.placeholderDefinitions[name]! {
            case .languageForm(let definition): placeholders[name] = .languageForm(definition)
            case .expression(let definition):
                var compiled: [CompiledFragmentAlternative] = []
                for (index, alternative) in definition.alternatives.enumerated() {
                    let expression = try compile(alternative.expression.string,
                        context: "Unable to compile generated-fragment alternative \(index) expression '\(alternative.expression)' for placeholder '\(name)' declared at \(path) in root key '\(rootKey)' for locale '\(locale.tag)'")
                    compiled.append(.init(expression: expression, translation: alternative.translation))
                }
                placeholders[name] = .expression(translation: definition.translation, alternatives: compiled)
            }
        }
        var children: [CompiledWholeAlternative] = []
        for child in model.alternatives {
            let childPath = "\(path) -> alternative[\(child.key)]"
            let expression: CompiledExpression
            if let cached = alternatives[child.storageIdentity] { expression = cached }
            else {
                expression = try compile(child.key.string,
                    context: "Unable to compile whole-message alternative expression '\(child.key)' at \(childPath) in root key '\(rootKey)' for locale '\(locale.tag)'")
                alternatives[child.storageIdentity] = expression
            }
            children.append(.init(expression: expression, node: try node(child, rootKey: rootKey, path: childPath)))
        }
        let compiled = CompiledCatalogNode(translation: model.translation, placeholders: placeholders,
                                           placeholderOrder: order, alternatives: children)
        nodes[model.storageIdentity] = compiled
        return compiled
    }

    private func compile(_ source: String, context: String) throws -> CompiledExpression {
        do { return try ExpressionEvaluator.compile(source, runtimeLimits: limits) }
        catch {
            throw EvaluationErrors.contextualize(error, message: "\(context): \(EvaluationErrors.message(error))")
        }
    }
}
