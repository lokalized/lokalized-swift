import Foundation
import Lokalized

enum CatalogObservations {
    static func parse(_ row: BehavioralCase) throws -> JSONValue {
        guard let fixture = row.fixture else { throw ConformanceError("Parser case has no fixture") }
        let input = try row.input.checkedObject(at: "parse.input", allowed: ["file", "locale", "source"])
        let name = try input.string("file", at: "parse.input")
        let locale = try input.string("locale", at: "parse.input")
        let source = try input.string("source", at: "parse.input")
        let fields = try fixture.checkedObject(at: "fixture")
        let warnings = WarningRecorder()
        var keys: [String] = []
        var failure: (type: String, message: String)?
        do {
            let options = try loadingOptions(fields["loadingOptions"])
            let bytes = try fileBytes(name, fixture: fields, materialized: row.materializedFiles)
            let file = try LocalizedStringLoader.parse(bytes, locale: locale, source: source,
                                                      warningHandler: { warnings.append($0) }, loadingOptions: options)
            keys = file.strings.map(\.key).sorted().map(\.string)
        } catch {
            failure = try projectedError(error)
        }
        return .object([.test("parse", .object([
            .test("failed", .bool(failure != nil)),
            .test("failureType", failure.map { .string($0.type) } ?? .null),
            .test("failureMessage", failure.map { .string($0.message) } ?? .null),
            .test("keys", .array(keys.map(JSONValue.string))),
            .test("warnings", .array(warnings.snapshot.map(warningObservation)))
        ]))])
    }

    static func define(_ row: BehavioralCase) throws -> JSONValue {
        guard let fixture = row.fixture else { throw ConformanceError("Constructor case has no fixture") }
        let input = try row.input.checkedObject(at: "define.input", allowed: ["locale", "localizedString"])
        let locale = try input.string("locale", at: "define.input")
        let fields = try fixture.checkedObject(at: "fixture")
        let model: LocalizedString
        do {
            model = try buildLocalizedString(try input.value("localizedString", at: "define.input"))
        } catch let error as CatalogModelError {
            return .object([.test("define", .object([
                .test("built", .bool(false)), .test("catalogKeyPresent", .null), .test("contains", .null),
                .test("failureType", .string("java.lang.IllegalArgumentException")),
                .test("failureMessage", .string(String(describing: error)))
            ]))])
        }
        let options = try loadingOptions(fields["loadingOptions"])
        let file = try LocalizedStringLoader.parse(fileBytes(locale, fixture: fields, materialized: row.materializedFiles), locale: locale, source: locale, loadingOptions: options)
        let candidate = file.strings.first { $0.key == model.key }
        return .object([.test("define", .object([
            .test("built", .bool(true)), .test("catalogKeyPresent", .bool(candidate != nil)),
            .test("contains", .bool(candidate == model)), .test("failureType", .null), .test("failureMessage", .null)
        ]))])
    }

    static func fileBytes(_ name: String, fixture: [ExactString: JSONValue], materialized: [ExactString: Data]? = nil) throws -> Data {
        let key = ExactString(name)
        if let materialized {
            guard let data = materialized[key] else { throw ConformanceError("Missing materialized fixture file: \(name)") }
            return data
        }
        let base64 = try fixture.value("rawFilesBase64", at: "fixture").checkedObject(at: "fixture.rawFilesBase64")
        if let value = base64[key] {
            guard case .string(let text) = value, let data = Data(base64Encoded: text) else {
                throw ConformanceError("Invalid fixture byte encoding for \(name)")
            }
            return data
        }
        let raw = try fixture.value("rawFiles", at: "fixture").checkedObject(at: "fixture.rawFiles")
        if let value = raw[key] {
            guard case .string(let text) = value else { throw ConformanceError("Invalid fixture raw text for \(name)") }
            return Data(text.utf8)
        }
        let files = try fixture.value("files", at: "fixture").checkedObject(at: "fixture.files")
        guard let file = files[key] else { throw ConformanceError("Missing fixture file: \(name)") }
        return try FixtureJSONWriter.bytes(file)
    }

    static func loadingOptions(_ value: JSONValue?) throws -> LocalizedStringLoadingOptions {
        guard let value, case .object = value else {
            if case .some(.null) = value { return .defaults }
            if value == nil { return .defaults }
            throw ConformanceError("Fixture loadingOptions must be an object or null")
        }
        let fields = try value.checkedObject(at: "loadingOptions", allowed: [
            "maximumInputBytes", "maximumReaderCharacters", "maximumJsonNestingDepth", "maximumTotalInputBytes",
            "maximumLocalizedStringsFiles", "maximumTranslationNodes", "maximumWarnings", "maximumDiscoveryEntries"
        ])
        let defaults = LocalizedStringLoadingOptions.defaults
        func integer(_ name: String, default fallback: Int) throws -> Int {
            guard let value = fields[ExactString(name)] else { return fallback }
            guard case .number(let literal) = value, let integer = Int(literal) else { throw ConformanceError("Invalid integer loading option: \(name)") }
            return integer
        }
        return try .init(
            maximumInputBytes: integer("maximumInputBytes", default: defaults.maximumInputBytes),
            maximumReaderCharacters: integer("maximumReaderCharacters", default: defaults.maximumReaderCharacters),
            maximumJsonNestingDepth: integer("maximumJsonNestingDepth", default: defaults.maximumJsonNestingDepth),
            maximumTotalInputBytes: integer("maximumTotalInputBytes", default: defaults.maximumTotalInputBytes),
            maximumLocalizedStringsFiles: integer("maximumLocalizedStringsFiles", default: defaults.maximumLocalizedStringsFiles),
            maximumTranslationNodes: integer("maximumTranslationNodes", default: defaults.maximumTranslationNodes),
            maximumWarnings: integer("maximumWarnings", default: defaults.maximumWarnings),
            maximumDiscoveryEntries: integer("maximumDiscoveryEntries", default: defaults.maximumDiscoveryEntries)
        )
    }

    private static func projectedError(_ error: any Error) throws -> (type: String, message: String) {
        switch error {
        case let error as StringsParseError:
            return ("com.lokalized.LocalizedStringLoadingException", error.message)
        case let error as LocalizedStringLoadingOptions.ValidationError:
            return ("java.lang.IllegalArgumentException", String(describing: error))
        default: throw ConformanceError("Unmapped parser error: \(error)")
        }
    }

    private static func warningObservation(_ warning: LocalizedStringWarning) -> JSONValue {
        .object([
            .test("key", warning.key.map { .string($0.string) } ?? .null),
            .test("locale", warning.locale.map(JSONValue.string) ?? .null),
            .test("message", .string(warning.message)),
            // The oracle projects Java's Set through a TreeSet. Keep authored
            // category order in the public warning and its message.
            .test("missingLanguageForms", .array(warning.missingLanguageForms.map { ExactString($0) }.sorted().map { .string($0.string) })),
            .test("placeholder", warning.placeholder.map { .string($0.string) } ?? .null), .test("source", .string(warning.source)),
            .test("type", .string(warning.type.rawValue))
        ])
    }

    // This decoder invokes the native constructor door. It must not silently
    // turn invalid fixture shapes into constructor refusals that could pass.
    static func buildLocalizedString(_ value: JSONValue, key inheritedKey: ExactString? = nil) throws -> LocalizedString {
        if case .string(let translation) = value, let inheritedKey {
            return try LocalizedString(key: inheritedKey, translation: translation)
        }
        let fields = try value.checkedObject(at: "define.model", allowed: inheritedKey == nil
            ? ["key", "translation", "commentary", "placeholders", "alternatives"]
            : ["translation", "commentary", "placeholders", "alternatives"])
        let key = try inheritedKey ?? ExactString(fields.string("key", at: "define.model"))
        func optionalString(_ name: String) throws -> String? {
            guard let value = fields[ExactString(name)] else { return nil }
            if case .null = value { return nil }
            guard case .string(let string) = value else { throw ConformanceError("Malformed constructor fixture field: \(name)") }
            return string
        }
        var placeholders: [ExactString: PlaceholderDefinition] = [:]
        if let value = fields["placeholders"], case .null = value {} else if let value = fields["placeholders"] {
            for (name, body) in try value.checkedObject(at: "define.model.placeholders") {
                placeholders[name] = try buildPlaceholder(body)
            }
        }
        var alternatives: [LocalizedString] = []
        if let value = fields["alternatives"], case .null = value {} else if let value = fields["alternatives"] {
            guard case .array(let values) = value else { throw ConformanceError("Malformed constructor alternatives") }
            for value in values {
                let object = try value.checkedObject(at: "define.model.alternative")
                guard object.count == 1, let (expression, body) = object.first else { throw ConformanceError("Constructor alternative must contain exactly one expression") }
                alternatives.append(try buildLocalizedString(body, key: expression))
            }
        }
        return try LocalizedString(key: key, translation: optionalString("translation"), commentary: optionalString("commentary"),
                                   placeholderDefinitions: placeholders, alternatives: alternatives)
    }

    private static func buildPlaceholder(_ value: JSONValue) throws -> PlaceholderDefinition {
        let fields = try value.checkedObject(at: "define.model.placeholder", allowed: ["value", "range", "translations", "translation", "alternatives"])
        let formMode = ["value", "range", "translations"].contains { fields[ExactString($0)] != nil }
        let expressionMode = ["translation", "alternatives"].contains { fields[ExactString($0)] != nil }
        guard formMode != expressionMode else { throw ConformanceError("Constructor fixture mixes placeholder modes") }
        if expressionMode {
            let translation = try fields.string("translation", at: "define.model.placeholder")
            guard let value = fields["alternatives"] else { return .expression(ExpressionTranslation(translation: translation)) }
            guard case .array(let values) = value else { throw ConformanceError("Malformed constructor fragment alternatives") }
            let alternatives = try values.map { value in
                let object = try value.checkedObject(at: "define.model.fragmentAlternative")
                guard object.count == 1, let (expression, body) = object.first, case .string(let text) = body else {
                    throw ConformanceError("Constructor fragment alternative must contain one expression/string")
                }
                return ExpressionAlternative(expression: expression, translation: text)
            }
            return .expression(try ExpressionTranslation(translation: translation, alternatives: alternatives))
        }
        let translations = try fields.value("translations", at: "define.model.placeholder").checkedObject(at: "define.model.translations")
        var byForm: [LanguageFormValue: String] = [:]
        for (name, value) in translations {
            guard let form = LanguageFormValue(rawValue: name.string), case .string(let translation) = value else {
                throw ConformanceError("Invalid constructor language-form branch")
            }
            byForm[form] = translation
        }
        if let value = fields["value"] {
            guard fields["range"] == nil, case .string(let selector) = value else { throw ConformanceError("Invalid constructor value selector") }
            return .languageForm(LanguageFormTranslation(value: ExactString(selector), translationsByLanguageForm: byForm))
        }
        let range = try fields.value("range", at: "define.model.placeholder").checkedObject(at: "define.model.range", allowed: ["start", "end"])
        let selectedRange = LanguageFormTranslationRange(start: ExactString(try range.string("start", at: "define.model.range")),
                                                        end: ExactString(try range.string("end", at: "define.model.range")))
        return .languageForm(LanguageFormTranslation(range: selectedRange, translationsByLanguageForm: byForm))
    }
}

private final class WarningRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var warnings: [LocalizedStringWarning] = []
    func append(_ warning: LocalizedStringWarning) { lock.lock(); defer { lock.unlock() }; warnings.append(warning) }
    var snapshot: [LocalizedStringWarning] { lock.lock(); defer { lock.unlock() }; return warnings }
}
