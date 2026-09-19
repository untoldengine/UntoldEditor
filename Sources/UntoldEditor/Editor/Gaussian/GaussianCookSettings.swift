//
//  GaussianCookSettings.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UntoldEngine

/// Editable state behind the sheet. Mirrors `untoldengine export --splat-*`.
struct GaussianCookSettings: Equatable {
    /// Number of progressive tiers; 1 writes a single `<name>.untoldgs`.
    var levelCount: Int = 1
    /// Spherical-harmonics degree to keep; `nil` keeps the source degree.
    var shDegree: Int?
    /// Splats per chunk: 1024 for objects, 4096 for environments.
    var chunkSplats: Int = 1024
    /// Which axis points up in the capture; the cook rotates it to the engine's Y-up frame.
    var upAxis: UntoldGSCaptureUpAxis = .y
    /// Legacy spelling of the 3DGS training convention (−Y up).
    var flipYZ: Bool {
        get { upAxis == .negativeY }
        set { upAxis = newValue ? .negativeY : .y }
    }

    var scale: Float = 1
    var minimumOpacity: Float = 0.005
    /// How many splats the cook may keep; the least important go first. Defaults to the Mac's
    /// runtime cap, the machine the editor runs on. A file meant for Vision Pro needs its cap.
    var splatBudget: GaussianSplatBudget = .mac
    /// Splat count for `GaussianSplatBudget.custom`.
    var customSplatBudget: Int = GaussianSplatBudget.visionPro.maxSplatCount ?? 0
    /// Bake a translation so the capture sits at the origin instead of wherever the
    /// training run left it. The cook reads the source bounds first to compute it.
    var recenter: Bool = false
    var recenterMode: GaussianRecenterMode = .baseOnGround
    /// Per-chunk coarse levels (`UntoldGSCookOptions.coarseLevels`): merged splats a far or
    /// not-yet-paged chunk draws instead of its fine records. Auto bakes two levels for assets
    /// of at least `UntoldGSFormat.coarseLevelsAutomaticMinimumChunks` chunks.
    var coarseLevels: GaussianCoarseLevelChoice = .automatic

    /// Options without recentering: the up-axis rotation and scale only.
    var cookOptions: UntoldGSCookOptions {
        cookOptions(recenteringBounds: nil)
    }

    /// Options with the recenter translation baked in after the up-axis rotation and scale, computed
    /// from the source splat-centre bounds. `nil` bounds (or `recenter` off) leave the
    /// capture where it is.
    func cookOptions(recenteringBounds bounds: (min: simd_float3, max: simd_float3)?) -> UntoldGSCookOptions {
        var options = UntoldGSCookOptions()
        options.log2ChunkSplats = UInt8(max(1, chunkSplats.trailingZeroBitCount))
        options.shDegree = shDegree.map { UInt8($0) }
        options.minimumOpacity = minimumOpacity
        options.maxSplatCount = splatBudget == .custom ? max(1, customSplatBudget) : splatBudget.maxSplatCount
        options.coarseLevels = coarseLevels.policy
        var transform = UntoldGSCookOptions.transform(upAxis: upAxis, scale: scale)
        if recenter, let bounds {
            let translation = gaussianRecenterTranslation(
                boundsMin: bounds.min,
                boundsMax: bounds.max,
                transform: transform,
                mode: recenterMode
            )
            var translate = matrix_identity_float4x4
            translate.columns.3 = simd_float4(translation, 1)
            transform = simd_mul(translate, transform)
        }
        options.transform = transform
        return options
    }
}

/// Where a recentred capture's bounding box ends up.
enum GaussianRecenterMode: String, CaseIterable, Identifiable {
    /// Centred on X and Z with its lowest point on Y = 0: props that stand on the floor.
    case baseOnGround
    /// Box centre at the origin: objects meant to be rotated or floated.
    case centreAtOrigin

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .baseOnGround: "Base on the ground"
        case .centreAtOrigin: "Centre at the origin"
        }
    }
}

/// The cook sheet's "Coarse levels" choices, mapped to `UntoldGSCoarseLevelPolicy`.
enum GaussianCoarseLevelChoice: String, CaseIterable, Identifiable {
    /// Two levels for assets of at least `UntoldGSFormat.coarseLevelsAutomaticMinimumChunks`
    /// chunks, none for smaller ones: the engine's default.
    case automatic
    /// No coarse section, whatever the size.
    case off
    /// One level (1/8 of the fine splats per chunk), whatever the size.
    case one
    /// Two levels (1/8 and 1/64), whatever the size.
    case two

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .off: "Off"
        case .one: "1"
        case .two: "2"
        }
    }

    var policy: UntoldGSCoarseLevelPolicy {
        switch self {
        case .automatic: .automatic
        case .off: .off
        case .one: .levels(count: 1)
        case .two: .levels(count: 2)
        }
    }

    /// The tooltip of the row: what the levels are for and what Auto does.
    static let summary = "Far chunks draw merged splats instead of their fine records, and a paged chunk draws them until its pages arrive. Auto bakes two levels for captures of at least \(UntoldGSFormat.coarseLevelsAutomaticMinimumChunks) chunks."
}

/// Splat budget presets: the per-entity caps the engine runtime enforces per platform
/// (`GaussianRuntimeLimits`), or no cap at all.
enum GaussianSplatBudget: String, CaseIterable, Identifiable {
    /// The engine's mobile per-entity cap (`UntoldGSCookOptions.splatBudgetMobile`): Apple
    /// Vision Pro, iPhone, iPad and Apple TV.
    case visionPro
    /// The engine's Mac per-entity cap (`UntoldGSCookOptions.splatBudgetMac`).
    case mac
    case custom
    case unlimited

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .visionPro: "Vision Pro, iPhone, iPad (\(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMobile)))"
        case .mac: "Mac (\(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMac)))"
        case .custom: "Custom"
        case .unlimited: "Unlimited (may not load)"
        }
    }

    /// The cook option for the preset; `nil` for unlimited and for custom (read the field).
    var maxSplatCount: Int? {
        switch self {
        case .visionPro: UntoldGSCookOptions.splatBudgetMobile
        case .mac: UntoldGSCookOptions.splatBudgetMac
        case .custom, .unlimited: nil
        }
    }

    /// Fixed English grouping, so captions and task rows read the same on every machine.
    static func formatted(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }
}

/// What a budget does to a source of `sourceCount` splats (after the other pruning steps,
/// which usually drop few), for the sheet's caption.
func gaussianBudgetCaption(sourceCount: Int?, maxSplatCount: Int?) -> String {
    guard let sourceCount else {
        return maxSplatCount.map { "Keeps at most \(GaussianSplatBudget.formatted($0)) splats per file." } ?? "No splat budget."
    }
    let source = GaussianSplatBudget.formatted(sourceCount)
    guard let maxSplatCount else {
        return sourceCount > UntoldGSCookOptions.splatBudgetMobile
            ? "\(source) splats in the source; unlimited files above \(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMobile)) do not load on Vision Pro, iPhone or iPad."
            : "\(source) splats in the source, all kept."
    }
    if sourceCount <= maxSplatCount {
        return "\(source) splats in the source, within the budget."
    }
    return "\(source) splats in the source; the budget keeps the \(GaussianSplatBudget.formatted(maxSplatCount)) most important."
}
