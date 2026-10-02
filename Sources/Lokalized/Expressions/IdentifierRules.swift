/// Oracle-pinned identifier policy: [L_][LNM_-]*, over Unicode scalars.
/// Swift/Foundation Unicode categories and grapheme segmentation are not used.
package enum IdentifierRules {
    package static func isStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 95 || IdentifierTables.contains(scalar.value, start: true)
    }

    package static func isContinuation(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 95 || scalar.value == 45 || IdentifierTables.contains(scalar.value, start: false)
    }

    package static func isIdentifier(_ value: String) -> Bool {
        var scalars = value.unicodeScalars.makeIterator()
        guard let first = scalars.next(), isStart(first) else { return false }
        while let scalar = scalars.next() {
            guard isContinuation(scalar) else { return false }
        }
        return true
    }
}
