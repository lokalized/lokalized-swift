import Foundation
import SwiftUI
import Darwin
import Lokalized

@MainActor
final class CatalogState: ObservableObject {
    @Published var english = ""
    @Published var french = ""
    @Published var selected = ""
    @Published var problem: String?
    private var strings: DefaultStrings?
    private var display: StringsDisplayAdapter?

    init() {
        do {
            let loaded = try LocalizedStringLoader.loadFromBundle(.main)
            let catalogs = loaded.mapValues { LocalizedCatalog(strings: $0.strings) }
            let en = try LocaleTag("en"), fr = try LocaleTag("fr")
            let strings = try DefaultStrings(configuration: StringsConfiguration(
                localizedStringSupplier: { catalogs }, localeSupplier: { _ in en }, fallbackLocale: en))
            self.strings = strings
            let display = StringsDisplayAdapter(strings, errorDisplayPolicy: .returnString("Translation unavailable"))
            self.display = display
            english = try display.get("welcome", placeholders: ["name": .text("Ada")], options: .forLocale(en))
            french = try display.get("welcome", placeholders: ["name": .text("Ada")], options: .forLocale(fr))
            let preferred = try PreferredLanguageChooser.chooseAppleLocale(using: strings)
            selected = display.get("welcome", placeholders: ["name": .text("Ada")], options: .forLocaleMatch(preferred))
        } catch { problem = "Catalogs could not be loaded: \(error)" }
    }

    func select(_ language: String) {
        guard let display else { return }
        do {
            let options = try TranslationOptions.forLocale(language)
            selected = display.get("welcome", placeholders: ["name": .text("Ada")], options: options)
        } catch { problem = "Language could not be selected: \(error)" }
    }

    func qualify() throws {
        if let problem { throw SampleError(message: problem) }
        guard let strings else { throw SampleError(message: "Runtime was not constructed") }
        guard english == "Hello, Ada!", french == "Bonjour, Ada !" else { throw SampleError(message: "Independent locales differ") }
        let keys = try strings.getKeysForLocale(LocaleTag("en"))
        guard keys.contains("é"), keys.contains("e\u{0301}") else { throw SampleError(message: "Exact keys were collapsed") }
        let result = try strings.getResult("items", placeholders: ["count": .integer(2)], options: .forLocale(LocaleTag("fr")))
        guard result.translation == "2 articles", result.resolvedLocale?.tag == "fr" else { throw SampleError(message: "French catalog did not supply plural translation") }
    }
}

private struct SampleError: Error { let message: String }

@main
struct CatalogApp: App {
    @StateObject private var state: CatalogState

    init() {
        let model = CatalogState()
        if CommandLine.arguments.contains("--qualify") {
            do {
                try model.qualify()
                print("Packaged Apple catalogs passed")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Catalog qualification failed: \(error)\n".utf8))
                exit(1)
            }
        }
        _state = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: state.english)
                Text(verbatim: state.french)
                Text(verbatim: state.selected)
                HStack {
                    Button("English") { state.select("en") }
                    Button("Français") { state.select("fr") }
                }
                if let problem = state.problem { Text(verbatim: problem) }
            }.padding()
        }
    }
}
