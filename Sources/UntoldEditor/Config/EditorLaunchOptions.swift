//
//  EditorLaunchOptions.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Command-line options of the editor executable.
enum EditorLaunchOptions {
    /// `--open-project <folder>`: open this project at launch instead of showing the welcome
    /// screen. The folder is the one that contains `<Name>.xcodeproj`.
    static let openProjectFlag = "--open-project"

    static func projectToOpen(arguments: [String] = CommandLine.arguments) -> URL? {
        guard let index = arguments.firstIndex(of: openProjectFlag), index + 1 < arguments.count else { return nil }
        let path = (arguments[index + 1] as NSString).expandingTildeInPath
        guard path.isEmpty == false, path.hasPrefix("--") == false else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
