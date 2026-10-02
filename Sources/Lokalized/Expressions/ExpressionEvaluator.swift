// Behavior ported from Lokalized Java ExpressionEvaluator.
// Copyright 2017-2022 Product Mog LLC, 2022-2026 Revetware LLC.
// Licensed under Apache-2.0; see LICENSE.

/// Package-private, like the Java evaluator. Runtime catalogs compile eagerly
/// and reuse these immutable expressions with raw caller values.
package enum ExpressionEvaluator {
    package static func evaluate(
        _ compiled: CompiledExpression, context: [ExactString: PlaceholderValue], locale: LocaleTag,
        runtimeLimits: TranslationRuntimeLimits = .defaults, phoneticResolver: PhoneticResolver? = nil
    ) throws -> Bool {
        try Engine(context: context, locale: locale, limits: runtimeLimits, resolver: phoneticResolver ?? PhoneticResolvers.failFast).run(compiled)
    }

    /// An instance compilation boundary that retains the loader's separate
    /// ExpressionCompilationError surface and hard-ceiling validation policy.
    package static func compile(_ source: String, runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> CompiledExpression {
        do { return try ExpressionCompiler.compile(source, limits: runtimeLimits) }
        catch let error as ExpressionCompilationError {
            throw compiledFailure(error)
        }
    }

    private static func compiledFailure(_ error: ExpressionCompilationError) -> TranslationEvaluationError {
        let cause: (any Error)?
        if let inner = error.cause as? ExpressionCompilationError { cause = compiledFailure(inner) }
        else { cause = error.cause }
        return failure(error.message, cause: cause)
    }

    /// Shared exact extraction for expression and generated selector paths.
    /// Ordinary comparisons use a PluralOperands value's signed source number.
    package static func numericValue(_ value: PlaceholderValue, placeholder: ExactString,
                                     runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> ExactDecimal {
        do {
            if let number = value.number {
                do { return try number.resolved(limits: runtimeLimits).decimal }
                catch let error as NumericError {
                    // NumericValue validates bounded carriers while converting.
                    // Java supplies this extraction site's name to those same
                    // scale/precision checks; other conversion messages stand.
                    if error.message.hasPrefix("Number scale ") || error.message.hasPrefix("Number precision ") {
                        throw NumericError(error.kind, "Numeric value '\(placeholder)'" + error.message.dropFirst("Number".count))
                    }
                    throw error
                }
            }
            if let operands = value.pluralOperands {
                return try validatedOperands(operands, placeholder: placeholder, limits: runtimeLimits).sourceNumber
            }
            throw failure("Unable to extract numeric value from '\(placeholder)'")
        } catch let error as NumericError {
            if error.kind == .roundingNecessary { throw error }
            throw failure("Unable to extract numeric value from '\(placeholder)': \(error.message)", cause: error)
        }
    }

    /// Plural classification keeps the expanded number and explicit metadata.
    package static func pluralOperands(for value: PlaceholderValue, placeholder: ExactString,
                                       runtimeLimits: TranslationRuntimeLimits = .defaults) throws -> PluralOperands {
        do {
            if let number = value.number { return try PluralOperands(number, runtimeLimits: runtimeLimits) }
            if let operands = value.pluralOperands {
                return try validatedOperands(operands, placeholder: placeholder, limits: runtimeLimits)
            }
            throw failure("Unable to extract numeric value from '\(placeholder)'")
        } catch let error as NumericError {
            if error.kind == .roundingNecessary { throw error }
            throw failure("Unable to extract numeric value from '\(placeholder)': \(error.message)", cause: error)
        }
    }

    private static func validatedOperands(_ operands: PluralOperands, placeholder: ExactString,
                                          limits: TranslationRuntimeLimits) throws -> PluralOperands {
        try operands.sourceNumber.validate(description: "Plural operands value '\(placeholder)'", limits: limits)
        if operands.e > limits.maximumCompactExponent {
            throw NumericError(.invalidArgument, "Plural operands compact exponent \(operands.e) exceeds the maximum of \(limits.maximumCompactExponent)")
        }
        if let places = operands.explicitVisibleDecimalPlaces, places > limits.maximumVisibleDecimalPlaces {
            throw NumericError(.invalidArgument, "Plural operands visible decimal places \(places) exceeds the maximum of \(limits.maximumVisibleDecimalPlaces)")
        }
        return operands
    }

    private static func failure(_ message: String, cause: (any Error)? = nil) -> TranslationEvaluationError {
        .init(kind: .expression, message: message, cause: cause)
    }

    private enum OperandType: String {
        case number = "NUMBER", gender = "GENDER", grammaticalCase = "GRAMMATICAL_CASE", definiteness = "DEFINITENESS"
        case classifier = "CLASSIFIER", formality = "FORMALITY", clusivity = "CLUSIVITY", animacy = "ANIMACY"
        case cardinality = "CARDINALITY", ordinality = "ORDINALITY", phonetic = "PHONETIC", unknown = "UNKNOWN"
        init(_ axis: LanguageFormAxis) {
            switch axis {
            case .cardinality: self = .cardinality
            case .ordinality: self = .ordinality
            case .gender: self = .gender
            case .grammaticalCase: self = .grammaticalCase
            case .definiteness: self = .definiteness
            case .classifier: self = .classifier
            case .formality: self = .formality
            case .clusivity: self = .clusivity
            case .animacy: self = .animacy
            case .phonetic: self = .phonetic
            }
        }
        var typeName: String {
            switch self {
            case .number: "Number"
            case .gender: "Gender"
            case .grammaticalCase: "GrammaticalCase"
            case .definiteness: "Definiteness"
            case .classifier: "Classifier"
            case .formality: "Formality"
            case .clusivity: "Clusivity"
            case .animacy: "Animacy"
            case .cardinality: "Cardinality"
            case .ordinality: "Ordinality"
            case .phonetic: "Phonetic"
            case .unknown: "UNKNOWN"
            }
        }
        var noun: String { self == .grammaticalCase ? "grammatical case" : rawValue.lowercased() }
        var isNominal: Bool { ![.number, .cardinality, .ordinality, .phonetic, .unknown].contains(self) }
    }

    private struct Engine {
        let context: [ExactString: PlaceholderValue]
        let locale: LocaleTag
        let limits: TranslationRuntimeLimits
        let resolver: PhoneticResolver

        /// Continuations emulate the left-to-right tree walk without recursive
        /// calls. A skipped branch does not even look up its variable's type.
        private enum Frame {
            case enter(Int)
            case afterLeft(ExpressionOperator, right: Int)
            case afterRight(ExpressionOperator, left: Bool)
        }
        func run(_ compiled: CompiledExpression) throws -> Bool {
            var frames: [Frame] = [.enter(compiled.root)], result = false
            while let frame = frames.popLast() {
                switch frame {
                case .enter(let index):
                    switch compiled.nodes[index] {
                    case .operand(let token): throw failure("Expected boolean but encountered '\(token.symbol)'")
                    case .operation(let operation, let left, let right):
                        if operation.isBoolean {
                            frames.append(.afterLeft(operation, right: right)); frames.append(.enter(left))
                        } else {
                            guard case .operand(let lhs) = compiled.nodes[left], case .operand(let rhs) = compiled.nodes[right] else {
                                throw failure("Unexpected comparison tree while evaluating '\(compiled.source)'")
                            }
                            result = try compare(lhs, operation, rhs)
                        }
                    }
                case .afterLeft(let operation, let right):
                    if operation == .and && !result || operation == .or && result { continue }
                    frames.append(.afterRight(operation, left: result)); frames.append(.enter(right))
                case .afterRight(let operation, let left): result = operation == .and ? left && result : left || result
                }
            }
            return result
        }

        private func binding(_ token: ExpressionToken) -> PlaceholderValue? { context[ExactString(token.symbol)] }
        private func form(_ token: ExpressionToken) -> LanguageFormValue? {
            if case .operand(.unknownVariable) = token.kind {
                if case .languageForm(let value) = binding(token) { return value }
                return nil
            }
            return LanguageFormValue(rawValue: token.symbol)
        }
        private func type(_ token: ExpressionToken) throws -> OperandType {
            if case .operand(.number) = token.kind { return .number }
            if case .operand(.unknownVariable) = token.kind {
                guard let value = binding(token) else { throw failure("No value was provided for placeholder '\(token.symbol)'") }
                switch value {
                case .null: throw failure("Placeholder '\(token.symbol)' resolved to null")
                case .number, .byte, .short, .integer, .pluralOperands: return .number
                case .languageForm(let value): return .init(value.axis)
                case .text: return .phonetic
                case .boolean, .custom: return .unknown
                }
            }
            if let value = form(token) { return .init(value.axis) }
            return .unknown
        }
        private func isRawText(_ token: ExpressionToken) -> Bool {
            if case .operand(.unknownVariable) = token.kind, case .text = binding(token) { return true }
            return false
        }
        private func runtimeName(_ token: ExpressionToken, type: OperandType) -> String {
            if case .operand(.unknownVariable) = token.kind {
                return binding(token)?.diagnosticTypeName ?? type.typeName
            }
            return type.typeName
        }
        private func compare(_ left: ExpressionToken, _ operation: ExpressionOperator, _ right: ExpressionToken) throws -> Bool {
            let lhsType = try type(left), rhsType = try type(right)
            let comparison = "\(left.symbol) \(operation.rawValue) \(right.symbol)"
            if lhsType == .unknown || rhsType == .unknown {
                throw failure("Unable to evaluate expression '\(comparison)'. Operand types \(lhsType.rawValue) and \(rhsType.rawValue) are unsupported")
            }
            let lhsText = isRawText(left), rhsText = isRawText(right)
            if lhsType == .phonetic && rhsType == .phonetic && lhsText && rhsText {
                if !operation.isOrdering {
                    throw failure("Raw CharSequence placeholders '\(left.symbol)' and '\(right.symbol)' cannot be compared with '\(operation.rawValue)': expressions do not support textual equality. Compare phonetic input with a PHONETIC_* constant or an explicit Phonetic value instead")
                }
                throw failure("Raw CharSequence placeholders '\(left.symbol)' and '\(right.symbol)' cannot be compared with '\(operation.rawValue)': expressions do not support textual ordering. Use numeric operands for ordering, or compare phonetic input with a PHONETIC_* constant or an explicit Phonetic value using '==' or '!='")
            }
            let textOperand = lhsType == .number && rhsText ? right : rhsType == .number && lhsText ? left : nil
            if let textOperand {
                throw failure("Numeric comparison '\(comparison)' requires numeric operands supplied as Number or PluralOperands values, but placeholder '\(textOperand.symbol)' resolved to String")
            }
            if lhsType == .number && rhsType == .number {
                let lhs = try number(left), rhs = try number(right)
                let value = lhs.compare(to: rhs)
                switch operation {
                case .less: return value < 0
                case .greater: return value > 0
                case .equal: return value == 0
                case .notEqual: return value != 0
                case .lessOrEqual: return value <= 0
                case .greaterOrEqual: return value >= 0
                case .and, .or: throw failure("Encountered unexpected operator '\(operation.rawValue)'")
                }
            }
            if lhsType == rhsType && lhsType.isNominal {
                try requireEquality(operation, lhsType, comparison)
                let equal = form(left) == form(right)
                return operation == .equal ? equal : !equal
            }
            if lhsType == .cardinality || rhsType == .cardinality {
                try requireEquality(operation, .cardinality, comparison)
                let lhs = try category(left, ordinal: false), rhs = try category(right, ordinal: false)
                return operation == .equal ? lhs == rhs : lhs != rhs
            }
            if lhsType == .ordinality || rhsType == .ordinality {
                try requireEquality(operation, .ordinality, comparison)
                let lhs = try category(left, ordinal: true), rhs = try category(right, ordinal: true)
                return operation == .equal ? lhs == rhs : lhs != rhs
            }
            if lhsType == .phonetic || rhsType == .phonetic {
                try requireEquality(operation, .phonetic, comparison)
                let lhs = try phonetic(left), rhs = try phonetic(right)
                return operation == .equal ? lhs == rhs : lhs != rhs
            }
            throw failure("Unable to evaluate expression '\(comparison)'. Operand runtime types \(runtimeName(left, type: lhsType)) and \(runtimeName(right, type: rhsType)) are incompatible")
        }
        private func requireEquality(_ operation: ExpressionOperator, _ type: OperandType, _ comparison: String) throws {
            if operation.isOrdering {
                throw failure("You may only use the '==' and '!=' operators when performing \(type.noun) comparisons. Offending comparison: '\(comparison)'")
            }
        }
        private func number(_ token: ExpressionToken) throws -> ExactDecimal {
            if let literal = token.numeric { return literal.decimal }
            guard let value = binding(token) else { throw failure("Unable to extract numeric value from '\(token.symbol)'") }
            return try numericValue(value, placeholder: ExactString(token.symbol), runtimeLimits: limits)
        }
        private func category(_ token: ExpressionToken, ordinal: Bool) throws -> LanguageFormValue {
            let target: LanguageFormAxis = ordinal ? .ordinality : .cardinality
            if let value = form(token), value.axis == target { return value }
            let operands: PluralOperands
            if let literal = token.numeric {
                operands = try pluralOperands(for: .number(.decimal(literal.decimal)), placeholder: ExactString(token.symbol), runtimeLimits: limits)
            } else if let value = binding(token) {
                switch value {
                case .number, .byte, .short, .integer, .pluralOperands:
                    operands = try pluralOperands(for: value, placeholder: ExactString(token.symbol), runtimeLimits: limits)
                default: throw failure("Unable to extract \(ordinal ? "Ordinality" : "Cardinality") value from '\(token.symbol)'")
                }
            } else { throw failure("Unable to extract \(ordinal ? "Ordinality" : "Cardinality") value from '\(token.symbol)'") }
            do {
                try JDKLocaleTag.requireWellFormed(locale, description: "Locale")
                if ordinal { return .ordinality(try Ordinality.forOperands(operands, locale: locale.tag)) }
                return .cardinality(try Cardinality.forOperands(operands, locale: locale.tag))
            } catch let error as LocaleTagError {
                throw TranslationEvaluationError(kind: .invalidArgument, message: error.message, cause: error)
            }
        }
        private func phonetic(_ token: ExpressionToken) throws -> Phonetic {
            if let value = form(token), case .phonetic(let phonetic) = value { return phonetic }
            if case .text(let term) = binding(token) {
                if term.utf16.count > limits.maximumInterpolatedOutputCharacters {
                    let message = "Phonetic input for placeholder '\(token.symbol)' exceeds the maximum of \(limits.maximumInterpolatedOutputCharacters) characters"
                    throw failure(message, cause: TranslationEvaluationError(kind: .invalidArgument, message: message))
                }
                // Unknown application errors remain the exact thrown object.
                return try resolver(term, locale)
            }
            throw failure("Unable to extract Phonetic value from '\(token.symbol)'")
        }
    }
}
