import Foundation
import LokalizedConformanceSupport
import Darwin

struct CommandOptions {
    let command: String
    let reference: URL
    let report: URL?

    init(arguments: [String]) throws {
        var command: String?
        var reference = URL(fileURLWithPath: "Reference", isDirectory: true)
        var report: URL?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--self-test", "--inventory", "--audit", "--plural-data", "--locale-data", "--resolution-components", "--runtime-adapter", "--loader", "--manifest-contract", "--manifest-urls":
                guard command == nil else { throw UsageError("Choose exactly one command") }
                command = argument
            case "--reference", "--report":
                guard index + 1 < arguments.count else { throw UsageError("Missing value for \(argument)") }
                index += 1
                let url = URL(fileURLWithPath: arguments[index], isDirectory: argument == "--reference")
                if argument == "--reference" { reference = url } else { report = url }
            default: throw UsageError("Unknown argument: \(argument)")
            }
            index += 1
        }
        guard let command else { throw UsageError("Choose --self-test, --inventory, --audit, --plural-data, --locale-data, --resolution-components, --runtime-adapter, --loader, --manifest-contract, or --manifest-urls") }
        self.command = command
        self.reference = reference
        self.report = report
    }
}

struct UsageError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) {
        description = message + "\nUsage: LokalizedConformance (--self-test | --inventory | --audit | --plural-data | --locale-data | --resolution-components | --runtime-adapter | --loader | --manifest-contract | --manifest-urls) [--reference PATH] [--report PATH]"
    }
}

struct SelfTestReport: Encodable { let status = "passed"; let checks: Int }
struct ErrorReport: Encodable { let status = "error"; let error: String }

func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(10)
    return data
}

do {
    let options = try CommandOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let output: Data
    let code: Int32
    switch options.command {
    case "--self-test":
        output = try encode(SelfTestReport(checks: ConformanceRunner.selfTest()))
        code = 0
    case "--inventory":
        output = try encode(ConformanceRunner.inventory(referenceDirectory: options.reference))
        code = 0
    case "--plural-data":
        let report = try ConformanceRunner.pluralDataAudit(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    case "--locale-data":
        let report = try ConformanceRunner.localeDataAudit(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    case "--resolution-components":
        let report = try ResolutionComponentQualification.run(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    case "--runtime-adapter":
        let report = try RuntimeAdapterQualification.run(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    case "--manifest-urls":
        let report = try ConformanceRunner.manifestURLAudit(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    case "--manifest-contract":
        let report = try ManifestContractQualification.run(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    case "--loader":
        let report = try LoaderQualification.run(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    default:
        let report = try ConformanceRunner.audit(referenceDirectory: options.reference)
        output = try encode(report)
        code = report.status == "passed" ? 0 : 1
    }
    if let report = options.report { try output.write(to: report, options: .atomic) }
    FileHandle.standardOutput.write(output)
    exit(code)
} catch {
    if let output = try? encode(ErrorReport(error: String(describing: error))) { FileHandle.standardError.write(output) }
    exit(2)
}
