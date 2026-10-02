/// Original implementation of the separately qualified Node URL profile.
/// The oracle preserves the whole input when its quick check passes. A failed
/// check decomposes the whole input, then orders legacy classes and composes.
/// PinnedNFC remains the independent, complete Unicode 17 NFC implementation.
package enum IDNACompatibilityNormalizer {
    package static func normalize(_ input: [UInt32]) -> [UInt32] {
        guard !input.isEmpty else { return [] }
        guard requiresNormalization(input) else { return input }
        var ordered: [UInt32] = []
        ordered.reserveCapacity(input.count)
        for scalar in input {
            if (0xAC00...0xD7A3).contains(scalar) {
                let position = scalar - 0xAC00
                ordered.append(0x1100 + position / 588)
                ordered.append(0x1161 + (position % 588) / 28)
                if position % 28 != 0 { ordered.append(0x11A7 + position % 28) }
            } else if let decomposition = IDNACompatibilityNormalizationTables.decomposition(scalar) {
                ordered.append(contentsOf: decomposition)
            } else {
                ordered.append(scalar)
            }
        }
        var classes = ordered.map(IDNACompatibilityNormalizationTables.combiningClass)
        var start = 0
        while start < ordered.count {
            if classes[start] == 0 { start += 1; continue }
            var end = start + 1, isOrdered = true
            while end < ordered.count && classes[end] != 0 {
                if classes[end] < classes[end - 1] { isOrdered = false }
                end += 1
            }
            if !isOrdered {
                let indices = (start..<end).sorted {
                    classes[$0] == classes[$1] ? $0 < $1 : classes[$0] < classes[$1]
                }
                let scalars = indices.map { ordered[$0] }, values = indices.map { classes[$0] }
                ordered.replaceSubrange(start..<end, with: scalars)
                classes.replaceSubrange(start..<end, with: values)
            }
            start = end
        }

        // Compose adjacent Jamo after the separately observed quick check and
        // full decomposition. Existing syllable/T contexts can therefore differ
        // depending on whether another part of the input triggered normalization.
        var collapsed: [UInt32] = []
        collapsed.reserveCapacity(ordered.count)
        var index = 0
        while index < ordered.count {
            let leading = ordered[index]
            if (0x1100...0x1112).contains(leading), index + 1 < ordered.count,
               (0x1161...0x1175).contains(ordered[index + 1]) {
                var syllable = 0xAC00 + ((leading - 0x1100) * 21 + ordered[index + 1] - 0x1161) * 28
                index += 2
                if index < ordered.count, (0x11A8...0x11C2).contains(ordered[index]) {
                    syllable += ordered[index] - 0x11A7
                    index += 1
                }
                collapsed.append(syllable)
            } else {
                collapsed.append(leading)
                index += 1
            }
        }
        var result: [UInt32] = []
        result.reserveCapacity(collapsed.count)
        result.append(collapsed[0])
        var previousClass = IDNACompatibilityNormalizationTables.combiningClass(collapsed[0])
        var starterIndex: Int? = previousClass == 0 ? 0 : nil
        for scalar in collapsed.dropFirst() {
            let combiningClass = IDNACompatibilityNormalizationTables.combiningClass(scalar)
            if let starterIndex, previousClass == 0 || previousClass < combiningClass,
               let replacement = IDNACompatibilityNormalizationTables.composition(result[starterIndex], scalar) {
                result[starterIndex] = replacement
            } else {
                if combiningClass == 0 { starterIndex = result.count }
                result.append(scalar)
                previousClass = combiningClass
            }
        }
        return result
    }

    private static func requiresNormalization(_ input: [UInt32]) -> Bool {
        var starter: UInt32?
        var previousClass: UInt8 = 0
        for (index, scalar) in input.enumerated() {
            if IDNACompatibilityNormalizationTables.decomposition(scalar)?.count == 1 { return true }
            let combiningClass = IDNACompatibilityNormalizationTables.combiningClass(scalar)
            if combiningClass != 0, previousClass > combiningClass { return true }
            if let starter, previousClass == 0 || previousClass < combiningClass,
               IDNACompatibilityNormalizationTables.composition(starter, scalar) != nil { return true }
            if index + 1 < input.count {
                let next = input[index + 1]
                if (0x1100...0x1112).contains(scalar), (0x1161...0x1175).contains(next) { return true }
                if (0xAC00...0xD7A3).contains(scalar), (scalar - 0xAC00) % 28 != 0,
                   (0x11A8...0x11C2).contains(next) { return true }
            }
            if combiningClass == 0 { starter = scalar }
            previousClass = combiningClass
        }
        return false
    }
}
