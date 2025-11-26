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
        return scriptsDirectory()?.appendingPathComponent("Sources/GenerateScripts")
    }
    
    func generatedDirectory() -> URL? {
        return scriptsDirectory()?.appendingPathComponent("Generated")
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
              let generatedDir = generatedDirectory() else {
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
    
    private func generatePackageSwift() -> String {
        return """
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
        return """
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
        
                let outputDir = URL(fileURLWithPath: "Generated/")
                try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
                // TODO: Call your script generation functions here
                // Example: generatePlayerController(to: outputDir)
                
                print("✅ All scripts generated in Generated/")
            }
        }
        """
    }
    
    private func generateScriptTemplate(name: String) -> String {
        return """
        //
        //  \(name).swift
        //  USC Script
        //
        //  Copyright (C) Untold Engine Studios
        //  Licensed under the GNU LGPL v3.0 or later.
        //
        
        import Foundation
        import UntoldEngine
        
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
        return """
        .build/
        Generated/
        .DS_Store
        """
    }
}

