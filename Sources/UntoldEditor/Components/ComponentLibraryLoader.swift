//
//  ComponentLibraryLoader.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldComponentKit

struct LoadedComponentLibrary: Equatable, Identifiable {
    let path: String
    let moduleName: String
    let role: ComponentSourceUnit.Role
    let revision: Int
    let componentNames: [String]
    let extensionNames: [String]
    /// Kinds of entity the library adds to the creation shelves.
    var templateNames: [String] = []
    let byteSize: Int

    var id: String {
        path
    }
}

enum ComponentLibraryLoader {
    /// Loads one library and registers what it defines.
    ///
    /// A plugin runtime is loaded globally because the units built after it find its symbols
    /// through the flat namespace, which only sees global images. Everything else stays local.
    /// Nothing is ever unloaded: Swift images cannot be.
    static func load(_ request: ComponentCompileRequest) -> Result<LoadedComponentLibrary, ComponentBuildError> {
        let path = request.libraryURL.path
        let scope = request.unit.role == .pluginRuntime ? RTLD_GLOBAL : RTLD_LOCAL
        guard dlopen(path, RTLD_NOW | scope) != nil else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown loader error"
            return .failure(.loadFailed(detail))
        }

        let components = CodeComponentRegistry.shared.discover(imagePath: path, revision: request.revision, policy: .replace)
        let extensions = EditorExtensionRegistry.shared.discover(imagePath: path, revision: request.revision, replaceExisting: true)
        let templates = EntityTemplateRegistry.shared.discover(imagePath: path, revision: request.revision, replaceExisting: true)
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0

        return .success(LoadedComponentLibrary(
            path: path,
            moduleName: request.moduleName,
            role: request.unit.role,
            revision: request.revision,
            componentNames: (components.registered + components.replaced).sorted(),
            extensionNames: extensions.sorted(),
            templateNames: templates.sorted(),
            byteSize: size
        ))
    }
}
