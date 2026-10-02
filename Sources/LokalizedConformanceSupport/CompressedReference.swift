import Foundation
import zlib

extension ConformanceRunner {
    /// Development-only fixture decoding using the Apple SDK's system zlib.
    /// Require one complete gzip member (including its CRC/size trailer), with
    /// separate limits on stored and decoded bytes. Never accept trailing data.
    static func boundedGzipRead(_ url: URL, maximumCompressedBytes: Int, maximumDecodedBytes: Int) throws -> Data {
        guard maximumCompressedBytes >= 0, maximumCompressedBytes < Int(UInt32.max),
              maximumDecodedBytes >= 0, maximumDecodedBytes < Int.max else {
            throw ConformanceError("Invalid compressed reference byte budget")
        }
        let compressed = try boundedRead(url, maximumBytes: maximumCompressedBytes)
        var stream = z_stream()
        guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ConformanceError("Cannot initialize compressed reference decoder")
        }
        defer { inflateEnd(&stream) }
        return try compressed.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var decoded = Data()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let capacity = min(buffer.count, maximumDecodedBytes - decoded.count + 1)
                let previousInput = stream.avail_in
                let (status, produced) = buffer.withUnsafeMutableBufferPointer { output in
                    stream.next_out = output.baseAddress
                    stream.avail_out = uInt(capacity)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    return (status, capacity - Int(stream.avail_out))
                }
                guard produced <= maximumDecodedBytes - decoded.count else {
                    throw ConformanceError("Decoded reference exceeds byte budget: \(url.lastPathComponent)")
                }
                decoded.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else {
                        throw ConformanceError("Compressed reference has trailing data: \(url.lastPathComponent)")
                    }
                    return decoded
                }
                guard status == Z_OK, produced > 0 || stream.avail_in < previousInput else {
                    throw ConformanceError("Compressed reference is invalid or truncated: \(url.lastPathComponent)")
                }
            }
        }
    }
}
