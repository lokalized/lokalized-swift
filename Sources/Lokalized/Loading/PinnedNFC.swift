// Original canonical normalization for the separately pinned Unicode 17 IDNA profile.
// This code deliberately does not consult Foundation or the host's Unicode tables.
package enum PinnedNFC {
    package static func normalize(_ input: [UInt32]) -> [UInt32] {
        guard !input.isEmpty else { return [] }
        var decomposed: [UInt32] = []
        decomposed.reserveCapacity(input.count)
        for scalar in input { decompose(scalar, into: &decomposed) }

        // Canonical ordering is stable within each sequence of nonstarters. Keep
        // already ordered sequences untouched, and use an index tie breaker for
        // the remaining runs. This avoids quadratic work on long hostile runs.
        var classes = decomposed.map(IDNAUnicodeTables.combiningClass)
        var start = 0
        while start < decomposed.count {
            if classes[start] == 0 { start += 1; continue }
            var end = start + 1
            var ordered = true
            while end < decomposed.count && classes[end] != 0 {
                if classes[end] < classes[end - 1] { ordered = false }
                end += 1
            }
            if !ordered {
                let indices = (start..<end).sorted {
                    classes[$0] == classes[$1] ? $0 < $1 : classes[$0] < classes[$1]
                }
                let orderedScalars = indices.map { decomposed[$0] }
                let orderedClasses = indices.map { classes[$0] }
                decomposed.replaceSubrange(start..<end, with: orderedScalars)
                classes.replaceSubrange(start..<end, with: orderedClasses)
            }
            start = end
        }

        var composed: [UInt32] = []
        composed.reserveCapacity(decomposed.count)
        composed.append(decomposed[0])
        var starterIndex: Int? = classes[0] == 0 ? 0 : nil
        var lastClass = classes[0]
        for index in 1..<decomposed.count {
            let scalar = decomposed[index]
            let combiningClass = classes[index]
            if let starterIndex,
               lastClass == 0 || lastClass < combiningClass,
               let replacement = compose(composed[starterIndex], scalar) {
                composed[starterIndex] = replacement
                // A consumed character does not block later compositions.
            } else {
                if combiningClass == 0 { starterIndex = composed.count }
                composed.append(scalar)
                lastClass = combiningClass
            }
        }
        return composed
    }

    private static func decompose(_ scalar: UInt32, into output: inout [UInt32]) {
        if scalar >= 0xAC00 && scalar <= 0xD7A3 {
            let syllable = scalar - 0xAC00
            output.append(0x1100 + syllable / 588)
            output.append(0x1161 + (syllable % 588) / 28)
            let trailing = syllable % 28
            if trailing != 0 { output.append(0x11A7 + trailing) }
        } else if let mapping = IDNAUnicodeTables.decomposition(scalar) {
            for member in mapping { decompose(member, into: &output) }
        } else {
            output.append(scalar)
        }
    }

    private static func compose(_ starter: UInt32, _ scalar: UInt32) -> UInt32? {
        if starter >= 0x1100 && starter <= 0x1112,
           scalar >= 0x1161 && scalar <= 0x1175 {
            return 0xAC00 + ((starter - 0x1100) * 21 + scalar - 0x1161) * 28
        }
        if starter >= 0xAC00 && starter <= 0xD7A3,
           (starter - 0xAC00) % 28 == 0,
           scalar >= 0x11A8 && scalar <= 0x11C2 {
            return starter + scalar - 0x11A7
        }
        return IDNAUnicodeTables.composition(starter, scalar)
    }
}
