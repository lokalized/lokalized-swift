import Foundation

public extension LocalizedStringLoader {
    /// Loads every catalog from an ordinary directory in the explicit bundle.
    /// Use `.copy("Lokalized")` in SwiftPM, or a folder reference in Xcode, to
    /// preserve the directory. No Apple localization selection participates.
    static func loadFromBundle(
        _ bundle: Bundle, directory: String = "Lokalized",
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> [LocaleTag: ParsedStringsFile] {
        let components = try resourceComponents(directory, description: "Bundle resource directory")
        let root = try resourceRoot(bundle)
        let location = components.reduce(root) { $0.appendingPathComponent($1) }
        return try loadFromDirectory(location, warningHandler: warningHandler, loadingOptions: loadingOptions)
    }

    /// Loads exact, bundle-relative paths under caller-specified locale tags.
    /// Filenames need not be locale tags; paths are used literally, including
    /// an explicit `.lproj` component. One aggregate budget covers the map.
    static func loadFromBundle(
        _ bundle: Bundle, resourcePathsByLocale: [LocaleTag: String],
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> [LocaleTag: ParsedStringsFile] {
        var paths: [LocaleTag: [String]] = [:]
        for locale in resourcePathsByLocale.keys.sorted(by: { ExactString($0.tag) < ExactString($1.tag) }) {
            paths[locale] = try resourceComponents(resourcePathsByLocale[locale]!, description: "Bundle resource path")
        }
        let root = try resourceRoot(bundle)
        let resources = paths.mapValues { components in
            components.reduce(root) { $0.appendingPathComponent($1) }
        }
        return try loadFromResources(resources, warningHandler: warningHandler, loadingOptions: loadingOptions)
    }

    private static func resourceRoot(_ bundle: Bundle) throws -> URL {
        guard let root = bundle.resourceURL, root.isFileURL else {
            throw LocalizedStringLoadingError(message: "Bundle '\(bundle.bundleURL.path)' has no local resource directory",
                source: bundle.bundleURL.path, kind: .invalidResource)
        }
        return root
    }

    private static func resourceComponents(_ path: String, description: String) throws -> [String] {
        // Scalar splitting preserves combining marks after slash/dot. These
        // are literal resource paths, not URLs or native localization queries.
        let components = path.unicodeScalars.split(omittingEmptySubsequences: false,
            whereSeparator: { $0.value == 47 }).map(String.init)
        guard !path.isEmpty, !path.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 92 }),
              components.allSatisfy({ !$0.isEmpty && ExactString($0) != "." && ExactString($0) != ".." }) else {
            throw LocalizedStringLoadingError(message: "\(description) '\(path)' must be a relative path with nonempty components and no '.' or '..' segments",
                source: path, kind: .invalidResource)
        }
        return components
    }
}
