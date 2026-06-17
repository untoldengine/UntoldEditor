//
//  DemoGalleryViewTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import SwiftUI
@testable import UntoldEditor
import XCTest

#if canImport(AppKit)
    final class DemoGalleryViewTests: XCTestCase {
        func test_demoSceneCatalog_wrapsStarterStreamsForExploreMode() {
            XCTAssertEqual(demoSceneCatalog.count, starterStreamModels.count)
            XCTAssertEqual(demoSceneCatalog.map(\.id), starterStreamModels.map(\.id))
            XCTAssertTrue(demoSceneCatalog.allSatisfy { $0.cameraFrame != nil })
            XCTAssertTrue(demoSceneCatalog.allSatisfy { !$0.title.isEmpty })
            XCTAssertTrue(demoSceneCatalog.allSatisfy { !$0.subtitle.isEmpty })
            XCTAssertTrue(demoSceneCatalog.allSatisfy { !$0.systemImageName.isEmpty })
        }

        func test_demoSceneCatalog_usesRemoteManifestSourcesForCurrentStarterDemos() {
            for demo in demoSceneCatalog {
                guard case let .remoteManifest(url) = demo.source else {
                    XCTFail("Expected current starter demo to use a remote manifest source.")
                    return
                }

                XCTAssertEqual(url.pathExtension, "json")
                XCTAssertEqual(demo.source.resolvedURL, url)
            }
        }

        func test_demoGalleryView_wiresCallbacks() {
            let firstDemo = demoSceneCatalog[0]
            var selectedDemoId: String?
            var didCreateProject = false
            var didOpenProject = false
            var didOpenFullEditor = false

            let sut = DemoGalleryView(
                demos: demoSceneCatalog,
                onDemoSelected: { selectedDemoId = $0.id },
                onCreateProject: { didCreateProject = true },
                onOpenProject: { didOpenProject = true },
                onOpenFullEditor: { didOpenFullEditor = true }
            )

            sut.onDemoSelected(firstDemo)
            sut.onCreateProject()
            sut.onOpenProject()
            sut.onOpenFullEditor()

            XCTAssertEqual(selectedDemoId, firstDemo.id)
            XCTAssertTrue(didCreateProject)
            XCTAssertTrue(didOpenProject)
            XCTAssertTrue(didOpenFullEditor)
        }

        func test_demoGalleryView_composesWithoutCrash() {
            let sut = DemoGalleryView(
                demos: demoSceneCatalog,
                onDemoSelected: { _ in },
                onCreateProject: {},
                onOpenProject: {},
                onOpenFullEditor: {}
            )

            let host = NSHostingController(rootView: sut)
            XCTAssertNotNil(host.view)
        }
    }
#endif
