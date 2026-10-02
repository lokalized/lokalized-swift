package extension LanguageRangeTables {
    private static let registryIndex = makeIndex(blob: registryBlob, offsets: registryOffsets)
    private static let jdkIndex = makeIndex(blob: jdkBlob, offsets: jdkOffsets)

    private static func row(blob: StaticString, offsets: [UInt32], index: Int) -> String {
        blob.withUTF8Buffer { bytes in
            String(decoding: bytes[Int(offsets[index])..<(Int(offsets[index + 1]) - 1)], as: UTF8.self)
        }
    }

    private static func makeIndex(blob: StaticString, offsets: [UInt32]) -> [String: Int] {
        var index: [String: Int] = [:]
        index.reserveCapacity(offsets.count - 1)
        for position in 0..<(offsets.count - 1) {
            let value = row(blob: blob, offsets: offsets, index: position)
            let key = value.prefix { $0 != "=" }
            precondition(index.updateValue(position, forKey: String(key)) == nil)
        }
        return index
    }

    static func equivalents(for key: String, jdk: Bool) -> [String]? {
        let index = jdk ? jdkIndex : registryIndex
        guard let position = index[key] else { return nil }
        let value = row(blob: jdk ? jdkBlob : registryBlob, offsets: jdk ? jdkOffsets : registryOffsets, index: position)
        return value.dropFirst(key.utf8.count + 1).split(separator: " ").map(String.init)
    }

    private static func hex(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ length: Int) -> UInt32 {
        var value: UInt32 = 0
        for offset in start..<(start + length) {
            let byte = bytes[offset]
            value = value * 16 + UInt32(byte <= 57 ? byte - 48 : byte - 87)
        }
        return value
    }

    static func lowercase(_ scalar: UInt32) -> [UInt32]? {
        lowercaseBlob.withUTF8Buffer { bytes in
            var low = 0, high = lowercaseCount
            while low < high {
                let middle = (low + high) / 2
                if hex(bytes, middle * 18, 6) < scalar { low = middle + 1 } else { high = middle }
            }
            guard low < lowercaseCount, hex(bytes, low * 18, 6) == scalar else { return nil }
            let first = hex(bytes, low * 18 + 6, 6), second = hex(bytes, low * 18 + 12, 6)
            return second == 0xffffff ? [first] : [first, second]
        }
    }

    static func wordProperties(_ scalar: UInt32) -> UInt32 {
        wordBlob.withUTF8Buffer { bytes in
            var low = 0, high = wordRangeCount
            while low < high {
                let middle = (low + high) / 2
                if hex(bytes, middle * 15 + 6, 6) < scalar { low = middle + 1 } else { high = middle }
            }
            guard low < wordRangeCount, hex(bytes, low * 15, 6) <= scalar else { return 0 }
            return hex(bytes, low * 15 + 12, 3)
        }
    }
}
