//
//  GaussianRuntimeSettings.swift
//  UntoldEditor
//
//  The editor's Gaussian splat runtime policy: the working set the frame compacts, sorts and
//  draws (View > Splat Debug > Working Set). The engine's Mac default, 6 M splats, costs about
//  55 ms of GPU per 1080p frame on an M4 Max once a large capture fills it (about 11 ms per
//  million drawn splats); the editor defaults to 3 M, about 30 ms, and the screen-weighted
//  quotas and the coarse levels make the truncation graceful. Shared between the AppKit menu
//  (radio checkmarks) and SwiftUI; persisted in `UserDefaults`.
//

import Foundation
import UntoldEngine

/// The working-set sizes the menu offers (`GaussianRuntimeLimits.workingSetSplatsOverride`).
enum EditorSplatWorkingSet: String, CaseIterable {
    case oneMillion
    case twoMillion
    case threeMillion
    case fourMillion
    /// The engine's platform figure (`GaussianRuntimeLimits.workingSetSplats`), no override.
    case engineDefault

    /// The editor's default: 3 M splats, about 30 ms of GPU per 1080p frame on an M4 Max.
    static let editorDefault = EditorSplatWorkingSet.threeMillion

    /// The override to install; nil restores the engine's default.
    var splats: Int? {
        switch self {
        case .oneMillion: 1_000_000
        case .twoMillion: 2_000_000
        case .threeMillion: 3_000_000
        case .fourMillion: 4_000_000
        case .engineDefault: nil
        }
    }

    /// What the frame draws with this choice, in splats.
    var splatsInEffect: Int {
        splats ?? GaussianRuntimeLimits.workingSetSplats
    }

    var title: String {
        switch self {
        case .engineDefault: "Engine Default (\(GaussianSplatBudget.formatted(GaussianRuntimeLimits.workingSetSplats)))"
        default: GaussianSplatBudget.formatted(splatsInEffect) + (self == .editorDefault ? " (Editor Default)" : "")
        }
    }

    /// The tooltip: the cost of the choice on the reference machine.
    var summary: String {
        let millions = Double(splatsInEffect) / 1_000_000
        let frameMs = Int((millions * 11).rounded())
        return "The frame compacts, sorts and draws at most \(GaussianSplatBudget.formatted(splatsInEffect)) splats across every splat entity: about \(frameMs) ms of GPU per 1080p frame on an M4 Max when a large capture fills it, \(gaussianCookFormatBytes(splatsInEffect * 72 * 3)) of working-set buffers."
    }
}

/// The View > Splat Debug > Working Set choice: the working set the frame draws from,
/// installed as the engine override once the editor has a renderer (`activate()`).
final class EditorGaussianRuntimeSettings: ObservableObject {
    static let shared = EditorGaussianRuntimeSettings(defaults: .standard)

    static let workingSetDefaultsKey = "editor.gaussian.workingSet"

    @Published var workingSet: EditorSplatWorkingSet {
        didSet {
            defaults.set(workingSet.rawValue, forKey: Self.workingSetDefaultsKey)
            guard isActivated else { return }
            applyToEngine()
        }
    }

    /// Set once the editor has an engine to configure (`activate()`); before that the choice
    /// only records the preference, so a test or a tool that never renders leaves the engine's
    /// limits alone.
    private(set) var isActivated = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.workingSetDefaultsKey),
           let saved = EditorSplatWorkingSet(rawValue: raw)
        {
            workingSet = saved
        } else {
            workingSet = .editorDefault
        }
    }

    /// Installs the preference. Called once the renderer exists.
    func activate() {
        isActivated = true
        applyToEngine()
    }

    /// Restores the engine's default (tests).
    func deactivate() {
        guard isActivated else { return }
        isActivated = false
        GaussianRuntimeLimits.workingSetSplatsOverride = nil
    }

    private func applyToEngine() {
        // The shared working set resizes at the next frame: it grows to the new budget when a
        // frame needs it and shrinks when it is above the budget (GaussianSharedWorkingSet).
        GaussianRuntimeLimits.workingSetSplatsOverride = workingSet.splats
    }
}
