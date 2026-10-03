import Darwin
import Foundation
import SwiftUI
import LokalizedConformanceSupport

// Development-only app entry point. The same standalone qualification functions
// used by the CLI run inside a real iOS application sandbox, without XCTest.
nonisolated private struct SelfTestReport: Encodable, Sendable { let status = "passed"; let checks: Int }
nonisolated private struct ErrorReport: Encodable, Sendable { let status = "error"; let error: String }

nonisolated private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

@main
struct IOSConformanceApp: App {
    @State private var started = false

    nonisolated private static func runQualification() {
        do {
            guard CommandLine.arguments.count == 2,
                  let reference = Bundle.main.resourceURL?.appendingPathComponent("Reference") else {
                throw NSError(domain: "IOSConformanceApp", code: 1)
            }
            let output: Data
            switch CommandLine.arguments[1] {
            case "--self-test": output = try encode(SelfTestReport(checks: ConformanceRunner.selfTest()))
            case "--inventory": output = try encode(ConformanceRunner.inventory(referenceDirectory: reference))
            case "--plural-data": output = try encode(ConformanceRunner.pluralDataAudit(referenceDirectory: reference))
            case "--locale-data": output = try encode(ConformanceRunner.localeDataAudit(referenceDirectory: reference))
            case "--resolution-components": output = try encode(ResolutionComponentQualification.run(referenceDirectory: reference))
            case "--runtime-adapter": output = try encode(RuntimeAdapterQualification.run(referenceDirectory: reference))
            case "--loader": output = try encode(LoaderQualification.run(referenceDirectory: reference))
            case "--loader-boundaries": output = try encode(LoaderBoundaryQualification.run())
            case "--manifest-contract": output = try encode(ManifestContractQualification.run(referenceDirectory: reference))
            case "--manifest-normalization": output = try encode(ManifestNormalizationQualification.run(referenceDirectory: reference))
            case "--diagnostic-text": output = try encode(DiagnosticTextQualification.run(referenceDirectory: reference))
            case "--manifest-urls": output = try encode(ConformanceRunner.manifestURLAudit(referenceDirectory: reference))
            case "--idna-normalization": output = try encode(ConformanceRunner.idnaNormalizationAudit(referenceDirectory: reference))
            case "--audit": output = try encode(ConformanceRunner.audit(referenceDirectory: reference))
            default: throw NSError(domain: "IOSConformanceApp", code: 2)
            }
            // The simulator console can block on one very large JSON line.
            // Base64 preserves every original UTF-8 byte in bounded ASCII lines.
            FileHandle.standardOutput.write(Data("LOKALIZED_IOS_REPORT_BEGIN\n".utf8))
            let bytes = Array(output.base64EncodedString().utf8)
            for start in stride(from: 0, to: bytes.count, by: 1_024) {
                FileHandle.standardOutput.write(Data(bytes[start..<min(start + 1_024, bytes.count)]) + Data([10]))
            }
            FileHandle.standardOutput.write(Data("LOKALIZED_IOS_REPORT_END\n".utf8))
            // Audit status and every ID are checked by the host qualifier. The
            // retained incomplete corpus is never turned into a passing audit.
            exit(0)
        } catch {
            if let output = try? encode(ErrorReport(error: String(describing: error))) {
                FileHandle.standardError.write(output)
            }
            exit(1)
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("Lokalized conformance").onAppear {
                guard !started else { return }
                started = true
                // Large Unicode audits run after application launch, off the UI
                // thread, so UIKit's launch watchdog cannot truncate the suite.
                Task.detached { Self.runQualification() }
            }
        }
    }
}
