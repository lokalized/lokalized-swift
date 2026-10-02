// Load-time validation ported from lokalized-java ExpressionTokenizer/Evaluator.
// Copyright 2017-2022 Product Mog LLC, 2022-2026 Revetware LLC.
// Licensed under the Apache License, Version 2.0; see LICENSE.

package struct ExpressionCompilationError: Error, Sendable, CustomStringConvertible {
    package enum Reason: String, Sendable {
        case lexical, numericLiteral, characterLimit, tokenLimit, nestingLimit, grouping, staticType
    }
    package let reason: Reason
    package let message: String
    package let cause: (any Error)?
    package var description: String { message }
}

package extension TranslationRuntimeLimits {
    /// Loading validates against hard ceilings; per-instance limits apply again
    /// when an expression is compiled for that instance during construction.
    static let expressionCompilationHardCeilings: Self = {
        do {
            return try Self(
                maximumNumberPrecision: hardMaximumNumberPrecision,
                maximumAbsoluteNumberScale: hardMaximumAbsoluteNumberScale,
                maximumExpressionCharacters: hardMaximumExpressionCharacters,
                maximumExpressionTokens: hardMaximumExpressionTokens,
                maximumExpressionNestingDepth: hardMaximumExpressionNestingDepth
            )
        } catch { preconditionFailure("Library hard ceilings are invalid: \(error)") }
    }()
}

package enum ExpressionValueType: String, Sendable {
    case number = "NUMBER", boolean = "BOOLEAN", gender = "GENDER"
    case grammaticalCase = "GRAMMATICAL_CASE", definiteness = "DEFINITENESS"
    case classifier = "CLASSIFIER", formality = "FORMALITY", clusivity = "CLUSIVITY"
    case animacy = "ANIMACY", cardinality = "CARDINALITY", ordinality = "ORDINALITY"
    case phonetic = "PHONETIC", unknownVariable = "UNKNOWN_VARIABLE"
}

package struct ExpressionNumericLiteral: Sendable {
    package let negative: Bool
    /// Leading zeroes removed, trailing zeroes retained, zero represented by "0".
    package let coefficient: String
    package let scale: Int
    /// Literal precision/scale are validated eagerly. Evaluation never reparses.
    package let decimal: ExactDecimal
    package init(negative: Bool, coefficient: String, scale: Int) {
        self.negative = negative; self.coefficient = coefficient; self.scale = scale
        self.decimal = .init(digits: Array(coefficient.utf8), negative: negative, scale: scale)
    }
}

package enum ExpressionOperator: String, Sendable {
    case and = "&&", or = "||", less = "<", greater = ">"
    case equal = "==", notEqual = "!=", lessOrEqual = "<=", greaterOrEqual = ">="
    var precedence: Int { self == .or ? 0 : (self == .and ? 1 : 2) }
    var isBoolean: Bool { self == .and || self == .or }
    var isOrdering: Bool { self == .less || self == .lessOrEqual || self == .greater || self == .greaterOrEqual }
}

package struct ExpressionToken: Sendable {
    package enum Kind: Sendable {
        case operand(ExpressionValueType), operation(ExpressionOperator), groupStart, groupEnd
    }
    package let kind: Kind
    package let symbol: String
    package var numeric: ExpressionNumericLiteral?
}

/// Flat immutable nodes avoid recursion during compilation, evaluation, and
/// destruction. Boolean edges retain source order for true short circuit.
package enum ExpressionNode: Sendable {
    case operand(ExpressionToken)
    case operation(ExpressionOperator, left: Int, right: Int)
}

/// Validated IR reusable across calls. Variables are read only when reached.
package struct CompiledExpression: Sendable {
    package let source: ExactString
    package let postfix: [ExpressionToken]
    package let nodes: [ExpressionNode]
    package let root: Int
}

package enum ExpressionCompiler {
    package static func validate(_ expression: String, limits: TranslationRuntimeLimits = .expressionCompilationHardCeilings) throws {
        _ = try compile(expression, limits: limits)
    }

    package static func compile(_ expression: String, limits: TranslationRuntimeLimits = .expressionCompilationHardCeilings) throws -> CompiledExpression {
        let length = expression.utf16.count
        guard length <= limits.maximumExpressionCharacters else {
            throw failure(.characterLimit, "Expression length \(length) exceeds maximum supported length \(limits.maximumExpressionCharacters)")
        }
        var tokens = try tokenize(expression)
        // Lex the entire source before rejecting any literal, then validate all
        // literals before token/depth/grammar checks, matching the Java pipeline.
        for index in tokens.indices {
            if case .operand(.number) = tokens[index].kind {
                tokens[index].numeric = try numericLiteral(tokens[index].symbol, limits: limits)
            }
        }
        guard tokens.count <= limits.maximumExpressionTokens else {
            throw failure(.tokenLimit, "Expression contains \(tokens.count) tokens, which exceeds maximum supported token count \(limits.maximumExpressionTokens)")
        }
        var depth = 0
        for token in tokens {
            switch token.kind {
            case .groupStart:
                depth += 1
                guard depth <= limits.maximumExpressionNestingDepth else {
                    throw failure(.nestingLimit, "Expression grouping depth exceeds maximum supported depth \(limits.maximumExpressionNestingDepth)")
                }
            case .groupEnd: if depth > 0 { depth -= 1 }
            default: break
            }
        }
        let postfix = try shuntingYard(tokens)
        do { try validateTypes(postfix) }
        catch let error as ExpressionCompilationError {
            throw failure(error.reason, "Invalid expression '\(expression)': \(error.message)", cause: error)
        }
        let tree = buildTree(postfix)
        return .init(source: ExactString(expression), postfix: postfix, nodes: tree.nodes, root: tree.root)
    }

    private static let forms: [ExactString: ExpressionValueType] = {
        var result: [ExactString: ExpressionValueType] = [:]
        func add<Form: LanguageForm & CaseIterable>(_ type: Form.Type, _ value: ExpressionValueType) {
            for form in Form.allCases { result[ExactString(form.rawValue)] = value }
        }
        add(Cardinality.self, .cardinality); add(Ordinality.self, .ordinality)
        add(Gender.self, .gender); add(GrammaticalCase.self, .grammaticalCase)
        add(Definiteness.self, .definiteness); add(Classifier.self, .classifier)
        add(Formality.self, .formality); add(Clusivity.self, .clusivity)
        add(Animacy.self, .animacy); add(Phonetic.self, .phonetic)
        return result
    }()

    private static func tokenize(_ expression: String) throws -> [ExpressionToken] {
        let scalars = Array(expression.unicodeScalars)
        var offsets: [Int] = []
        var offset = 0
        for scalar in scalars { offsets.append(offset); offset += scalar.value > 0xffff ? 2 : 1 }
        var tokens: [ExpressionToken] = []
        var index = 0
        func text(_ first: Int, _ end: Int) -> String { String(String.UnicodeScalarView(scalars[first..<end])) }
        while index < scalars.count {
            let start = index
            let value = scalars[index].value
            if [32, 9, 13, 10, 12].contains(value) { index += 1; continue }
            if value == 40 || value == 41 {
                tokens.append(.init(kind: value == 40 ? .groupStart : .groupEnd, symbol: text(index, index + 1)))
                index += 1; continue
            }
            if index + 1 < scalars.count, let operation = ExpressionOperator(rawValue: text(index, index + 2)) {
                tokens.append(.init(kind: .operation(operation), symbol: operation.rawValue)); index += 2; continue
            }
            if let operation = ExpressionOperator(rawValue: text(index, index + 1)) {
                tokens.append(.init(kind: .operation(operation), symbol: operation.rawValue)); index += 1; continue
            }
            if let end = numberEnd(scalars, index) {
                tokens.append(.init(kind: .operand(.number), symbol: text(index, end))); index = end; continue
            }
            if IdentifierRules.isStart(scalars[index]) {
                index += 1
                while index < scalars.count && IdentifierRules.isContinuation(scalars[index]) { index += 1 }
                let symbol = text(start, index)
                tokens.append(.init(kind: .operand(forms[ExactString(symbol)] ?? .unknownVariable), symbol: symbol)); continue
            }
            let hex = String(value, radix: 16, uppercase: true)
            var message = "Unexpected code point U+\(String(repeating: "0", count: max(0, 4 - hex.count)))\(hex) at index \(offsets[index]) while evaluating expression '\(expression)'."
            if value == 61 { message += " Did you mean '=='?" }
            throw failure(.lexical, message)
        }
        return tokens
    }

    private static func numberEnd(_ scalars: [Unicode.Scalar], _ start: Int) -> Int? {
        func digit(_ index: Int) -> Bool { index < scalars.count && (48...57).contains(scalars[index].value) }
        var index = start
        if index < scalars.count && (scalars[index].value == 43 || scalars[index].value == 45) { index += 1 }
        let before = index
        while digit(index) { index += 1 }
        let integerDigits = index - before
        if index < scalars.count && scalars[index].value == 46 {
            index += 1
            let fractionStart = index
            while digit(index) { index += 1 }
            if integerDigits == 0 && index == fractionStart { return nil }
        } else if integerDigits == 0 { return nil }
        if index < scalars.count && (scalars[index].value == 69 || scalars[index].value == 101) {
            let exponentStart = index
            index += 1
            if index < scalars.count && (scalars[index].value == 43 || scalars[index].value == 45) { index += 1 }
            let digitsStart = index
            while digit(index) { index += 1 }
            if index == digitsStart { index = exponentStart } // regex backtracks incomplete exponent
        }
        return index
    }

    private static func numericLiteral(_ symbol: String, limits: TranslationRuntimeLimits) throws -> ExpressionNumericLiteral {
        let bytes = Array(symbol.utf8)
        let exponentAt = bytes.firstIndex { $0 == 69 || $0 == 101 } ?? bytes.count
        let dot = bytes[..<exponentAt].firstIndex(of: 46)
        let fractionalPlaces = dot.map { exponentAt - $0 - 1 } ?? 0
        var exponent: Int64 = 0
        if exponentAt < bytes.count {
            var index = exponentAt + 1
            let negative = bytes[index] == 45
            if bytes[index] == 45 || bytes[index] == 43 { index += 1 }
            while bytes.count - index > 10 && bytes[index] == 48 { index += 1 }
            guard bytes.count - index <= 10 else {
                throw numericFailure(symbol, message: "Too many nonzero exponent digits.", kind: .invalidDecimal)
            }
            for byte in bytes[index...] { exponent = exponent * 10 + Int64(byte - 48) }
            if negative { exponent = -exponent }
        }
        let scale = Int64(fractionalPlaces) - exponent
        guard scale >= Int64(Int32.min) && scale <= Int64(Int32.max) else {
            throw numericFailure(symbol, message: "Exponent overflow.", kind: .invalidDecimal)
        }
        guard abs(scale) <= Int64(limits.maximumAbsoluteNumberScale) else {
            throw numericFailure(symbol, message: "Numeric literal '\(symbol)' scale \(scale) exceeds the maximum absolute scale of \(limits.maximumAbsoluteNumberScale)")
        }
        let digits = bytes[..<exponentAt].filter { (48...57).contains($0) }
        let first = digits.firstIndex { $0 != 48 } ?? (digits.count - 1)
        let significant = Array(digits[first...])
        guard significant.count <= limits.maximumNumberPrecision else {
            throw numericFailure(symbol, message: "Numeric literal '\(symbol)' precision \(significant.count) exceeds the maximum of \(limits.maximumNumberPrecision)")
        }
        return .init(negative: bytes.first == 45, coefficient: String(decoding: significant, as: UTF8.self), scale: Int(scale))
    }

    private static func shuntingYard(_ tokens: [ExpressionToken]) throws -> [ExpressionToken] {
        var output: [ExpressionToken] = []
        var operators: [ExpressionToken] = []
        for token in tokens {
            switch token.kind {
            case .operand: output.append(token)
            case .operation(let operation):
                while let top = operators.last, case .operation(let prior) = top.kind, operation.precedence <= prior.precedence {
                    output.append(operators.removeLast())
                }
                operators.append(token)
            case .groupStart: operators.append(token)
            case .groupEnd:
                while let top = operators.last {
                    if case .groupStart = top.kind { break }
                    output.append(operators.removeLast())
                }
                guard !operators.isEmpty else { throw failure(.grouping, "Unbalanced ) detected") }
                operators.removeLast()
            }
        }
        while let token = operators.popLast() {
            if case .groupStart = token.kind { throw failure(.grouping, "Unbalanced ( detected") }
            output.append(token)
        }
        return output
    }

    private struct ValidationValue { let type: ExpressionValueType; let symbol: String }

    /// Types and arity have already been checked. Each node references earlier
    /// nodes, so a caller cannot construct a cyclic or malformed graph.
    private static func buildTree(_ postfix: [ExpressionToken]) -> (nodes: [ExpressionNode], root: Int) {
        var nodes: [ExpressionNode] = [], stack: [Int] = []
        nodes.reserveCapacity(postfix.count)
        for token in postfix {
            switch token.kind {
            case .operand: nodes.append(.operand(token))
            case .operation(let operation):
                let right = stack.removeLast(), left = stack.removeLast()
                nodes.append(.operation(operation, left: left, right: right))
            case .groupStart, .groupEnd: preconditionFailure("Validated postfix cannot contain grouping")
            }
            stack.append(nodes.count - 1)
        }
        return (nodes, stack[0])
    }

    private static func validateTypes(_ tokens: [ExpressionToken]) throws {
        guard !tokens.isEmpty else { throw failure(.staticType, "Expression must not be empty") }
        var stack: [ValidationValue] = []
        for token in tokens {
            switch token.kind {
            case .operand(let type): stack.append(.init(type: type, symbol: token.symbol))
            case .operation(let operation):
                guard stack.count >= 2 else { throw failure(.staticType, "Insufficient arguments provided for operator '\(token.symbol)'") }
                let right = stack.removeLast(), left = stack.removeLast()
                try validateOperator(left, operation, right)
                stack.append(.init(type: .boolean, symbol: "previous comparison"))
            default: throw failure(.staticType, "Unexpected symbol encountered: '\(token.symbol)'")
            }
        }
        if stack.count == 1 {
            let result = stack[0]
            guard result.type == .boolean else {
                throw failure(.staticType, "Expression must evaluate to a boolean result but ended with operand '\(result.symbol)' (\(result.type.rawValue))")
            }
        } else {
            throw failure(.staticType, "Unexpected extra values exist on the stack: [\(stack.reversed().map(\.symbol).joined(separator: ", "))]")
        }
    }

    private static func validateOperator(_ left: ValidationValue, _ operation: ExpressionOperator, _ right: ValidationValue) throws {
        let expression = "\(left.symbol) \(operation.rawValue) \(right.symbol)"
        let types = "\(left.type.rawValue) and \(right.type.rawValue)"
        if operation.isBoolean {
            guard left.type == .boolean && right.type == .boolean else {
                throw failure(.staticType, "Operator '\(operation.rawValue)' requires boolean operands but encountered \(types) in '\(expression)'")
            }
        } else {
            guard left.type != .boolean && right.type != .boolean else {
                throw failure(.staticType, "Chained comparisons are not supported. Operator '\(operation.rawValue)' cannot compare \(types) in '\(expression)'")
            }
            if operation.isOrdering {
                guard [.number, .unknownVariable].contains(left.type) && [.number, .unknownVariable].contains(right.type) else {
                    throw failure(.staticType, "Operator '\(operation.rawValue)' requires numeric operands but encountered \(types) in '\(expression)'")
                }
            } else {
                let compatible = left.type == .unknownVariable || right.type == .unknownVariable || left.type == right.type
                    || (left.type == .number && [.cardinality, .ordinality].contains(right.type))
                    || (right.type == .number && [.cardinality, .ordinality].contains(left.type))
                guard compatible else {
                    throw failure(.staticType, "Operator '\(operation.rawValue)' cannot compare \(types) operands in '\(expression)'")
                }
            }
        }
    }

    private static func numericFailure(_ symbol: String, message: String, kind: NumericError.Kind = .invalidArgument) -> ExpressionCompilationError {
        failure(.numericLiteral, "Invalid numeric literal '\(symbol)': \(message)", cause: NumericError(kind, message))
    }

    private static func failure(_ reason: ExpressionCompilationError.Reason, _ message: String,
                                cause: (any Error)? = nil) -> ExpressionCompilationError {
        .init(reason: reason, message: message, cause: cause)
    }
}
