/// Manifest special-host mapping pinned to Unicode 17.0 with separately
/// pinned Node 26.5.0 normalization and validity. No device Unicode, Foundation URL
/// or ICU services determine the profile.
package enum IDNAProcessor {
    package static func toASCII(_ domain: String) -> String? {
        // The URL profile preserves even malformed ACE labels in an entirely
        // ASCII input. Unicode-containing inputs take the compatibility path below.
        if domain.utf8.allSatisfy({ $0 < 128 }) {
            return String(decoding: domain.utf8.map { (65...90).contains($0) ? $0 + 32 : $0 }, as: UTF8.self)
        }
        // The pinned Node URL profile bounds decoded Unicode input before
        // mapping, including characters that mapping would subsequently ignore.
        guard domain.utf8.count <= 16_384 else { return nil }
        var mapped: [UInt32] = []
        mapped.reserveCapacity(domain.unicodeScalars.count)
        for scalar in domain.unicodeScalars {
            let row = IDNAUnicodeTables.mapping(scalar.value)
            switch row.status {
            case 1: break
            case 2: mapped.append(contentsOf: row.replacement)
            default: mapped.append(scalar.value)
            }
        }
        let normalized = IDNACompatibilityNormalizer.normalize(mapped)
        let labels = normalized.split(separator: 46, omittingEmptySubsequences: false)
        var result: [String] = []
        result.reserveCapacity(labels.count)
        for original in labels {
            var label = Array(original)
            var originalACE: String?
            if label.starts(with: [120, 110, 45, 45]) {
                guard label.allSatisfy({ $0 < 128 }),
                      let decoded = PunycodeCodec.decode(label.dropFirst(4).map(UInt8.init)),
                      !decoded.isEmpty, decoded.contains(where: { $0 >= 128 }),
                      IDNACompatibilityNormalizer.normalize(decoded) == decoded else { return nil }
                originalACE = String(decoding: label.map(UInt8.init), as: UTF8.self)
                label = decoded
            }
            guard valid(label) else { return nil }
            // Successful ACE validation preserves the mapped ASCII spelling,
            // including a redundant leading Punycode delimiter in this oracle.
            if let originalACE { result.append(originalACE) }
            else if label.contains(where: { $0 >= 128 }) {
                guard let encoded = PunycodeCodec.encode(label) else { return nil }
                result.append("xn--" + encoded)
            } else { result.append(String(decoding: label.map(UInt8.init), as: UTF8.self)) }
        }
        return result.joined(separator: ".")
    }
    private static func valid(_ label: [UInt32]) -> Bool {
        guard let first = label.first else { return true }
        guard !IDNACompatibilityProperties.isMark(first), !label.starts(with: [120, 110, 45, 45]) else { return false }
        for scalar in label {
            let status = IDNAUnicodeTables.mapping(scalar).status
            guard scalar != 46, status == 0 || status == 3 else { return false }
        }
        // Preserve the pinned oracle's observed first-joiner short circuit:
        // scalar validity precedes it, but later joiners and bidi do not run.
        // This is a URL compatibility quirk, not strict UTS #46 conformance.
        if let index = label.firstIndex(where: { $0 == 0x200C || $0 == 0x200D }) {
            guard index > 0 else { return false }
            if IDNACompatibilityProperties.isVirama(label[index - 1]) { return true }
            guard label[index] == 0x200C else { return false }
            // This oracle searches the entire prefix/suffix for a joining
            // direction, even across nontransparent intervening characters.
            return label[..<index].contains { [1, 3].contains(IDNACompatibilityProperties.joiningType($0)) }
                && label[(index + 1)...].contains { [2, 3].contains(IDNACompatibilityProperties.joiningType($0)) }
        }
        return validBidi(label)
    }
    private static func validBidi(_ label: [UInt32]) -> Bool {
        let classes = label.map(IDNACompatibilityProperties.bidiClass)
        // The pinned URL oracle checks RTL labels, while accepting LTR labels
        // such as "1é" or "_a" elsewhere in the same domain. Keep that observed
        // URL behavior separate from strict domain-registration validation.
        guard classes.contains(where: { [1, 2, 3].contains($0) }) else { return true }
        guard let first = classes.first, first == 1 || first == 2,
              classes.allSatisfy({ (1...10).contains($0) }),
              let last = classes.last(where: { $0 != 10 }), [1, 2, 3, 4].contains(last),
              !(classes.contains(3) && classes.contains(4)) else { return false }
        return true
    }
}
