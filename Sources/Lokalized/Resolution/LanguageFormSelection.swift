package extension CatalogResolutionAttempt {
    func selectLanguageForm(_ definition: LanguageFormTranslation) throws -> GeneratedSelection {
        guard let axis = definition.translationsByLanguageForm.keys.first?.axis else {
            throw TranslationEvaluationError(kind: .invalidState, message: "A generated language-form placeholder requires translations")
        }
        let typeName = Self.typeName(axis)
        let selected: LanguageFormValue
        let description: String
        let missingMessage: String
        switch definition.selector {
        case .range(let range):
            guard let startValue = values[range.start], !startValue.isMissing else {
                throw refusal("Missing range start placeholder '\(range.start)' for key '\(key)'")
            }
            guard let endValue = values[range.end], !endValue.isMissing else {
                throw refusal("Missing range end placeholder '\(range.end)' for key '\(key)'")
            }
            let start = try cardinality(startValue, name: range.start, description: "Range start placeholder")
            let end = try cardinality(endValue, name: range.end, description: "Range end placeholder")
            let rangeForm = try Cardinality.forRange(start, end, locale: locale.tag)
            selected = .cardinality(rangeForm)
            description = "Cardinality.\(rangeForm.displayName) range (start \(start.displayName), end \(end.displayName))"
            missingMessage = "Missing Cardinality translation for range cardinality \(rangeForm.displayName) (start was \(start.displayName), end was \(end.displayName))"
        case .value(let name):
            guard let value = values[name], !value.isMissing else {
                throw refusal("Missing value for placeholder '\(name)' in key '\(key)'")
            }
            switch axis {
            case .cardinality: selected = .cardinality(try cardinality(value, name: name, description: "Placeholder"))
            case .ordinality:
                if case .ordinality(let form) = value.languageForm { selected = .ordinality(form) }
                else if value.number != nil || value.pluralOperands != nil {
                    selected = .ordinality(try Ordinality.forOperands(operands(value, description: "Placeholder"), locale: locale.tag))
                } else {
                    throw refusal("Placeholder '\(name)' in key '\(key)' must be a Number, PluralOperands, or Ordinality but was \(value.diagnosticTypeName)")
                }
            case .phonetic:
                if case .phonetic(let form) = value.languageForm { selected = .phonetic(form) }
                else if let term = try value.phoneticTerm(maximumCharacters: limits.maximumInterpolatedOutputCharacters,
                                                          description: "Phonetic input for placeholder '\(name)' in key '\(key)'") {
                    selected = .phonetic(try (phoneticResolver ?? PhoneticResolvers.failFast)(term, locale))
                } else {
                    throw refusal("Placeholder '\(name)' in key '\(key)' must be a Phonetic or CharSequence but was \(value.diagnosticTypeName)")
                }
            default:
                guard let form = value.languageForm, form.axis == axis else {
                    throw refusal("Placeholder '\(name)' in key '\(key)' must be a \(typeName) but was \(value.diagnosticTypeName)")
                }
                selected = form
            }
            description = "\(typeName).\(selected.displayName)"
            missingMessage = "Missing \(typeName) translation for \(selected.displayName)"
        }
        guard let translation = definition.translationsByLanguageForm[selected] else {
            throw TranslationEvaluationError(kind: .invalidState, message: missingMessage)
        }
        return .init(translation: translation, description: description)
    }

    private func cardinality(_ value: PlaceholderValue, name: ExactString, description: String) throws -> Cardinality {
        if case .cardinality(let form) = value.languageForm { return form }
        guard value.number != nil || value.pluralOperands != nil else {
            throw refusal("\(description) '\(name)' in key '\(key)' must be a Number, PluralOperands, or Cardinality but was \(value.diagnosticTypeName)")
        }
        return try Cardinality.forOperands(operands(value, description: description), locale: locale.tag)
    }

    /// Selector validation has its own category and wording. The expression
    /// evaluator's numeric extraction helper deliberately wraps these failures
    /// as expression errors, so it must not be used for generated selectors.
    private func operands(_ value: PlaceholderValue, description: String) throws -> PluralOperands {
        if let number = value.number { return try PluralOperands(number, runtimeLimits: limits) }
        let operands = value.pluralOperands!
        try operands.sourceNumber.validate(description: description, limits: limits)
        if operands.e > limits.maximumCompactExponent {
            throw refusal("\(description) compact exponent \(operands.e) exceeds the configured maximum of \(limits.maximumCompactExponent)")
        }
        if let places = operands.explicitVisibleDecimalPlaces, places > limits.maximumVisibleDecimalPlaces {
            throw refusal("\(description) visible decimal places \(places) exceeds the configured maximum of \(limits.maximumVisibleDecimalPlaces)")
        }
        return operands
    }

    private func refusal(_ message: String) -> TranslationEvaluationError {
        .init(kind: .invalidArgument, message: message)
    }
    private static func typeName(_ axis: LanguageFormAxis) -> String {
        switch axis {
        case .cardinality: "Cardinality"
        case .ordinality: "Ordinality"
        case .gender: "Gender"
        case .grammaticalCase: "GrammaticalCase"
        case .definiteness: "Definiteness"
        case .classifier: "Classifier"
        case .formality: "Formality"
        case .clusivity: "Clusivity"
        case .animacy: "Animacy"
        case .phonetic: "Phonetic"
        }
    }
}
