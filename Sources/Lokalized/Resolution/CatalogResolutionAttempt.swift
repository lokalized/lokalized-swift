package struct CatalogPlaceholderBinding: Sendable {
    package let definition: CompiledPlaceholderDefinition
    package let declaringPath: String
}
package struct SelectedCatalogTemplate: Sendable {
    package let translation: String
    package let bindings: [ExactString: CatalogPlaceholderBinding]
    package let path: String
}

/// Mutable work is confined to one locale/key attempt. Predicates and selectors
/// always see values; selected generated templates and expanded text live in
/// separate dictionaries and cannot leak back into that caller snapshot.
package struct CatalogResolutionAttempt {
    package let key: ExactString
    package let locale: LocaleTag
    package let values: [ExactString: PlaceholderValue]
    package let limits: TranslationRuntimeLimits
    package let phoneticResolver: PhoneticResolver?
    package let callerValueRenderer: ((ExactString, PlaceholderValue, Int) throws -> String?)?
    package let callerValueRendererFactory: (() -> ((ExactString, PlaceholderValue, Int) throws -> String?))?

    package func select(_ node: CompiledCatalogNode, inherited: [ExactString: CatalogPlaceholderBinding],
                        path: String) throws -> SelectedCatalogTemplate? {
        var bindings = inherited
        for name in node.placeholderOrder {
            bindings[name] = .init(definition: node.placeholders[name]!, declaringPath: path)
        }
        for alternative in node.alternatives {
            if try evaluate(alternative.expression) {
                // A selected subtree is terminal even if it has no default and
                // no nested predicate matches. Never resume siblings/ancestors.
                return try select(alternative.node, inherited: bindings,
                                  path: "\(path) -> alternative[\(alternative.expression.source)]")
            }
        }
        guard let translation = node.translation else { return nil }
        return .init(translation: translation, bindings: bindings, path: path)
    }

    package func render(_ selected: SelectedCatalogTemplate) throws -> String {
        var pending: [ExactString] = [], pendingIndex = 0
        var queued = Set<ExactString>(), resolved = Set<ExactString>()
        var generated: [ExactString: GeneratedSelection] = [:]
        func enqueue(_ text: String) throws {
            for name in try StringInterpolator.placeholderNamesIn(text) {
                if selected.bindings[name] != nil && !resolved.contains(name) && queued.insert(name).inserted {
                    pending.append(name)
                }
            }
        }
        try enqueue(selected.translation)
        // First select every reached generated template in breadth-first source
        // order. Expansion/cycle checks happen only after this selection pass.
        while pendingIndex < pending.count {
            let name = pending[pendingIndex]; pendingIndex += 1
            queued.remove(name)
            guard resolved.insert(name).inserted else { continue }
            guard let binding = selected.bindings[name] else {
                throw invalidState("No effective definition was found for generated placeholder '\(name)' in key '\(key)'")
            }
            do {
                let selection = try selectPlaceholder(binding.definition)
                generated[name] = selection
                try enqueue(selection.translation)
            } catch {
                throw contextualize(error, name: name, binding: binding, selection: nil)
            }
        }
        var expanded: [ExactString: String] = [:], path: [ExactString] = [], consumed = 0
        return try expand(selected.translation, bindings: selected.bindings, generated: generated,
                          expanded: &expanded, path: &path, consumed: &consumed, depth: 0)
    }

    private func evaluate(_ expression: CompiledExpression) throws -> Bool {
        try ExpressionEvaluator.evaluate(expression, context: values, locale: locale,
                                         runtimeLimits: limits, phoneticResolver: phoneticResolver)
    }
    private func selectPlaceholder(_ definition: CompiledPlaceholderDefinition) throws -> GeneratedSelection {
        switch definition {
        case .languageForm(let form): return try selectLanguageForm(form)
        case .expression(let translation, let alternatives):
            for alternative in alternatives {
                let matched: Bool
                do { matched = try evaluate(alternative.expression) }
                catch {
                    throw EvaluationErrors.contextualize(error,
                        message: "Unable to evaluate generated-fragment expression '\(alternative.expression.source)': \(EvaluationErrors.message(error))")
                }
                if matched {
                    return .init(translation: alternative.translation,
                                 description: "expression '\(alternative.expression.source)'")
                }
            }
            return .init(translation: translation, description: "default translation")
        }
    }

    private func expand(_ template: String, bindings: [ExactString: CatalogPlaceholderBinding],
                        generated: [ExactString: GeneratedSelection], expanded: inout [ExactString: String],
                        path: inout [ExactString], consumed: inout Int, depth: Int) throws -> String {
        if depth > limits.maximumGeneratedPlaceholderDepth {
            throw invalidState("Generated placeholder nesting for key '\(key)' exceeds the maximum depth of \(limits.maximumGeneratedPlaceholderDepth): [\(path.map(\.string).joined(separator: ", "))]")
        }
        var replacements: [ExactString: String] = [:]
        for name in try StringInterpolator.placeholderNamesIn(template) {
            guard let binding = bindings[name] else { continue }
            if let memoized = expanded[name] { replacements[name] = memoized; continue }
            if let start = path.firstIndex(of: name) {
                let cycle = (Array(path[start...]) + [name]).map(\.string).joined(separator: " -> ")
                throw invalidState("Generated placeholder cycle for key '\(key)': \(cycle)")
            }
            if let selection = generated[name] {
                path.append(name)
                do {
                    let value = try expand(selection.translation, bindings: bindings, generated: generated,
                                           expanded: &expanded, path: &path, consumed: &consumed, depth: depth + 1)
                    expanded[name] = value
                    replacements[name] = value
                    path.removeLast()
                } catch {
                    path.removeLast()
                    throw contextualize(error, name: name, binding: binding, selection: selection.description)
                }
            }
        }
        let renderer = callerValueRendererFactory?() ?? callerValueRenderer
        let result = try StringInterpolator.interpolate(template, maximumOutputCharacters: limits.maximumInterpolatedOutputCharacters) { name, remaining in
            if bindings[name] != nil { return replacements[name] }
            let value = values[name] ?? .null
            // Missing values never invoke application display/bidi conversion.
            if value.isMissing { return nil }
            if let renderer { return try renderer(name, value, remaining) }
            return try value.interpolationText(maximumCharacters: remaining)
        }
        if !result.unresolvedPlaceholderNames.isEmpty {
            throw TranslationEvaluationError(kind: .invalidArgument,
                message: "Missing value for placeholder(s) [\(result.unresolvedPlaceholderNames.map(\.string).joined(separator: ", "))] in key '\(key)'")
        }
        if depth > 0 {
            let count = result.value.utf16.count
            if count > limits.maximumGeneratedExpansionCharacters - consumed {
                throw invalidState("Generated placeholder expansion for key '\(key)' exceeds the cumulative limit of \(limits.maximumGeneratedExpansionCharacters) characters")
            }
            consumed += count
        }
        return result.value
    }

    private func contextualize(_ error: any Error, name: ExactString, binding: CatalogPlaceholderBinding,
                               selection: String?) -> any Error {
        let selected = selection.map { "; selected \($0)" } ?? ""
        return EvaluationErrors.contextualize(error,
            message: "Unable to resolve generated placeholder '\(name)' (\(binding.definition.kindName)) for key '\(key)'; definition declared at \(binding.declaringPath)\(selected): \(EvaluationErrors.message(error))")
    }
    private func invalidState(_ message: String) -> TranslationEvaluationError {
        .init(kind: .invalidState, message: message)
    }
}

package struct GeneratedSelection: Sendable {
    package let translation: String
    package let description: String
}
