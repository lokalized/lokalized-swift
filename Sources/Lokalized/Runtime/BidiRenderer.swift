/// Caller text conversion for one interpolated template. A renderer is never
/// shared between templates; isolated values are materialized once per name.
package final class BidiRenderer {
    private let isolatesValues: Bool
    private let maximumOutputCharacters: Int
    private var renderedValues: [ExactString: String] = [:]

    package init(locale: LocaleTag, isolation: BidiIsolation, limits: TranslationRuntimeLimits) {
        switch isolation {
        case .disabled: isolatesValues = false
        case .always: isolatesValues = true
        case .rtlLocales: isolatesValues = locale.isRightToLeft
        }
        maximumOutputCharacters = limits.maximumInterpolatedOutputCharacters
    }

    package func render(name: ExactString, value: PlaceholderValue, remaining: Int) throws -> String? {
        if value.isMissing { return nil }
        guard isolatesValues else { return try value.interpolationText(maximumCharacters: remaining) }
        if let rendered = renderedValues[name] {
            try Self.checkLength(rendered, maximumCharacters: remaining, reportedMaximumCharacters: maximumOutputCharacters)
            return rendered
        }
        guard let text = try value.interpolationText(maximumCharacters: remaining) else { return nil }
        let rendered = try Self.isolate(text, maximumCharacters: remaining,
                                       reportedMaximumCharacters: maximumOutputCharacters)
        renderedValues[name] = rendered
        return rendered
    }

    /// A failure key uses caller values only, requested-locale directionality
    /// and lenient scanning. Any rendering error returns the exact original key.
    package static func failureKey(_ key: ExactString, values: [ExactString: PlaceholderValue],
                                   locale: LocaleTag, isolation: BidiIsolation,
                                   limits: TranslationRuntimeLimits) -> String {
        do {
            let renderer = Self(locale: locale, isolation: isolation, limits: limits)
            return try StringInterpolator.interpolate(key.string, strict: false,
                maximumOutputCharacters: limits.maximumInterpolatedOutputCharacters) { name, remaining in
                try renderer.render(name: name, value: values[name] ?? .null, remaining: remaining)
            }.value
        } catch {
            return key.string
        }
    }

    /// Wraps caller text in FSI/PDI, repairing stray pops and unclosed isolates.
    /// The bounded length check precedes both scanning and the balanced fast path.
    package static func isolate(_ value: String, maximumCharacters: Int = -1,
                                reportedMaximumCharacters: Int? = nil) throws -> String {
        guard maximumCharacters >= -1 else {
            throw TranslationEvaluationError(kind: .invalidArgument,
                message: "maximumCharacters must be non-negative or -1 for no limit")
        }
        let reported = reportedMaximumCharacters ?? maximumCharacters
        try checkLength(value, maximumCharacters: maximumCharacters, reportedMaximumCharacters: reported)
        guard !value.isEmpty else { return "" }
        if isIsolated(value) { return value }
        var output: [UInt16] = []
        output.reserveCapacity(min(maximumCharacters < 0 ? 256 : maximumCharacters, 256))
        func append(_ unit: UInt16) throws {
            if maximumCharacters >= 0 && output.count >= maximumCharacters { throw outputLimitExceeded(reported) }
            output.append(unit)
        }
        var depth = 0
        try append(0x2068)
        for unit in value.utf16 {
            if isInitiator(unit) { depth += 1; try append(unit) }
            else if unit == 0x2069 {
                if depth > 0 { depth -= 1; try append(unit) }
            } else { try append(unit) }
        }
        for _ in 0..<depth { try append(0x2069) }
        try append(0x2069)
        return String(decoding: output, as: UTF16.self)
    }

    private static func checkLength(_ value: String, maximumCharacters: Int, reportedMaximumCharacters: Int) throws {
        guard maximumCharacters >= -1 else {
            throw TranslationEvaluationError(kind: .invalidArgument,
                message: "maximumCharacters must be non-negative or -1 for no limit")
        }
        if maximumCharacters >= 0 {
            // A bounded prefix avoids scanning arbitrary caller text to discover
            // its full length before refusing an oversized replacement.
            let inspected = maximumCharacters == Int.max ? value.utf16.count : value.utf16.prefix(maximumCharacters + 1).count
            if inspected > maximumCharacters { throw outputLimitExceeded(reportedMaximumCharacters) }
        }
    }
    private static func isInitiator(_ unit: UInt16) -> Bool { unit == 0x2066 || unit == 0x2067 || unit == 0x2068 }
    private static func isIsolated(_ value: String) -> Bool {
        let units = value.utf16
        guard let first = units.first, isInitiator(first) else { return false }
        var depth = 0
        var index = units.startIndex
        while index < units.endIndex {
            let unit = units[index]
            if isInitiator(unit) { depth += 1 }
            else if unit == 0x2069 {
                depth -= 1
                if depth < 0 { return false }
                if depth == 0 && units.index(after: index) != units.endIndex { return false }
            }
            index = units.index(after: index)
        }
        return depth == 0
    }
    private static func outputLimitExceeded(_ maximum: Int) -> TranslationEvaluationError {
        .init(kind: .invalidState, message: "Interpolated output exceeds the maximum of \(maximum) characters")
    }
}
