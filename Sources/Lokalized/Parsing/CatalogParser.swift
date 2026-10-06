import Foundation

/// Source-aware catalog parsing and same-locale shard assembly.
public enum LocalizedStringLoader {
    /// Parses a UTF-8 JSON catalog into validated localized entries.
    ///
    /// The locale identifies the catalog; the source label is used in errors, warnings, and origin records.
    /// Loading options bound bytes, nesting, nodes, and warnings. Invalid content or exceeded limits throws `StringsParseError`.
    /// Warning callback errors propagate unchanged.
    public static func parse(
        _ input: Data, locale: String, source: String = "<input>",
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> ParsedStringsFile {
        let session = CatalogParsingSession(source: source, options: loadingOptions, warningHandler: warningHandler)
        try session.beginFile(source)
        return try session.parseBytes(input, locale: locale)
    }

    /// Parses JSON catalog text into validated localized entries.
    ///
    /// The locale identifies the catalog; the source label is used in errors, warnings, and origin records.
    /// The character limit counts UTF-16 code units. Invalid content or exceeded limits throws `StringsParseError`; warning callback errors propagate unchanged.
    public static func parse(
        _ input: String, locale: String, source: String = "<input>",
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> ParsedStringsFile {
        let session = CatalogParsingSession(source: source, options: loadingOptions, warningHandler: warningHandler)
        try session.beginFile(source)
        guard input.utf16.count <= loadingOptions.maximumReaderCharacters else {
            throw session.error("localized strings resource exceeds the maximum size of \(loadingOptions.maximumReaderCharacters) characters")
        }
        // No original bytes exist for a String input; do not fabricate a byte charge.
        return try session.parse(input, locale: locale)
    }

    /// Validates programmatically constructed entries as one catalog.
    /// Checks templates, expressions, forms, nodes, and warnings. Byte and JSON
    /// nesting limits apply to source parsing rather than typed definitions.
    /// Invalid definitions throw `StringsParseError`; warning callback errors propagate.
    public static func defineCatalog(
        _ strings: [LocalizedString], locale: String, source: String = "<defined>",
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> ParsedStringsFile {
        let session = CatalogParsingSession(source: source, options: loadingOptions, warningHandler: warningHandler)
        try session.beginFile(source)
        return try session.validate(strings, locale: locale, emitWarnings: true)
    }

    /// Deduplicates complete equal definitions, unions their origins and rejects
    /// conflicting definitions. The model budget applies after deduplication.
    public static func mergeParsedStringsFiles(
        _ files: [ParsedStringsFile], loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> ParsedStringsFile {
        let source = "<merged>"
        let session = CatalogParsingSession(source: source, options: loadingOptions, warningHandler: nil)
        guard let first = files.first else { throw session.error("merging requires at least one parsed strings file") }
        for file in files { try session.beginFile(file.sources.first ?? source) }
        let locale = try CatalogParsingLocale.normalize(first.locale, source: source)
        for file in files.dropFirst() {
            let other = try CatalogParsingLocale.normalize(file.locale, source: source)
            guard ExactString(other) == ExactString(locale) else {
                throw session.error("every input must be authored for one exact locale, but '\(locale)' and '\(other)' were both supplied. Matching primary language or script is not enough — plural and language-form selection depend on the exact tag.")
            }
        }
        var strings: [LocalizedString] = []
        var indexes: [ExactString: Int] = [:]
        var origins: [ExactString: [String]] = [:]
        var sources: [String] = []
        var warnings: [LocalizedStringWarning] = []
        for file in files {
            sources.append(contentsOf: file.sources)
            warnings.append(contentsOf: file.warnings)
            for string in file.strings {
                let incoming = file.originsByKey[string.key].flatMap { $0.isEmpty ? nil : $0 } ?? file.sources
                if let index = indexes[string.key] {
                    guard strings[index] == string else {
                        throw session.error("key '\(string.key)' is defined differently in \(list(origins[string.key] ?? [])) and \(list(incoming)). Merging shards never picks a winner; make the definitions identical or give them different keys.")
                    }
                    for origin in incoming where !(origins[string.key] ?? []).contains(where: { ExactString($0) == ExactString(origin) }) {
                        origins[string.key, default: []].append(origin)
                    }
                } else {
                    indexes[string.key] = strings.count
                    strings.append(string)
                    origins[string.key] = incoming
                }
            }
        }
        for warning in warnings { try session.admit(warning, deliver: false) }
        let validated = try session.validate(strings, locale: locale, emitWarnings: false)
        return .init(locale: locale, sources: sources, strings: validated.strings, originsByKey: origins, warnings: warnings)
    }
}

private func list(_ values: [String]) -> String { "[\(values.joined(separator: ", "))]" }

private struct ParsedCatalogNode {
    let model: LocalizedString
    let placeholderOrder: [ExactString]
    let alternatives: [ParsedCatalogNode]
}

/// One load's cumulative counters. Each resource has a distinct parsing session
/// so its returned warnings and source provenance remain local to that file.
package final class CatalogParsingBudget {
    package let options: LocalizedStringLoadingOptions
    package var files = 0
    package var inputBytes = 0
    package var translationNodes = 0
    package var warningCount = 0
    package var discoveryEntries = 0
    package init(options: LocalizedStringLoadingOptions) { self.options = options }
    package func discoverEntry(source: String) throws {
        guard discoveryEntries < options.maximumDiscoveryEntries else {
            throw StringsParseError(message: "\(source): localized strings load exceeds the aggregate maximum of \(options.maximumDiscoveryEntries) discovery entries", source: source)
        }
        discoveryEntries += 1
    }
}

package final class CatalogParsingSession {
    let source: String
    let options: LocalizedStringLoadingOptions
    let warningHandler: LocalizedStringWarningHandler?
    let budget: CatalogParsingBudget
    var warnings: [LocalizedStringWarning] = []
    private var validatedModelDepths: [ObjectIdentifier: Int] = [:]
    private var validatedModels: [ObjectIdentifier: ParsedCatalogNode] = [:]

    package init(source: String, options: LocalizedStringLoadingOptions, warningHandler: LocalizedStringWarningHandler?,
                 budget: CatalogParsingBudget? = nil) {
        self.source = source; self.options = options; self.warningHandler = warningHandler
        self.budget = budget ?? CatalogParsingBudget(options: options)
        precondition(self.budget.options == options, "A shared parsing budget requires the same loading options")
    }
    package func error(_ message: String, path: String? = nil, cause: (any Error)? = nil) -> StringsParseError {
        .init(message: "\(source): \(message)", source: source, path: path, cause: cause)
    }
    package func beginFile(_ label: String) throws {
        guard budget.files < options.maximumLocalizedStringsFiles else {
            throw StringsParseError(message: "\(label): localized strings load exceeds the aggregate localized strings file limit of \(options.maximumLocalizedStringsFiles)", source: label)
        }
        budget.files += 1
    }
    package func addInputBytes(_ count: Int) throws {
        guard count >= 0 && count <= options.maximumTotalInputBytes - budget.inputBytes else {
            throw error("localized strings load exceeds the aggregate maximum of \(options.maximumTotalInputBytes) input bytes")
        }
        budget.inputBytes += count
    }
    func addNodes(_ count: Int) throws {
        guard count >= 0 && count <= options.maximumTranslationNodes - budget.translationNodes else {
            throw error("localized strings load exceeds the aggregate maximum of \(options.maximumTranslationNodes) translation nodes")
        }
        budget.translationNodes += count
    }
    func admit(_ warning: LocalizedStringWarning, deliver: Bool = true) throws {
        guard budget.warningCount < options.maximumWarnings else {
            throw StringsParseError(message: "\(warning.source): localized strings load exceeds the aggregate maximum of \(options.maximumWarnings) warnings", source: warning.source)
        }
        budget.warningCount += 1
        warnings.append(warning)
        if deliver { try warningHandler?(warning) }
    }

    package func parseBytes(_ input: Data, locale: String, chargeInput: Bool = true) throws -> ParsedStringsFile {
        if chargeInput {
            // Java charges aggregate bytes in 8 KiB reads before the resource
            // refusal. Streams have already charged their actual bounded reads.
            let readable = min(input.count, options.maximumInputBytes + 1)
            let chunk = min(8_192, options.maximumInputBytes + 1)
            var offset = 0
            while offset < readable {
                let count = min(chunk, readable - offset)
                try addInputBytes(count); offset += count
            }
        }
        guard input.count <= options.maximumInputBytes else {
            throw error("localized strings resource exceeds the maximum size of \(options.maximumInputBytes) bytes")
        }
        let text: String
        do { text = try JSONReader.decodeUTF8(input) }
        catch { throw self.error("localized strings resource is not valid UTF-8", cause: error) }
        // maximumReaderCharacters applies only to String/character input.
        return try parse(text, locale: locale)
    }

    package func parse(_ input: String, locale: String) throws -> ParsedStringsFile {
        var text = input
        if text.unicodeScalars.first?.value == 0xFEFF { text = String(text.unicodeScalars.dropFirst()) }
        guard text.utf16.contains(where: { $0 != 32 && $0 != 9 && $0 != 10 && $0 != 13 }) else {
            throw error("a localized strings file may not be blank; use an empty JSON object ({}) for an empty file")
        }
        try checkNesting(text)
        let root: JSONValue
        do {
            root = try JSONReader.parse(text, limits: .init(maximumCharacters: max(1, text.utf16.count), maximumDepth: 128, maximumNodes: Int.max), allowLeadingBOM: false)
        } catch let cause as JSONReadError {
            throw StringsParseError(message: "\(source):\(cause.location.line):\(cause.location.column): unable to parse localized strings file",
                                    source: source, line: cause.location.line, column: cause.location.column, cause: cause)
        }
        guard case .object(let members) = root else {
            throw error("a localized strings file must be comprised of a single JSON object")
        }
        return try parseMembers(members, locale: locale)
    }

    func validate(_ strings: [LocalizedString], locale: String, emitWarnings: Bool) throws -> ParsedStringsFile {
        let normalized = try CatalogParsingLocale.normalize(locale, source: source)
        try addNodes(strings.count)
        var seen: Set<ExactString> = []
        var validated: [LocalizedString] = []
        var origins: [ExactString: [String]] = [:]
        for model in strings {
            guard seen.insert(model.key).inserted else { throw error("duplicate localized string key '\(model.key)' encountered") }
            let node = try validateModel(model, rootKey: model.key, path: model.key.string, depth: 0)
            if emitWarnings { try reportWarnings(node, rootKey: model.key, locale: normalized) }
            validated.append(node.model)
            origins[model.key] = [source]
        }
        return .init(locale: normalized, sources: [source], strings: validated, originsByKey: origins, warnings: warnings)
    }

    private func parseMembers(_ members: [JSONMember], locale: String, emitWarnings: Bool = true) throws -> ParsedStringsFile {
        let normalized = try CatalogParsingLocale.normalize(locale, source: source)
        try addNodes(members.count)
        var seen: Set<ExactString> = []
        var strings: [LocalizedString] = []
        var origins: [ExactString: [String]] = [:]
        for member in members {
            guard seen.insert(member.name).inserted else { throw error("duplicate localized string key '\(member.name)' encountered") }
            try checkDuplicates(member.value, path: boundedPath("$", ".", member.name.string, ""))
            let node = try parseNode(member.value, rootKey: member.name, key: member.name, path: member.name.string, depth: 0)
            if emitWarnings { try reportWarnings(node, rootKey: member.name, locale: normalized) }
            strings.append(node.model)
            origins[member.name] = [source]
        }
        return .init(locale: normalized, sources: [source], strings: strings, originsByKey: origins, warnings: warnings)
    }

    private func checkNesting(_ text: String) throws {
        var depth = 0, inside = false, escaped = false
        for unit in text.utf16 {
            if inside {
                if escaped { escaped = false }
                else if unit == 92 { escaped = true }
                else if unit == 34 { inside = false }
            } else if unit == 34 { inside = true }
            else if unit == 123 || unit == 91 {
                depth += 1
                if depth > options.maximumJsonNestingDepth { throw error("JSON nesting depth exceeds the maximum of \(options.maximumJsonNestingDepth)") }
            } else if unit == 125 || unit == 93 { depth -= 1 }
        }
    }

    private func checkDuplicates(_ value: JSONValue, path: String) throws {
        switch value {
        case .object(let members):
            var seen: Set<ExactString> = []
            for member in members {
                guard seen.insert(member.name).inserted else {
                    throw error("duplicate JSON object member '\(boundedValue(member.name.string))' encountered at \(path)", path: path)
                }
                try checkDuplicates(member.value, path: boundedPath(path, ".", member.name.string, ""))
            }
        case .array(let values):
            for (index, value) in values.enumerated() { try checkDuplicates(value, path: boundedPath(path, "[", String(index), "]")) }
        default: break
        }
    }

    private func parseNode(_ value: JSONValue, rootKey: ExactString, key: ExactString, path: String, depth: Int) throws -> ParsedCatalogNode {
        guard depth <= 128 else { throw error("alternative nesting exceeds the maximum depth of 128 for key '\(rootKey)'") }
        if case .string(let translation) = value {
            try references(translation, rootKey: rootKey, description: declaration("translation", rootKey: rootKey, path: path))
            return .init(model: try LocalizedString(key: key, translation: translation), placeholderOrder: [], alternatives: [])
        }
        guard case .object(let members) = value else { throw error("either a translation string or object value is required for key '\(key)'") }
        try unexpected(members, key: key, description: "localized string", allowed: ["translation", "commentary", "placeholders", "alternatives"])
        let fields = dictionary(members)
        var translation: String?, commentary: String?
        if let value = fields["translation"] {
            guard case .string(let text) = value else { throw error("translation must be a string for key '\(key)'") }
            translation = text
        }
        if let value = fields["commentary"] {
            guard case .string(let text) = value else { throw error("commentary must be a string for key '\(key)'") }
            commentary = text
        }
        var placeholders: [ExactString: PlaceholderDefinition] = [:]
        var placeholderOrder: [ExactString] = []
        if let value = fields["placeholders"] {
            guard case .object(let definitions) = value else { throw error("the placeholders value must be an object. Key is '\(key)'") }
            for definition in definitions {
                try addNodes(1)
                try identifier(definition.name.string, key: key, description: "placeholder")
                guard case .object(let shape) = definition.value else { throw error("the placeholder value must be an object. Key is '\(key)'") }
                placeholders[definition.name] = try placeholder(shape, rootKey: rootKey, placeholderKey: definition.name, path: path)
                placeholderOrder.append(definition.name)
            }
        }
        var alternatives: [ParsedCatalogNode] = []
        if let value = fields["alternatives"] {
            guard case .array(let values) = value else { throw error("alternatives must be an array. Key is '\(key)'") }
            guard !values.isEmpty else { throw error("alternatives must contain at least one expression. Key is '\(key)'") }
            for value in values {
                try addNodes(1)
                if case .null = value { throw error("alternative values cannot be null. Key is '\(key)'") }
                guard case .object(let expressions) = value else { throw error("alternative value must be an object. Key is '\(key)'") }
                guard !expressions.isEmpty else { throw error("alternative objects must contain at least one expression. Key is '\(key)'") }
                guard expressions.count == 1, let expression = expressions.first else {
                    throw error("each alternative object must contain exactly one expression so array order defines first-match precedence. Key is '\(key)'")
                }
                try compile(expression.name.string, description: "unable to parse whole-message alternative expression '\(expression.name)' for root key '\(rootKey)'")
                alternatives.append(try parseNode(expression.value, rootKey: rootKey, key: expression.name,
                                                  path: boundedPath(path, " -> alternative[", expression.name.string, "]"), depth: depth + 1))
            }
        }
        guard translation != nil || !alternatives.isEmpty else {
            throw error("either a translation or at least one alternative expression is required for key '\(key)'")
        }
        if let translation { try references(translation, rootKey: rootKey, description: declaration("translation", rootKey: rootKey, path: path)) }
        return .init(model: try LocalizedString(key: key, translation: translation, commentary: commentary,
                                               placeholderDefinitions: placeholders, placeholderDefinitionOrder: placeholderOrder,
                                               alternatives: alternatives.map(\.model)),
                     placeholderOrder: placeholderOrder, alternatives: alternatives)
    }

    private func placeholder(_ members: [JSONMember], rootKey: ExactString, placeholderKey: ExactString, path: String) throws -> PlaceholderDefinition {
        try unexpected(members, key: rootKey, description: "placeholder '\(placeholderKey)'", allowed: ["value", "range", "translations", "translation", "alternatives"])
        let fields = dictionary(members)
        let form = fields["value"] != nil || fields["range"] != nil || fields["translations"] != nil
        let template = fields["translation"] != nil || fields["alternatives"] != nil
        if form && template { throw error("placeholder '\(placeholderKey)' for root key '\(rootKey)' mixes language-form members [value, range, translations] with template members [translation, alternatives]; placeholder modes are mutually exclusive") }
        guard form || template else { throw error("placeholder '\(placeholderKey)' for root key '\(rootKey)' must define either a language-form translation or a template translation") }
        return template ? try fragment(fields, rootKey: rootKey, placeholderKey: placeholderKey, path: path)
                        : try languageForm(fields, rootKey: rootKey, placeholderKey: placeholderKey, path: path)
    }

    private func languageForm(_ fields: [ExactString: JSONValue], rootKey: ExactString, placeholderKey: ExactString, path: String) throws -> PlaceholderDefinition {
        for member in ["value", "range", "translations"] {
            if case .null = fields[ExactString(member)] { throw error("placeholder member '\(member)' may not be null. Placeholder is '\(placeholderKey)' for key '\(rootKey)'") }
        }
        let rawValue = fields["value"], rawRange = fields["range"]
        guard rawValue != nil || rawRange != nil else { throw error("a placeholder translation value or range is required. Key is '\(rootKey)'") }
        guard rawValue == nil || rawRange == nil else { throw error("a placeholder translation cannot have both a value and a range. Key is '\(rootKey)'") }
        var selector: ExactString?, range: LanguageFormTranslationRange?
        if let rawRange {
            guard case .object(let members) = rawRange else { throw error("the placeholder translation range must be an object. Key is '\(rootKey)'") }
            try unexpected(members, key: rootKey, description: "range for placeholder '\(placeholderKey)'", allowed: ["start", "end"])
            let endpoints = dictionary(members)
            for name in ["start", "end"] {
                if endpoints[ExactString(name)] == nil || endpoints[ExactString(name)].isNull { throw error("a placeholder translation range \(name) is required. Key is '\(rootKey)'") }
            }
            guard case .string(let start) = endpoints["start"] else { throw error("a placeholder translation range start must be a string. Key is '\(rootKey)'") }
            guard case .string(let end) = endpoints["end"] else { throw error("a placeholder translation range end must be a string. Key is '\(rootKey)'") }
            try identifier(start, key: rootKey, description: "range start"); try identifier(end, key: rootKey, description: "range end")
            range = .init(start: ExactString(start), end: ExactString(end))
        } else {
            guard case .string(let text) = rawValue else { throw error("a placeholder translation value must be a string. Key is '\(rootKey)'") }
            try identifier(text, key: rootKey, description: "placeholder value"); selector = ExactString(text)
        }
        guard let translationsValue = fields["translations"] else { throw error("placeholder translations are required. Key is '\(rootKey)'") }
        guard case .object(let members) = translationsValue else { throw error("the placeholder translations value must be an object. Key is '\(rootKey)'") }
        var translations: [LanguageFormValue: String] = [:]
        var axes: Set<LanguageFormAxis> = []
        for member in members {
            guard let form = formByName[member.name] else {
                throw error("unexpected placeholder translation language form encountered. Key is '\(rootKey)'. You provided '\(member.name)', valid values are \(list(validFormNames))")
            }
            guard case .string(let text) = member.value else { throw error("the placeholder translation value must be a string. Key is '\(rootKey)'") }
            try references(text, rootKey: rootKey, description: declaration("placeholder translation for generated placeholder '\(placeholderKey)'", rootKey: rootKey, path: path))
            translations[form] = text; axes.insert(form.axis)
        }
        guard !translations.isEmpty else { throw error("placeholder translations are required. Key is '\(rootKey)'") }
        guard axes.count <= 1 else { throw error("you cannot mix-and-match language forms in placeholder translations. Placeholder is '\(placeholderKey)' for key '\(rootKey)'") }
        if let range {
            guard axes == [.cardinality] else { throw error("range-based translations only support Cardinality. Placeholder is '\(placeholderKey)' for key '\(rootKey)'") }
            return .languageForm(.init(range: range, translationsByLanguageForm: translations))
        }
        return .languageForm(.init(value: selector!, translationsByLanguageForm: translations))
    }

    private func fragment(_ fields: [ExactString: JSONValue], rootKey: ExactString, placeholderKey: ExactString, path: String) throws -> PlaceholderDefinition {
        guard let value = fields["translation"] else { throw error("a default template translation is required for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
        if case .null = value { throw error("default template translation may not be null for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
        guard case .string(let text) = value else { throw error("default template translation must be a string for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
        try references(text, rootKey: rootKey, description: declaration("default fragment for generated placeholder '\(placeholderKey)'", rootKey: rootKey, path: path))
        guard let alternativesValue = fields["alternatives"] else { return .expression(.init(translation: text)) }
        if case .null = alternativesValue { throw error("fragment alternatives may not be null for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
        guard case .array(let values) = alternativesValue else { throw error("fragment alternatives must be an array for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
        guard !values.isEmpty else { throw error("fragment alternatives must contain at least one expression for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
        var alternatives: [ExpressionAlternative] = []
        for (index, value) in values.enumerated() {
            try addNodes(1)
            if case .null = value { throw error("fragment alternative \(index) may not be null for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
            guard case .object(let members) = value else { throw error("fragment alternative \(index) must be an object for placeholder '\(placeholderKey)' in root key '\(rootKey)'") }
            guard members.count == 1, let member = members.first else { throw error("fragment alternative \(index) must contain exactly one expression so array order defines first-match precedence. Placeholder is '\(placeholderKey)' in root key '\(rootKey)'") }
            guard case .string(let translation) = member.value else { throw error("fragment alternative \(index) for expression '\(member.name)' must have a string result. Placeholder is '\(placeholderKey)' in root key '\(rootKey)'") }
            try compile(member.name.string, description: "unable to parse fragment alternative \(index) expression '\(member.name)' for placeholder '\(placeholderKey)' in root key '\(rootKey)'")
            try references(translation, rootKey: rootKey, description: declaration("fragment alternative \(index) for expression '\(member.name)' and generated placeholder '\(placeholderKey)'", rootKey: rootKey, path: path))
            alternatives.append(.init(expression: member.name, translation: translation))
        }
        return .expression(try .init(translation: text, alternatives: alternatives))
    }

    private func unexpected(_ members: [JSONMember], key: ExactString, description: String, allowed: [String]) throws {
        let names = Set(allowed.map { ExactString($0) })
        for member in members where !names.contains(member.name) {
            throw error("unexpected field '\(member.name)' in \(description) for key '\(key)'. Valid fields are \(list(allowed.sorted()))")
        }
    }
    private func identifier(_ name: String, key: ExactString, description: String) throws {
        guard IdentifierRules.isIdentifier(name) else {
            throw error("invalid \(description) '\(name)'. Placeholder names must start with a Unicode letter or underscore and contain only Unicode letters, Unicode numbers, Unicode combining marks, underscores, or hyphens. Key is '\(key)'")
        }
        if formByName[ExactString(name)] != nil { throw error("invalid \(description) '\(name)'. Placeholder names may not use reserved expression constants. Key is '\(key)'") }
    }
    private func compile(_ expression: String, description: String) throws {
        do { try ExpressionCompiler.validate(expression) }
        catch { throw self.error("\(description): \(String(describing: error))", cause: error) }
    }
    private func declaration(_ description: String, rootKey: ExactString, path: String) -> String {
        ExactString(path) == rootKey ? description : "\(description) declared at \(path)"
    }

    private func references(_ text: String, rootKey: ExactString, description: String) throws {
        let units = Array(text.utf16)
        var cursor = 0
        func pair(_ at: Int, _ unit: UInt16) -> Bool { at + 1 < units.count && units[at] == unit && units[at + 1] == unit }
        func close(_ start: Int) -> Int? {
            var index = start
            while index + 1 < units.count { if pair(index, 125) { return index }; index += 1 }
            return nil
        }
        func failure(_ reason: String) -> StringsParseError { error("invalid placeholder reference in \(description) for key '\(rootKey)': \(reason)") }
        while cursor < units.count {
            if units[cursor] == 92 {
                if cursor + 1 < units.count && units[cursor + 1] == 92 { cursor += 2; continue }
                if pair(cursor + 1, 123) {
                    guard let end = close(cursor + 3) else { break }
                    cursor = end + 2; continue
                }
                if pair(cursor + 1, 125) { cursor += 3; continue }
                cursor += 1; continue
            }
            if pair(cursor, 125) { throw failure("Unexpected placeholder closing delimiter '}}' at index \(cursor)") }
            guard pair(cursor, 123) else { cursor += 1; continue }
            guard let end = close(cursor + 2) else { throw failure("Unclosed placeholder starting at index \(cursor)") }
            let name = String(decoding: units[(cursor + 2)..<end], as: UTF16.self)
            guard IdentifierRules.isIdentifier(name) else {
                throw failure("Malformed placeholder '{{\(name)}}'. Placeholder names must start with a Unicode letter or underscore and contain only Unicode letters, Unicode numbers, Unicode combining marks, underscores, or hyphens")
            }
            try identifier(name, key: rootKey, description: "\(description) placeholder reference")
            cursor = end + 2
        }
    }

    private func reportWarnings(_ node: ParsedCatalogNode, rootKey: ExactString, locale: String) throws {
        var visited: Set<ObjectIdentifier> = []
        try walkWarnings(node, rootKey: rootKey, locale: locale, visited: &visited)
    }

    private func walkWarnings(_ node: ParsedCatalogNode, rootKey: ExactString, locale: String, visited: inout Set<ObjectIdentifier>) throws {
        guard visited.insert(node.model.storageIdentity).inserted else { return }
        for name in node.placeholderOrder {
            guard case .languageForm(let definition) = node.model.placeholderDefinitions[name], definition.range == nil else { continue }
            for axis in [LanguageFormAxis.cardinality, .ordinality] {
                let provided = Set(definition.translationsByLanguageForm.keys.filter { $0.axis == axis }.map(\.rawValue))
                guard !provided.isEmpty else { continue }
                let supported = try CatalogWarningForms.supported(locale: locale, axis: axis)
                let missing = supported.filter { !provided.contains($0) }
                guard !missing.isEmpty else { continue }
                let axisName = axis == .cardinality ? "Cardinality" : "Ordinality"
                let message = "\(source): placeholder '\(name)' for key '\(rootKey)' is missing \(axisName) translation[s] for locale '\(locale)': \(list(missing)). Supported forms are \(list(supported)). Values that resolve to a missing form are treated as resolution failures at runtime."
                try admit(.init(type: axis == .cardinality ? .incompleteCardinalityTranslations : .incompleteOrdinalityTranslations,
                                source: source, locale: locale, key: rootKey, placeholder: name, missingLanguageForms: missing, message: message))
            }
        }
        for alternative in node.alternatives { try walkWarnings(alternative, rootKey: rootKey, locale: locale, visited: &visited) }
    }

    private func validateModel(_ model: LocalizedString, rootKey: ExactString, path: String, depth: Int) throws -> ParsedCatalogNode {
        guard depth <= 128 else { throw error("alternative nesting exceeds the maximum depth of 128 for key '\(rootKey)'") }
        let identity = model.storageIdentity
        if let deepest = validatedModelDepths[identity], deepest >= depth, let cached = validatedModels[identity] { return cached }
        // Validate directly, never expand the entire value graph into JSON before
        // charging its nodes. A shared COW subtree can otherwise expand to 2^depth
        // allocations before the model budget gets a chance to refuse it.
        let names = model.placeholderDefinitionOrder
        for name in names {
            try addNodes(1)
            try identifier(name.string, key: model.key, description: "placeholder")
            let definition = model.placeholderDefinitions[name]!
            try validateModelPlaceholder(definition, rootKey: rootKey, placeholderKey: name, path: path)
        }
        var children: [ParsedCatalogNode] = []
        for alternative in model.alternatives {
            try addNodes(1)
            try compile(alternative.key.string, description: "unable to parse whole-message alternative expression '\(alternative.key)' for root key '\(rootKey)'")
            children.append(try validateModel(alternative, rootKey: rootKey,
                                              path: boundedPath(path, " -> alternative[", alternative.key.string, "]"), depth: depth + 1))
        }
        if let translation = model.translation {
            try references(translation, rootKey: rootKey, description: declaration("translation", rootKey: rootKey, path: path))
        }
        let parsed = ParsedCatalogNode(model: model, placeholderOrder: names, alternatives: children)
        validatedModelDepths[identity] = depth
        validatedModels[identity] = parsed
        return parsed
    }

    private func validateModelPlaceholder(_ definition: PlaceholderDefinition, rootKey: ExactString, placeholderKey: ExactString, path: String) throws {
        switch definition {
        case .languageForm(let form):
            if let value = form.value { try identifier(value.string, key: rootKey, description: "placeholder value") }
            if let range = form.range {
                try identifier(range.start.string, key: rootKey, description: "range start")
                try identifier(range.end.string, key: rootKey, description: "range end")
            }
            var axes: Set<LanguageFormAxis> = []
            for key in form.translationsByLanguageForm.keys.sorted(by: { ExactString($0.rawValue) < ExactString($1.rawValue) }) {
                try references(form.translationsByLanguageForm[key]!, rootKey: rootKey,
                               description: declaration("placeholder translation for generated placeholder '\(placeholderKey)'", rootKey: rootKey, path: path))
                axes.insert(key.axis)
            }
            guard !form.translationsByLanguageForm.isEmpty else { throw error("placeholder translations are required. Key is '\(rootKey)'") }
            guard axes.count == 1 else { throw error("you cannot mix-and-match language forms in placeholder translations. Placeholder is '\(placeholderKey)' for key '\(rootKey)'") }
            if form.range != nil && axes != [.cardinality] { throw error("range-based translations only support Cardinality. Placeholder is '\(placeholderKey)' for key '\(rootKey)'") }
        case .expression(let expression):
            try references(expression.translation, rootKey: rootKey,
                           description: declaration("default fragment for generated placeholder '\(placeholderKey)'", rootKey: rootKey, path: path))
            for (index, alternative) in expression.alternatives.enumerated() {
                try addNodes(1)
                try compile(alternative.expression.string,
                            description: "unable to parse fragment alternative \(index) expression '\(alternative.expression)' for placeholder '\(placeholderKey)' in root key '\(rootKey)'")
                try references(alternative.translation, rootKey: rootKey,
                               description: declaration("fragment alternative \(index) for expression '\(alternative.expression)' and generated placeholder '\(placeholderKey)'", rootKey: rootKey, path: path))
            }
        }
    }
}

private func dictionary(_ members: [JSONMember]) -> [ExactString: JSONValue] {
    Dictionary(members.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
}
private extension Optional where Wrapped == JSONValue {
    var isNull: Bool { if case .null = self { true } else { false } }
}
private func boundedValue(_ value: String) -> String {
    let units = Array(value.utf16.prefix(257))
    return units.count <= 256 ? value : String(decoding: units.prefix(255), as: UTF16.self) + "…"
}
private func boundedPath(_ parent: String, _ prefix: String, _ component: String, _ suffix: String) -> String {
    var units = Array(parent.utf16.prefix(4_096))
    for part in [prefix, component, suffix] {
        let remaining = 4_096 - units.count
        guard remaining > 0 else { break }
        let addition = Array(part.utf16.prefix(remaining + 1))
        if addition.count <= remaining { units.append(contentsOf: addition) }
        else { units.append(contentsOf: addition.prefix(remaining - 1)); units.append(0x2026) }
    }
    return String(decoding: units, as: UTF16.self)
}
private let validFormNames: [String] = {
    var names: [String] = []
    names.append(contentsOf: Gender.allCases.map(\.rawValue)); names.append(contentsOf: GrammaticalCase.allCases.map(\.rawValue))
    names.append(contentsOf: Definiteness.allCases.map(\.rawValue)); names.append(contentsOf: Classifier.allCases.map(\.rawValue))
    names.append(contentsOf: Formality.allCases.map(\.rawValue)); names.append(contentsOf: Clusivity.allCases.map(\.rawValue))
    names.append(contentsOf: Animacy.allCases.map(\.rawValue)); names.append(contentsOf: Cardinality.allCases.map(\.rawValue))
    names.append(contentsOf: Ordinality.allCases.map(\.rawValue)); names.append(contentsOf: Phonetic.allCases.map(\.rawValue))
    return names
}()
private let formByName = Dictionary(uniqueKeysWithValues: LanguageFormValue.allValues.map { (ExactString($0.rawValue), $0) })

/// Public catalog ingress uses the shared strict JDK projection. CLDR aliases
/// affect category lookup, rather than collapsing authored catalog identities.
private enum CatalogParsingLocale {
    static func normalize(_ input: String, source: String) throws -> String {
        do {
            guard !input.isEmpty else { throw LocaleTagError(.malformedLanguageTag, "Empty catalog locale") }
            return try LocaleTag(input).tag
        } catch is LocaleTagError {
            throw StringsParseError(message: "\(source): invalid locale tag '\(input)'", source: source)
        }
    }
}

private enum CatalogWarningForms {
    static func supported(locale: String, axis: LanguageFormAxis) throws -> [String] {
        switch axis {
        case .cardinality: return try Cardinality.supportedCardinalitiesForLocale(locale).map(\.rawValue)
        case .ordinality: return try Ordinality.supportedOrdinalitiesForLocale(locale).map(\.rawValue)
        default: return []
        }
    }
}
