// Semantic validation follows Lokalized Java LocalizedStringValidator.
// Copyright 2017-2022 Product Mog LLC, 2022-2026 Revetware LLC.
// Licensed under Apache-2.0; see LICENSE.

/// Constructor admission is independent of JSON/loading budgets and retains
/// Java's model-validation order before matcher configuration/instance compile.
package struct RuntimeCatalogValidator {
    private var deepest: [ObjectIdentifier: Int] = [:]
    private var active = Set<ObjectIdentifier>()
    private let locale: LocaleTag
    private let rootKey: ExactString

    package init(locale: LocaleTag, rootKey: ExactString) {
        self.locale = locale; self.rootKey = rootKey
    }

    package mutating func validate(_ model: LocalizedString, alternative: Bool = false, depth: Int = 0) throws {
        guard depth <= 128 else { throw invalid("Alternative nesting exceeds the maximum depth of 128") }
        let identity = model.storageIdentity
        guard !active.contains(identity) else { throw invalid("Alternative graph contains an identity cycle") }
        if let previous = deepest[identity], previous >= depth { return }
        active.insert(identity)
        defer { active.remove(identity) }
        if alternative {
            do { _ = try ExpressionEvaluator.compile(model.key.string, runtimeLimits: .expressionCompilationHardCeilings) }
            catch {
                throw invalid("Invalid alternative expression '\(model.key)': \(EvaluationErrors.message(error))", cause: error)
            }
        }
        if let translation = model.translation { try template(translation, description: "translation") }
        for name in model.placeholderDefinitionOrder {
            try identifier(name, description: "generated placeholder")
            switch model.placeholderDefinitions[name]! {
            case .languageForm(let form):
                switch form.selector {
                case .value(let value): try identifier(value, description: "input for generated placeholder '\(name)'")
                case .range(let range):
                    try identifier(range.start, description: "range start for generated placeholder '\(name)'")
                    try identifier(range.end, description: "range end for generated placeholder '\(name)'")
                }
                guard !form.translationsByLanguageForm.isEmpty else { throw invalid("Generated placeholder '\(name)' must define translations") }
                var axes = Set<LanguageFormAxis>()
                for key in form.translationsByLanguageForm.keys.sorted(by: { ExactString($0.rawValue) < ExactString($1.rawValue) }) {
                    axes.insert(key.axis)
                    try template(form.translationsByLanguageForm[key]!, description: "translation for generated placeholder '\(name)'")
                }
                guard axes.count == 1 else { throw invalid("Generated placeholder '\(name)' may not mix language-form types") }
                if form.range != nil && axes != [.cardinality] { throw invalid("Range-driven placeholder '\(name)' only supports cardinality") }
            case .expression(let expression):
                try template(expression.translation, description: "default translation for generated placeholder '\(name)'")
                for (index, alternative) in expression.alternatives.enumerated() {
                    do { _ = try ExpressionEvaluator.compile(alternative.expression.string, runtimeLimits: .expressionCompilationHardCeilings) }
                    catch {
                        throw invalid("Invalid expression alternative \(index) for generated placeholder '\(name)', expression '\(alternative.expression)': \(EvaluationErrors.message(error))", cause: error)
                    }
                    try template(alternative.translation,
                                 description: "translation for generated placeholder '\(name)' expression alternative \(index) ('\(alternative.expression)')")
                }
            }
        }
        for child in model.alternatives { try validate(child, alternative: true, depth: depth + 1) }
        deepest[identity] = depth
    }

    private func template(_ text: String, description: String) throws {
        let names: [ExactString]
        do { names = try StringInterpolator.placeholderNamesIn(text) }
        catch { throw invalid("Invalid placeholder reference in \(description): \(EvaluationErrors.message(error))", cause: error) }
        for name in names { try identifier(name, description: description + " placeholder reference") }
    }

    private func identifier(_ name: ExactString, description: String) throws {
        guard IdentifierRules.isIdentifier(name.string) else { throw invalid("Invalid \(description) '\(name)'") }
        if LanguageFormValue(rawValue: name.string) != nil {
            throw invalid("Invalid \(description) '\(name)': language-form constants are reserved")
        }
    }
    private func invalid(_ message: String, cause: (any Error)? = nil) -> TranslationEvaluationError {
        .init(kind: .invalidArgument,
              message: "Invalid localized string '\(rootKey)' for locale '\(locale.tag)': \(message)", cause: cause)
    }
}
