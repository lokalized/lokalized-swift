/// UTF-16 scanner shared by fragment rendering and the later failure-key path.
/// Caller replacements are strings; no conversion, selector evaluation, or
/// recursive interpolation is hidden inside this scanner.
package enum StringInterpolator {
    package struct InterpolationResult: Sendable {
        package let value: String
        package let unresolvedPlaceholderNames: [ExactString]
    }

    package static func placeholderNamesIn(_ text: String, strict: Bool = true) throws -> [ExactString] {
        try scan(text, strict: strict, maximumOutputCharacters: 0, collectOnly: true,
                 replacement: { _, _ in nil }).unresolvedPlaceholderNames
    }

    /// A zero output limit means unbounded. A replacement receives the number
    /// of remaining UTF-16 units, or -1 when the output has no limit.
    package static func interpolate(
        _ text: String, strict: Bool = true, maximumOutputCharacters: Int = 0,
        replacement: (ExactString, Int) throws -> String?
    ) throws -> InterpolationResult {
        guard maximumOutputCharacters >= 0 else {
            throw TranslationEvaluationError(kind: .invalidArgument, message: "maximumOutputCharacters must be non-negative")
        }
        return try scan(text, strict: strict, maximumOutputCharacters: maximumOutputCharacters,
                        collectOnly: false, replacement: replacement)
    }

    private static func scan(
        _ text: String, strict: Bool, maximumOutputCharacters: Int, collectOnly: Bool,
        replacement: (ExactString, Int) throws -> String?
    ) throws -> InterpolationResult {
        let units = text.utf16
        var cursor = units.startIndex, position = 0
        var output: [UInt16] = []
        if !collectOnly && maximumOutputCharacters > 0 { output.reserveCapacity(min(256, maximumOutputCharacters)) }
        var unresolved: [ExactString] = [], seen = Set<ExactString>()
        func advance(_ index: String.UTF16View.Index, by count: Int) -> String.UTF16View.Index {
            units.index(index, offsetBy: count)
        }
        func pair(_ index: String.UTF16View.Index, _ unit: UInt16) -> Bool {
            guard index < units.endIndex && units[index] == unit else { return false }
            let next = units.index(after: index)
            return next < units.endIndex && units[next] == unit
        }
        func closing(_ start: String.UTF16View.Index) -> String.UTF16View.Index? {
            var index = start
            while index < units.endIndex {
                if pair(index, 125) { return index }
                index = units.index(after: index)
            }
            return nil
        }
        func append<Units: Collection>(_ value: Units) throws where Units.Element == UInt16 {
            if collectOnly { return }
            if maximumOutputCharacters > 0 && value.count > maximumOutputCharacters - output.count {
                throw TranslationEvaluationError(kind: .invalidState, message: "Interpolated output exceeds the maximum of \(maximumOutputCharacters) characters")
            }
            output.append(contentsOf: value)
        }
        func appendUnit(_ value: UInt16) throws {
            if collectOnly { return }
            if maximumOutputCharacters > 0 && output.count >= maximumOutputCharacters {
                throw TranslationEvaluationError(kind: .invalidState, message: "Interpolated output exceeds the maximum of \(maximumOutputCharacters) characters")
            }
            output.append(value)
        }
        func move(to next: String.UTF16View.Index) {
            position += units.distance(from: cursor, to: next)
            cursor = next
        }
        while cursor < units.endIndex {
            if units[cursor] == 92 {
                let next = units.index(after: cursor)
                if next < units.endIndex && units[next] == 92 {
                    try appendUnit(92); move(to: advance(next, by: 1)); continue
                }
                if pair(next, 123) {
                    guard let end = closing(advance(next, by: 2)) else {
                        try append(units[next...]); break
                    }
                    let after = advance(end, by: 2)
                    try append(units[next..<after]); move(to: after); continue
                }
                if pair(next, 125) {
                    try append("}}".utf16); move(to: advance(next, by: 2)); continue
                }
                try appendUnit(92); move(to: next); continue
            }
            if pair(cursor, 125) {
                if strict { throw TranslationEvaluationError(kind: .invalidArgument, message: "Unexpected placeholder closing delimiter '}}' at index \(position)") }
                try append("}}".utf16); move(to: advance(cursor, by: 2)); continue
            }
            if !pair(cursor, 123) {
                try appendUnit(units[cursor]); move(to: units.index(after: cursor)); continue
            }
            guard let end = closing(advance(cursor, by: 2)) else {
                if strict { throw TranslationEvaluationError(kind: .invalidArgument, message: "Unclosed placeholder starting at index \(position)") }
                try append(units[cursor...]); break
            }
            let after = advance(end, by: 2)
            let name = String(decoding: units[advance(cursor, by: 2)..<end], as: UTF16.self)
            guard IdentifierRules.isIdentifier(name) else {
                if strict {
                    throw TranslationEvaluationError(kind: .invalidArgument, message: "Malformed placeholder '{{\(name)}}'. Placeholder names must start with a Unicode letter or underscore and contain only Unicode letters, Unicode numbers, Unicode combining marks, underscores, or hyphens")
                }
                try append(units[cursor..<after]); move(to: after); continue
            }
            let exactName = ExactString(name)
            let remaining = maximumOutputCharacters == 0 ? -1 : maximumOutputCharacters - output.count
            if let value = try replacement(exactName, remaining) {
                try append(value.utf16)
            } else {
                if seen.insert(exactName).inserted { unresolved.append(exactName) }
                try append("{{".utf16); try append(name.utf16); try append("}}".utf16)
            }
            move(to: after)
        }
        return .init(value: String(decoding: output, as: UTF16.self), unresolvedPlaceholderNames: unresolved)
    }
}
