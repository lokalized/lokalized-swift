/// Pinned Unicode15 scalar mappings and an original word-token implementation
/// for Java ROOT's contextual final sigma. No host Unicode properties/casing.
package enum LanguageRangeLowercase {
    package static func apply(_ source: String) -> String {
        // ASCII has no contextual or multi-scalar mappings in pinned ROOT casing.
        // Locale tags usually take this path, avoiding Unicode tables and arrays.
        if source.utf8.allSatisfy({ $0 < 128 }) {
            return String(decoding: source.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }, as: UTF8.self)
        }
        let scalars = Array(source.unicodeScalars)
        let finalSigmas = scalars.contains(where: { $0.value == 0x3a3 }) ? finalSigmaPositions(scalars) : []
        var result = String.UnicodeScalarView()
        for (index, scalar) in scalars.enumerated() {
            if scalar.value == 0x3a3 && finalSigmas.contains(index) { result.append(Unicode.Scalar(0x3c2)!) }
            else if let mapped = LanguageRangeTables.lowercase(scalar.value) {
                for value in mapped { result.append(Unicode.Scalar(value)!) }
            } else { result.append(scalar) }
        }
        return String(result)
    }

    private static func finalSigmaPositions(_ source: [Unicode.Scalar]) -> Set<Int> {
        // Format characters do not influence Java ROOT word segmentation.
        let active = source.indices.filter { LanguageRangeTables.wordProperties(source[$0].value) & 8 == 0 }
        let properties = active.map { LanguageRangeTables.wordProperties(source[$0].value) }
        func has(_ index: Int, _ mask: UInt32) -> Bool { index < active.count && properties[index] & mask != 0 }
        func unit(_ start: Int, _ type: UInt32) -> Int? {
            guard has(start, type) else { return nil }
            var end = start + 1
            while has(end, 4) { end += 1 }
            return end
        }
        func component(_ start: Int, _ type: UInt32, _ middle: UInt32) -> Int? {
            guard var end = unit(start, type) else { return nil }
            while true {
                if let next = unit(end, type) { end = next }
                else if has(end, middle), let next = unit(end + 1, type) { end = next }
                else { break }
            }
            if type == 1 && has(end, 256) { end += 1 }
            return end
        }
        func wordEnd(_ start: Int) -> Int? {
            var end = start
            if has(start, 64) {
                end += 1
                guard has(end, 2) else { return nil }
            } else if let word = component(end, 1, 16) { end = word }
            while let number = component(end, 2, 32) {
                end = number
                if let word = component(end, 1, 16) { end = word }
                else {
                    if has(end, 128) { end += 1 }
                    break
                }
            }
            return end > start ? end : nil
        }
        var positions = Set<Int>()
        var start = 0
        while start < active.count {
            var end = wordEnd(start) ?? start + 1
            if end == start + 1 { while has(end, 4) { end += 1 } }
            let firstOriginal = active[start], lastOriginal = active[end - 1]
            for index in start..<end where source[active[index]].value == 0x3a3 {
                let sigma = active[index]
                var cursor = sigma, precedingCased = false
                while cursor > firstOriginal {
                    // JDK21's queried boundary after a surrogate pair is true
                    // even when its forward word iterator joins that pair.
                    if source[cursor - 1].value > 0xffff { break }
                    cursor -= 1
                    if LanguageRangeTables.wordProperties(source[cursor].value) & 512 != 0 { precedingCased = true; break }
                }
                guard precedingCased else { continue }
                cursor = sigma + 1
                var followingCased = false
                while cursor <= lastOriginal {
                    if source[cursor - 1].value > 0xffff { break }
                    if LanguageRangeTables.wordProperties(source[cursor].value) & 512 != 0 { followingCased = true; break }
                    cursor += 1
                }
                if !followingCased { positions.insert(sigma) }
            }
            start = end
        }
        return positions
    }
}
