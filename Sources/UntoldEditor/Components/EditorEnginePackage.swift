//
//  EditorEnginePackage.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldEngine

/// The engine this editor was built with, as a package reference for the projects it creates.
///
/// The editor compiles a project's code components against its own engine, and Xcode compiles
/// the same sources against the engine the project pins. Pinning new projects to the editor's
/// engine is what makes "it compiles in Xcode" and "it compiles in the editor" mean the same.
enum EditorEnginePackage {
    /// A packaged editor reads it from its Component SDK; an editor run from source finds the
    /// `Package.resolved` of its own checkout above the executable. `nil` when neither exists,
    /// in which case new projects keep the engine's default reference and get no plugins folder.
    static func resolve(
        sdk: ComponentSDK? = ComponentSDK.resolve(),
        executableURL: URL? = Bundle.main.executableURL
    ) -> EnginePackageReference? {
        if let sdk, let url = sdk.engineURL, let revision = sdk.engineRevision {
            return EnginePackageReference(url: url, requirement: .revision(revision))
        }
        guard var directory = executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() else { return nil }
        for _ in 0 ..< 8 {
            let candidate = directory.appendingPathComponent("Package.resolved")
            if let reference = reference(fromResolvedFile: candidate) {
                return reference
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }
        return nil
    }

    static func reference(fromResolvedFile url: URL) -> EnginePackageReference? {
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable { let revision: String }
                let identity: String
                let location: String
                let state: State
            }

            let pins: [Pin]
        }
        guard let data = try? Data(contentsOf: url),
              let resolved = try? JSONDecoder().decode(Resolved.self, from: data),
              let engine = resolved.pins.first(where: { $0.identity == "untoldengine" })
        else { return nil }
        return EnginePackageReference(url: engine.location, requirement: .revision(engine.state.revision))
    }
}
