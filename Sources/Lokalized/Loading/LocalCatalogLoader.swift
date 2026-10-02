import Foundation
import Darwin

extension LocalizedStringLoader {
    /// Reads from the current position, opening a not-yet-open stream. The caller
    /// retains ownership: this method never closes the supplied stream.
    public static func parse(
        _ input: InputStream, locale: String, source: String = "<input>",
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> ParsedStringsFile {
        let locale = try LocaleTag(locale)
        let session = CatalogParsingSession(source: source, options: loadingOptions, warningHandler: warningHandler)
        try session.beginFile(source)
        if input.streamStatus == .notOpen { input.open() }
        let data = try LocalCatalogLoader.read(session: session) { buffer, count in
            let read = input.read(buffer, maxLength: count)
            guard read >= 0 else {
                throw LocalizedStringLoadingError(message: "Unable to load localized strings resource contents for \(source)",
                                                  source: source, cause: input.streamError ?? LocalCatalogLoader.posixError())
            }
            return read
        }
        return try session.parseBytes(data, locale: locale.tag, chargeInput: false)
    }

    /// Opens and closes an owned regular file, following symbolic links. Source
    /// provenance records the canonical path rather than the link's spelling.
    public static func parse(
        file: URL, locale: String,
        warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> ParsedStringsFile {
        let locale = try LocaleTag(locale)
        try LocalCatalogLoader.requireFileURL(file)
        return try LocalCatalogLoader.parseFile(file, locale: locale, warningHandler: warningHandler,
                                               budget: .init(options: loadingOptions))
    }

    /// Scans only actual immediate entries. Discovery is bounded before selected
    /// resources are processed in UTF-8 byte order.
    public static func loadFromDirectory(
        _ directory: URL, warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> [LocaleTag: ParsedStringsFile] {
        try LocalCatalogLoader.requireFileURL(directory)
        return try LocalCatalogLoader.loadDirectory(directory, warningHandler: warningHandler, options: loadingOptions)
    }

    /// Loads exactly the explicit mappings, with one cumulative loading budget.
    /// Every mapping is validated before any resource is opened.
    public static func loadFromResources(
        _ resources: [LocaleTag: URL], warningHandler: LocalizedStringWarningHandler? = nil,
        loadingOptions: LocalizedStringLoadingOptions = .defaults
    ) throws -> [LocaleTag: ParsedStringsFile] {
        let source = "explicit resource mapping"
        guard resources.count <= loadingOptions.maximumLocalizedStringsFiles else {
            throw LocalizedStringLoadingError(message: "Resource mapping contains \(resources.count) localized strings files, exceeding the aggregate localized strings file limit of \(loadingOptions.maximumLocalizedStringsFiles)",
                                              source: source, kind: .invalidResource)
        }
        let entries = resources.sorted {
            if $0.key.tag == $1.key.tag { return LocalCatalogLoader.utf8Less($0.key.javaIdentifier, $1.key.javaIdentifier) }
            return LocalCatalogLoader.utf8Less($0.key.tag, $1.key.tag)
        }
        var rendered: [ExactString: URL] = [:]
        for (locale, url) in entries {
            try JDKLocaleTag.requireWellFormed(locale, description: "Locale key")
            try LocalCatalogLoader.requireFileURL(url)
            if let previous = rendered.updateValue(url, forKey: ExactString(locale.tag)) {
                throw LocalizedStringLoadingError(message: "Duplicate localized strings resource mapping for locale '\(locale.tag)' found at '\(previous.path)' and '\(url.path)'",
                                                  source: source, kind: .duplicateLocale)
            }
        }
        let budget = CatalogParsingBudget(options: loadingOptions)
        var files: [LocaleTag: ParsedStringsFile] = [:]
        for (locale, url) in entries {
            files[locale] = try LocalCatalogLoader.parseFile(url, locale: locale, warningHandler: warningHandler, budget: budget)
        }
        try LocalCatalogLoader.requireUniqueRenderedLocales(files, source: source)
        return files
    }
}

package enum LocalCatalogLoader {
    static func utf8Less(_ first: String, _ second: String) -> Bool { first.utf8.lexicographicallyPrecedes(second.utf8) }
    static func posixError(_ code: Int32 = errno) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    static func requireFileURL(_ url: URL) throws {
        guard url.isFileURL else {
            throw LocalizedStringLoadingError(message: "Localized strings resource URL must be a file URL: \(url.absoluteString)",
                                              source: url.absoluteString, kind: .invalidResource)
        }
        guard url.host == nil || url.host == "" || url.host == "localhost" else {
            throw LocalizedStringLoadingError(message: "Localized strings resource URL must identify a local file: \(url.absoluteString)",
                                              source: url.absoluteString, kind: .invalidResource)
        }
        // NUL would silently truncate POSIX paths, changing the selected resource.
        guard !url.path.utf8.contains(0) else {
            throw LocalizedStringLoadingError(message: "Localized strings resource path must not contain a NUL character",
                                              source: url.path, kind: .invalidResource)
        }
    }
    static func isDirectory(_ path: [UInt8]) -> Bool {
        var metadata = stat()
        let terminated = path + [0]
        return terminated.withUnsafeBytes {
            fstatat(AT_FDCWD, $0.baseAddress!.assumingMemoryBound(to: CChar.self), &metadata, 0)
        } == 0 && metadata.st_mode & S_IFMT == S_IFDIR
    }
    static func canonicalPath(_ path: String) throws -> String {
        guard let resolved = path.withCString({ realpath($0, nil) }) else {
            throw LocalizedStringLoadingError(message: "Unable to determine canonical path for localized strings file \(path)",
                                              source: path, cause: posixError())
        }
        defer { free(resolved) }
        let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(resolved).assumingMemoryBound(to: UInt8.self),
                                        count: strlen(resolved))
        return try decodeCanonicalPath(bytes, source: path)
    }
    package static func decodeCanonicalPath(_ bytes: UnsafeBufferPointer<UInt8>, source: String) throws -> String {
        guard let canonical = String(bytes: bytes, encoding: .utf8) else {
            throw LocalizedStringLoadingError(message: "Canonical path for localized strings file \(source) is not valid UTF-8",
                                              source: source, kind: .invalidResource)
        }
        return canonical
    }
    static func parseFile(_ url: URL, locale: LocaleTag, warningHandler: LocalizedStringWarningHandler?,
                          budget: CatalogParsingBudget) throws -> ParsedStringsFile {
        let path = try canonicalPath(url.path)
        var metadata = stat()
        guard path.withCString({ fstatat(AT_FDCWD, $0, &metadata, 0) }) == 0 else {
            throw LocalizedStringLoadingError(message: "Unable to load localized strings file contents for \(path)",
                                              source: path, cause: posixError())
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            throw LocalizedStringLoadingError(message: "\(path) is not a regular file", source: path, kind: .invalidResource)
        }
        // A selected file can change between stat and open. Nonblocking open plus
        // fstat refuses a replacement FIFO/special file without waiting for data.
        let fd = path.withCString { Darwin.open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else {
            throw LocalizedStringLoadingError(message: "Unable to load localized strings file contents for \(path)",
                                              source: path, cause: posixError())
        }
        defer { Darwin.close(fd) }
        var openedMetadata = stat()
        guard fstat(fd, &openedMetadata) == 0 else {
            throw LocalizedStringLoadingError(message: "Unable to load localized strings file contents for \(path)",
                                              source: path, cause: posixError())
        }
        guard openedMetadata.st_mode & S_IFMT == S_IFREG else {
            throw LocalizedStringLoadingError(message: "\(path) is not a regular file", source: path, kind: .invalidResource)
        }
        let session = CatalogParsingSession(source: path, options: budget.options, warningHandler: warningHandler, budget: budget)
        try session.beginFile(path)
        let data = try read(session: session) { buffer, count in
            var countRead: Int
            repeat { countRead = Darwin.read(fd, buffer, count) } while countRead < 0 && errno == EINTR
            guard countRead >= 0 else {
                throw LocalizedStringLoadingError(message: "Unable to load localized strings resource contents for \(path)",
                                                  source: path, cause: posixError())
            }
            return countRead
        }
        return try session.parseBytes(data, locale: locale.tag, chargeInput: false)
    }
    static func read(session: CatalogParsingSession,
                     read: (UnsafeMutablePointer<UInt8>, Int) throws -> Int) throws -> Data {
        let ceiling = session.options.maximumInputBytes + 1
        var buffer = [UInt8](repeating: 0, count: min(8_192, ceiling))
        var data = Data()
        data.reserveCapacity(min(8_192, session.options.maximumInputBytes))
        while data.count < ceiling {
            let requested = min(buffer.count, ceiling - data.count)
            let count = try buffer.withUnsafeMutableBufferPointer { try read($0.baseAddress!, requested) }
            if count == 0 { break }
            guard count > 0 && count <= requested else {
                throw LocalizedStringLoadingError(message: "Unable to load localized strings resource contents for \(session.source)",
                                                  source: session.source, cause: posixError(EIO))
            }
            try session.addInputBytes(count)
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    static func loadDirectory(_ url: URL, warningHandler: LocalizedStringWarningHandler?,
                              options: LocalizedStringLoadingOptions) throws -> [LocaleTag: ParsedStringsFile] {
        let path = url.path
        var metadata = stat()
        guard path.withCString({ fstatat(AT_FDCWD, $0, &metadata, 0) }) == 0 else {
            throw LocalizedStringLoadingError(message: "Location '\(path)' does not exist", source: path, kind: .discovery)
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw LocalizedStringLoadingError(message: "Location '\(path)' exists but is not a directory", source: path, kind: .discovery)
        }
        guard let directory = path.withCString({ opendir($0) }) else {
            throw LocalizedStringLoadingError(message: "Unable to read localized strings directory '\(path)'",
                                              source: path, cause: posixError(), kind: .discovery)
        }
        defer { closedir(directory) }
        let budget = CatalogParsingBudget(options: options)
        let discoverySource = "filesystem directory '\(path)'"
        var names: [[UInt8]] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 {
                    throw LocalizedStringLoadingError(message: "Unable to read localized strings directory '\(path)'",
                                                      source: path, cause: posixError(), kind: .discovery)
                }
                break
            }
            let bytes = withUnsafeBytes(of: entry.pointee.d_name) { Array($0.prefix { $0 != 0 }) }
            if bytes == [46] || bytes == [46, 46] { continue }
            try budget.discoverEntry(source: discoverySource)
            names.append(bytes)
        }
        names.sort { $0.lexicographicallyPrecedes($1) }
        var files: [LocaleTag: ParsedStringsFile] = [:]
        for bytes in names {
            let name = String(decoding: bytes, as: UTF8.self)
            let child = url.appendingPathComponent(name)
            if isDirectory(Array(path.utf8) + [47] + bytes) { continue }
            if bytes.first == 46 { continue }
            guard let tag = try tagForFilename(bytes, directory: path) else { continue }
            let locale = LocaleTag.forLanguageTag(tag)
            if files[locale] != nil {
                throw LocalizedStringLoadingError(message: "Duplicate localized strings file for locale '\(locale.tag)' found at '\(child.path)'",
                                                  source: child.path, kind: .duplicateLocale)
            }
            files[locale] = try parseFile(child, locale: locale, warningHandler: warningHandler, budget: budget)
        }
        try requireUniqueRenderedLocales(files, source: path)
        return files
    }
    static func tagForFilename(_ bytes: [UInt8], directory: String) throws -> String? {
        let name = String(decoding: bytes, as: UTF8.self)
        let suffix = bytes.suffix(5).map { (65...90).contains($0) ? $0 + 32 : $0 }
        let hasJSON = suffix == [46, 106, 115, 111, 110]
        let stemBytes = hasJSON ? bytes.dropLast(5) : bytes[...]
        if let stem = String(bytes: stemBytes, encoding: .utf8), JDKLocaleTag.isCatalogLanguageTag(stem) { return stem }
        if hasJSON {
            throw LocalizedStringLoadingError(message: "File '\(name)' ends with .json but is not named with a valid IETF BCP 47 language tag. Use names like 'en', 'en.json', or 'en-US.json'",
                                              source: directory, kind: .invalidResource)
        }
        return nil
    }
    static func requireUniqueRenderedLocales(_ files: [LocaleTag: ParsedStringsFile], source: String) throws {
        var tags: Set<ExactString> = []
        for locale in files.keys.sorted(by: { utf8Less($0.tag, $1.tag) }) {
            guard tags.insert(ExactString(locale.tag.lowercased())).inserted else {
                throw LocalizedStringLoadingError(message: "Duplicate locale key rendering as language tag '\(locale.tag)'",
                                                  source: source, kind: .duplicateLocale)
            }
        }
    }
}
