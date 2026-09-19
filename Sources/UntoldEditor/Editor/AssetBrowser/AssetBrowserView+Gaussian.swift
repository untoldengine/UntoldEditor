//
//  AssetBrowserView+Gaussian.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

extension AssetBrowserView {
    /// Opens the cook sheet for the `.ply`/`.spz` files among `urls`. With none there is
    /// nothing to configure, so the status line says so instead of an empty sheet.
    func requestGaussianCook(of urls: [URL]) {
        guard let request = GaussianCookRequest(sources: urls) else {
            showStatus("Select .ply/.spz files to cook", isError: true)
            return
        }
        pendingGaussianCook = request
    }

    /// Cooks each `.ply`/`.spz` to `.untoldgs` with the sheet's current settings. Every file
    /// is its own job in the Tasks panel (the context-menu cook and an import batch share
    /// this path); the bakes run one after another on the cook queue and the browser
    /// refreshes as each one lands. A failed cook leaves the source file untouched.
    func cookGaussianSources(_ plyURLs: [URL]) {
        let settings = gaussianCookSettings
        let gaussianRoot = assetBasePath?.appendingPathComponent(AssetCategory.gaussians.rawValue, isDirectory: true)
        showStatus(plyURLs.count == 1
            ? "Cooking \(plyURLs[0].lastPathComponent)..."
            : "Cooking \(plyURLs.count) Gaussian files (see Tasks)...")
        for plyURL in plyURLs {
            let name = plyURL.lastPathComponent
            let outputDirectory = gaussianRoot.flatMap { root -> URL? in
                plyURL.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
                    ? gaussianPackageFolder(for: plyURL, in: root)
                    : nil
            }
            cookGaussianPLYTracked(plyURL: plyURL, settings: settings, outputDirectory: outputDirectory) { result in
                switch result {
                case let .success(bake):
                    loadAssets()
                    let report = bake.cookReport
                    let names = bake.tiers.map(\.url.lastPathComponent).joined(separator: ", ")
                    showStatus("Cooked \(report.keptSplatCount) of \(report.inputSplatCount) splats → \(names)")
                    Logger.log(message: "Cooked \(name): kept \(report.keptSplatCount) of \(report.inputSplatCount) (opacity \(report.prunedByOpacity), degenerate \(report.prunedByDegenerateGeometry), crop \(report.prunedByCrop)), SH degree \(report.shDegree)")
                case let .failure(error) where error is GaussianCookCancelledError:
                    showStatus("Cook cancelled for \(name); the source file is unchanged")
                case let .failure(error):
                    let detail = gaussianCookFailureDetail(error)
                    showStatus("Cook failed for \(name): \(detail)", isError: true)
                    Logger.log(message: "❌ Cook failed for \(name): \(detail). The source file is unchanged; re-cook from its context menu.")
                }
            }
        }
    }
}
