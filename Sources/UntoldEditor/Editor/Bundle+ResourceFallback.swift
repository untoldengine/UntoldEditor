//
//  Bundle+ResourceFallback.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import UntoldEngine

extension Bundle {
    /// Finds the first file named `filename` anywhere under `directory`, recursively. Used by
    /// the fallback lookups below so they find resources regardless of whether SPM flattens
    /// them to the directory root or nests them in a subdirectory.
    private static func firstFileURL(named filename: String, under directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == filename {
            return url
        }
        return nil
    }

    /// A last-resort resource lookup that checks the filesystem directly under
    /// `Bundle.main.resourceURL`, bypassing `Bundle.url(forResource:withExtension:)`'s
    /// internal resource index. Use this alongside that call, not instead of it.
    static func mainResourceURLByPath(forResource name: String, withExtension ext: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return firstFileURL(named: "\(name).\(ext)", under: resourceURL)
    }

    /// A last-resort resource lookup for unpackaged dev/debug runs (`swift run`, Xcode's Run
    /// scheme), where SPM places resources in a `<bundleName>.bundle` folder next to the bare
    /// executable rather than under `Bundle.main.resourceURL`. Hand-rolled instead of going
    /// through the SPM-generated `Bundle.module` accessor, whose fallback path calls
    /// `Swift.fatalError()` when it can't locate the bundle folder — a missing resource here
    /// just returns nil.
    static func devBuildResourceURL(
        forResource name: String,
        withExtension ext: String,
        bundleName: String
    ) -> URL? {
        guard let executableURL = Bundle.main.executableURL else { return nil }
        let bundleDirectory = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent(bundleName)
        return firstFileURL(named: "\(name).\(ext)", under: bundleDirectory)
    }

    /// Resolves a bundled thumbnail across all three lookup tiers (packaged .app resource
    /// index, packaged .app direct filesystem check, unpackaged dev-build layout), trying each
    /// candidate extension in order and skipping one that fails to decode as an image. Logs and
    /// returns nil on a total miss instead of crashing.
    static func editorThumbnailImage(
        forResource name: String,
        extensions: [String],
        bundleName: String,
        context: String
    ) -> NSImage? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.mainResourceURLByPath(forResource: name, withExtension: ext)
                ?? Bundle.devBuildResourceURL(forResource: name, withExtension: ext, bundleName: bundleName),
                let image = NSImage(contentsOf: url)
            {
                return image
            }
        }
        Logger.log(
            message: "\(context): thumbnail not found for '\(name)' (resourcePath: \(Bundle.main.resourcePath ?? "nil"))"
        )
        return nil
    }
}
