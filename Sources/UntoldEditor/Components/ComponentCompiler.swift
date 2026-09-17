//
//  ComponentCompiler.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The compiler and macOS SDK the editor builds component libraries with.
///
/// `xcrun` is called by absolute path: the user's `swift` on `PATH` can be a toolchain manager's
/// shim pointing anywhere, and the build must not depend on it.
struct ComponentToolchain: Equatable {
    let swiftcPath: String
    let macOSSDKPath: String
    /// First line of `swiftc --version`.
    let compilerVersion: String

    static let xcrunPath = "/usr/bin/xcrun"

    static func locate() -> Result<ComponentToolchain, ComponentBuildError> {
        guard FileManager.default.isExecutableFile(atPath: xcrunPath) else {
            return .failure(.toolchainMissing("xcrun was not found. Install Xcode or the Command Line Tools."))
        }
        let compiler = ComponentCompiler.run(xcrunPath, ["--find", "swiftc"])
        let sdk = ComponentCompiler.run(xcrunPath, ["--sdk", "macosx", "--show-sdk-path"])
        guard compiler.status == 0, sdk.status == 0 else {
            return .failure(.toolchainMissing("xcrun could not find swiftc or the macOS SDK:\n\(compiler.output)\(sdk.output)"))
        }
        let swiftcPath = compiler.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = ComponentCompiler.run(swiftcPath, ["--version"]).output
            .split(separator: "\n").first.map(String.init) ?? "unknown"
        return .success(ComponentToolchain(
            swiftcPath: swiftcPath,
            macOSSDKPath: sdk.output.trimmingCharacters(in: .whitespacesAndNewlines),
            compilerVersion: version
        ))
    }
}

enum ComponentBuildError: Error, Equatable, LocalizedError {
    case toolchainMissing(String)
    case sdkMissing
    case compilerMismatch(editor: String, installed: String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case let .toolchainMissing(detail):
            return detail
        case .sdkMissing:
            return "The editor's Component SDK was not found, so components cannot be compiled. Rebuild the editor, or reinstall it if this is a packaged app."
        case let .compilerMismatch(editor, installed):
            return "This editor was built with \"\(editor)\" but the installed compiler is \"\(installed)\". Components must be compiled with the same compiler: install the matching Xcode, or build the editor from source."
        case let .loadFailed(detail):
            return "The component library could not be loaded: \(detail)"
        }
    }
}

struct ComponentCompileRequest: Equatable {
    let unit: ComponentSourceUnit
    let revision: Int
    let outputDirectory: URL
    let sdk: ComponentSDK
    let toolchain: ComponentToolchain

    /// Unique per build: Swift libraries are never unloaded, and two images defining classes
    /// of the same name make the Objective-C runtime complain and casts misbehave.
    var moduleName: String {
        "\(unit.moduleBaseName)_r\(revision)"
    }

    var libraryURL: URL {
        outputDirectory.appendingPathComponent("\(moduleName).dylib")
    }

    var swiftModuleURL: URL {
        outputDirectory.appendingPathComponent("\(moduleName).swiftmodule")
    }
}

struct ComponentDiagnostic: Identifiable, Equatable {
    enum Severity: String, Equatable {
        case error
        case warning
        case note
    }

    let file: String
    let line: Int
    let column: Int
    let severity: Severity
    let message: String

    var id: String {
        "\(file):\(line):\(column):\(severity.rawValue):\(message)"
    }

    var fileName: String {
        (file as NSString).lastPathComponent
    }
}

struct ComponentCompileResult {
    let request: ComponentCompileRequest
    let succeeded: Bool
    let output: String
    let diagnostics: [ComponentDiagnostic]
    let seconds: Double
}

enum ComponentCompiler {
    /// The `swiftc` arguments for one unit. Pure, so it can be tested without a toolchain.
    static func arguments(for request: ComponentCompileRequest) -> [String] {
        var arguments = [
            "-emit-library", "-parse-as-library",
            "-o", request.libraryURL.path,
            "-module-name", request.moduleName,
        ]
        if request.unit.role == .pluginRuntime {
            // Later units import this one, so they need its module next to the library.
            arguments += ["-emit-module", "-emit-module-path", request.swiftModuleURL.path]
        }
        for imported in request.unit.reloadableImports.sorted() {
            arguments += ["-module-alias", "\(imported)=\(imported)_r\(request.revision)"]
        }
        arguments += [
            "-swift-version", "5", "-Onone", "-g",
            "-D", "UNTOLD_EDITOR",
            "-target", request.sdk.targetTriple,
            "-sdk", request.toolchain.macOSSDKPath,
            "-I", request.sdk.modulesDirectory.path,
        ]
        if request.unit.reloadableImports.isEmpty == false {
            arguments += ["-I", request.outputDirectory.path]
        }
        arguments += [
            "-Xcc", "-fmodule-map-file=\(request.sdk.cShaderTypesModuleMap.path)",
            // Link nothing of the engine: its symbols are found in the running editor at load.
            "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
        ]
        arguments += request.unit.sources.map(\.path)
        return arguments
    }

    /// Runs the compiler. Blocking: call it off the main thread.
    static func compile(_ request: ComponentCompileRequest, attach: ((Process) -> Void)? = nil) -> ComponentCompileResult {
        try? FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
        let started = Date()
        let result = run(request.toolchain.swiftcPath, arguments(for: request), attach: attach)
        return ComponentCompileResult(
            request: request,
            succeeded: result.status == 0,
            output: result.output,
            diagnostics: parseDiagnostics(result.output),
            seconds: Date().timeIntervalSince(started)
        )
    }

    /// `/path/File.swift:12:9: error: message` lines; everything else (source excerpts, carets)
    /// stays in the raw output.
    static func parseDiagnostics(_ output: String) -> [ComponentDiagnostic] {
        var diagnostics: [ComponentDiagnostic] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 4, omittingEmptySubsequences: false)
            guard parts.count == 5,
                  parts[0].hasPrefix("/"),
                  let lineNumber = Int(parts[1]),
                  let column = Int(parts[2]),
                  let severity = ComponentDiagnostic.Severity(rawValue: parts[3].trimmingCharacters(in: .whitespaces))
            else { continue }
            let diagnostic = ComponentDiagnostic(
                file: String(parts[0]),
                line: lineNumber,
                column: column,
                severity: severity,
                message: parts[4].trimmingCharacters(in: .whitespaces)
            )
            if diagnostics.contains(diagnostic) == false {
                diagnostics.append(diagnostic)
            }
        }
        return diagnostics
    }

    static func run(_ executable: String, _ arguments: [String], attach: ((Process) -> Void)? = nil) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        attach?(process)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
