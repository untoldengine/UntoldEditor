//
//  ScriptProjectManager.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import Foundation
import UntoldEngine

enum ScriptProjectError: Error {
    case noAssetBasePath
    case projectAlreadyExists
    case failedToCreateDirectory
    case failedToWriteFile
    case projectNotInitialized
    case invalidScriptName
}

class ScriptProjectManager {
    static let shared = ScriptProjectManager()

    private init() {}

    // MARK: - Paths

    func scriptsDirectory() -> URL? {
        guard let basePath = EditorAssetBasePath.shared.basePath else {
            return nil
        }
        return basePath.appendingPathComponent("Scripts")
    }

    func sourcesDirectory() -> URL? {
        scriptsDirectory()?.appendingPathComponent("Sources/GenerateScripts")
    }

    func generatedDirectory() -> URL? {
        scriptsDirectory()?.appendingPathComponent("Generated")
    }

    // MARK: - Project Status

    func isProjectInitialized() -> Bool {
        guard let scriptsDir = scriptsDirectory() else { return false }
        let packageSwift = scriptsDir.appendingPathComponent("Package.swift")
        let generateScripts = sourcesDirectory()?.appendingPathComponent("GenerateScripts.swift")

        return FileManager.default.fileExists(atPath: packageSwift.path) &&
            FileManager.default.fileExists(atPath: generateScripts?.path ?? "")
    }

    // MARK: - Initialize Project

    func initializeProject() throws {
        guard let basePath = EditorAssetBasePath.shared.basePath else {
            throw ScriptProjectError.noAssetBasePath
        }

        if isProjectInitialized() {
            throw ScriptProjectError.projectAlreadyExists
        }

        guard let scriptsDir = scriptsDirectory(),
              let sourcesDir = sourcesDirectory(),
              let generatedDir = generatedDirectory()
        else {
            throw ScriptProjectError.noAssetBasePath
        }

        // Create directory structure
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generatedDir, withIntermediateDirectories: true)

        // Create Package.swift
        let packageSwiftContent = generatePackageSwift()
        let packageSwiftPath = scriptsDir.appendingPathComponent("Package.swift")
        try packageSwiftContent.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

        // Create GenerateScripts.swift
        let generateScriptsContent = generateMainScriptTemplate()
        let generateScriptsPath = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        try generateScriptsContent.write(to: generateScriptsPath, atomically: true, encoding: .utf8)

        // Create .gitignore
        let gitignoreContent = generateGitignore()
        let gitignorePath = scriptsDir.appendingPathComponent(".gitignore")
        try gitignoreContent.write(to: gitignorePath, atomically: true, encoding: .utf8)

        print("✅ Script project initialized at: \(scriptsDir.path)")
    }

    // MARK: - Create New Script

    func createNewScript(name: String) throws {
        guard !name.isEmpty else {
            throw ScriptProjectError.invalidScriptName
        }

        // Validate script name (alphanumeric, starts with letter)
        let nameRegex = "^[A-Za-z][A-Za-z0-9]*$"
        let namePredicate = NSPredicate(format: "SELF MATCHES %@", nameRegex)
        guard namePredicate.evaluate(with: name) else {
            throw ScriptProjectError.invalidScriptName
        }

        guard isProjectInitialized() else {
            throw ScriptProjectError.projectNotInitialized
        }

        guard let sourcesDir = sourcesDirectory() else {
            throw ScriptProjectError.noAssetBasePath
        }

        let scriptPath = sourcesDir.appendingPathComponent("\(name).swift")

        // Check if file already exists
        if FileManager.default.fileExists(atPath: scriptPath.path) {
            print("⚠️ Script \(name).swift already exists")
            return
        }

        // Create script file
        let scriptContent = generateScriptTemplate(name: name)
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)

        // Ensure GenerateScripts main triggers this generator
        try addScriptInvocationToMain(name: name)

        print("✅ Created script: \(scriptPath.path)")
    }

    // MARK: - Build Scripts

    func buildScripts(completion: @escaping (Result<String, Error>) -> Void) {
        guard let scriptsDir = scriptsDirectory() else {
            completion(.failure(ScriptProjectError.noAssetBasePath))
            return
        }

        guard isProjectInitialized() else {
            completion(.failure(ScriptProjectError.projectNotInitialized))
            return
        }

        // Run swift run in background
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.currentDirectoryURL = scriptsDir
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["run"]

            let pipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                let combinedOutput = output + errorOutput

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        // Notify Asset Browser to reload (new .uscript files likely created)
                        NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
                        completion(.success(combinedOutput))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "ScriptBuild", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: combinedOutput])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - List Scripts

    func listScriptFiles() -> [URL] {
        guard let sourcesDir = sourcesDirectory() else { return [] }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "GenerateScripts.swift" }
        } catch {
            return []
        }
    }

    // MARK: - Template Generators

    /// Adds a generate<Name>(to:) invocation into GenerateScripts.swift if not present.
    private func addScriptInvocationToMain(name: String) throws {
        guard let sourcesDir = sourcesDirectory() else { return }
        let generateScriptsPath = sourcesDir.appendingPathComponent("GenerateScripts.swift")

        var contents = try String(contentsOf: generateScriptsPath, encoding: .utf8)

        let callLine = "generate\(name)(to: outputDir)"
        if contents.contains(callLine) {
            return
        }

        let anchor = "print(\"✅ All scripts generated in Generated/\")"
        if let range = contents.range(of: anchor) {
            // Preserve existing indentation from the anchor line
            let lineStart = contents[..<range.lowerBound].lastIndex(of: "\n") ?? contents.startIndex
            let indentStart = contents.index(after: lineStart)
            let indent = String(contents[indentStart..<range.lowerBound])

            let insertion = "\(indent)\(callLine)\n\n\(indent)\(anchor)"
            contents.replaceSubrange(range, with: insertion)
        } else {
            // Fallback: append at end of file
            contents.append("\n        \(callLine)\n")
        }

        try contents.write(to: generateScriptsPath, atomically: true, encoding: .utf8)
    }

    private func generatePackageSwift() -> String {
        """
        // swift-tools-version: 5.10
        import PackageDescription

        let package = Package(
            name: "GameScripts",
            platforms: [.macOS(.v14)],
            dependencies: [
                .package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "develop")
            ],
            targets: [
                .executableTarget(
                    name: "GenerateScripts",
                    dependencies: ["UntoldEngine"]
                )
            ]
        )
        """
    }

    private func generateMainScriptTemplate() -> String {
        """
        //
        //  GenerateScripts.swift
        //  USC Script Generator
        //
        //  Copyright (C) Untold Engine Studios
        //  Licensed under the GNU LGPL v3.0 or later.
        //

        import Foundation
        import UntoldEngine

        @main
        struct GenerateScripts {
            static func main() {
                print("🔨 Generating USC scripts...")

                // Get the directory where GenerateScripts.swift lives (project root)
                let projectRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()  // Remove GenerateScripts.swift
                    .deletingLastPathComponent()  // Remove GenerateScripts
                    .deletingLastPathComponent()  // Remove Sources

                let outputDir = projectRoot.appendingPathComponent("Generated")

                // Create the directory if it doesn't exist
                try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

                print("📁 Output directory: \\(outputDir.path)")

                // TODO: Call your script generation functions here
                // Example: generatePlayerController(to: outputDir)
                // New scripts created in the editor are auto-added below.

                print("✅ All scripts generated in Generated/")
            }
        }
        """
    }

    private func generateScriptTemplate(name: String) -> String {
        """
        //
        //  \(name).swift
        //  USC Script
        //
        //  Copyright (C) Untold Engine Studios
        //  Licensed under the GNU LGPL v3.0 or later.
        //

        import Foundation
        import UntoldEngine
        import simd

        extension GenerateScripts {
            static func generate\(name)(to dir: URL) {
                let script = buildScript(name: "\(name)") { s in
                    s.onUpdate()
                     .log("TODO: Add your \(name) logic here")
                }

                let outputPath = dir.appendingPathComponent("\(name).uscript")
                try? saveUSCScript(script, to: outputPath)
                print("  ✅ \(name).uscript")
            }
        }
        """
    }

    private func generateGitignore() -> String {
        """
        .build/
        Generated/
        .DS_Store
        """
    }

    /// Removes a generate<Name>(to:) invocation from GenerateScripts.swift if present.
    func removeScriptInvocationFromMain(name: String) {
        guard let sourcesDir = sourcesDirectory() else { return }
        let generateScriptsPath = sourcesDir.appendingPathComponent("GenerateScripts.swift")

        guard FileManager.default.fileExists(atPath: generateScriptsPath.path),
              var contents = try? String(contentsOf: generateScriptsPath, encoding: .utf8)
        else { return }

        let callLine = "generate\(name)(to: outputDir)"

        if contents.contains(callLine) {
            contents = contents.replacingOccurrences(of: callLine + "\n", with: "")
            contents = contents.replacingOccurrences(of: callLine, with: "")
            try? contents.write(to: generateScriptsPath, atomically: true, encoding: .utf8)
        }
    }
}
