//
//  EditorBuildTargetSettings.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import Foundation

/// The platforms a project can be built for, as the toolbar's target menu lists
/// them: the three the engine's build system generates targets for.
enum EditorBuildTarget: String, CaseIterable, Identifiable {
    case macOS
    case iOS
    case visionOS

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .macOS: return "macOS"
        case .iOS: return "iOS"
        case .visionOS: return "visionOS"
        }
    }

    var systemImage: String {
        switch self {
        case .macOS: return "desktopcomputer"
        case .iOS: return "iphone"
        case .visionOS: return "visionpro"
        }
    }

    /// The status bar's "Target: macOS · Metal".
    var statusLabel: String {
        "\(title) · Metal"
    }
}

/// The build target chosen for the open project: what the viewport will preview
/// and what the status bar shows. It builds nothing yet. A preference of the
/// editor, kept per project in `UserDefaults` under the project's root path
/// (the project manifest is read-only today).
final class EditorBuildTargetSettings: ObservableObject {
    static let shared: EditorBuildTargetSettings = {
        let settings = EditorBuildTargetSettings(
            defaults: .standard,
            projectRoot: projectRoot(of: EditorAssetBasePath.shared.basePath)
        )
        settings.follow(EditorAssetBasePath.shared.$basePath.map(projectRoot(of:)).eraseToAnyPublisher())
        return settings
    }()

    static let defaultsKeyPrefix = "editor.buildTarget."

    @Published var target: EditorBuildTarget {
        didSet {
            guard isLoading == false else { return }
            defaults.set(target.rawValue, forKey: key)
        }
    }

    private let defaults: UserDefaults
    private var projectRoot: URL?
    private var isLoading = false
    private var projectSubscription: AnyCancellable?

    init(defaults: UserDefaults, projectRoot: URL? = nil) {
        self.defaults = defaults
        self.projectRoot = projectRoot
        target = Self.storedTarget(in: defaults, key: Self.key(for: projectRoot)) ?? .macOS
    }

    /// Reloads the target whenever the open project changes.
    func follow(_ projectRoots: AnyPublisher<URL?, Never>) {
        projectSubscription = projectRoots
            .receive(on: RunLoop.main)
            .sink { [weak self] root in
                self?.switchProject(to: root)
            }
    }

    /// The project root for an asset base path (`<root>/Sources/<Project>/GameData`).
    static func projectRoot(of basePath: URL?) -> URL? {
        basePath?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private var key: String {
        Self.key(for: projectRoot)
    }

    private static func key(for projectRoot: URL?) -> String {
        defaultsKeyPrefix + (projectRoot?.standardizedFileURL.path ?? "no-project")
    }

    private static func storedTarget(in defaults: UserDefaults, key: String) -> EditorBuildTarget? {
        guard let raw = defaults.string(forKey: key) else {
            return nil
        }
        return EditorBuildTarget(rawValue: raw)
    }

    private func switchProject(to root: URL?) {
        guard root != projectRoot else { return }
        projectRoot = root
        isLoading = true
        target = Self.storedTarget(in: defaults, key: key) ?? .macOS
        isLoading = false
    }
}
