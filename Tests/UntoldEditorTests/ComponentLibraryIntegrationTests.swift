//
//  ComponentLibraryIntegrationTests.swift
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
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// Runs the editor's real pipeline end to end inside the test process: locate the SDK of this
/// build, compile a project's component sources with `ComponentCompiler`, load the result with
/// `ComponentLibraryLoader`, and check what the editor relies on afterwards.
///
/// Skipped, never failed, when the toolchain or this build's modules cannot be found.
final class ComponentLibraryIntegrationTests: XCTestCase {
    private static var revision = 9000

    override func setUp() {
        super.setUp()
        ComponentPluginRegistry.shared.removeAll()
        EditorMenuPluginRegistry.shared.removeAll()
        EntityPluginRegistry.shared.removeAll()
        ScenePluginSystem.install()
    }

    override func tearDown() {
        ScenePluginSystem.shared.prepareForReload()
        ComponentPluginRegistry.shared.removeAll()
        EditorMenuPluginRegistry.shared.removeAll()
        EntityPluginRegistry.shared.removeAll()
        super.tearDown()
    }

    func test_projectSourcesCompileLoadAndShareTheEditorsEngine() throws {
        let environment = try Environment.locate(for: Self.self)
        let scratch = try ScratchDirectory("ComponentLibraryIntegration")
        let basePath = try scratch.directory("Sample/Sources/Sample/GameData")
        try scratch.write(Self.componentSource, to: "Sample/Sources/SamplePlugins/Orbiter.swift")
        try scratch.write(Self.extensionSource, to: "Sample/Sources/SamplePlugins/SampleTools.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: environment.sdk)
        let unit = try XCTUnwrap(layout.units.first)
        XCTAssertEqual(unit.sources.count, 2)

        Self.revision += 1
        let request = ComponentCompileRequest(
            unit: unit,
            revision: Self.revision,
            outputDirectory: scratch.url.appendingPathComponent("cache"),
            sdk: environment.sdk,
            toolchain: environment.toolchain
        )
        let result = ComponentCompiler.compile(request)
        if result.succeeded == false, result.output.contains("compiled with") || result.output.contains("cannot be imported") {
            throw XCTSkip("xcrun's swiftc differs from the compiler that built these tests:\n\(result.output)")
        }
        XCTAssertTrue(result.succeeded, "swiftc failed:\n\(result.output)")
        XCTAssertTrue(result.diagnostics.filter { $0.severity == .error }.isEmpty)

        let library = try ComponentLibraryLoader.load(request).get()
        XCTAssertEqual(library.componentNames, ["Orbiter"])
        XCTAssertEqual(library.menuPluginNames, ["SampleTools"])
        XCTAssertEqual(library.entityPluginNames, ["OrbiterEntity"])
        XCTAssertEqual(library.moduleName, "SamplePlugins_r\(Self.revision)")
        XCTAssertGreaterThan(library.byteSize, 0)

        // The loaded component runs against this process's engine.
        let entity = createEntity()
        let orbiter = try XCTUnwrap(ScenePluginSystem.shared.add("Orbiter", to: entity))
        XCTAssertEqual(getEntityName(entityId: entity), "orbiting")
        XCTAssertEqual(orbiter.untoldAttributes().map(\.displayLabel), ["Radius", "Clockwise"])

        // And the loaded extension declares menus the host can build.
        let extensionType = try XCTUnwrap(EditorMenuPluginRegistry.shared.type(named: "SampleTools"))
        XCTAssertEqual(extensionType.init().untoldMenuItems().map(\.menu.identifier), ["debug/Sample/Verbose", "tools/Sample/Reset"])

        // And the loaded kind of entity is on its shelf, and a new one starts with the loaded component.
        XCTAssertEqual(EntityPluginShelfItem.items(on: .primitives).map(\.displayName), ["Orbiter"])
        let placed = try XCTUnwrap(EntityPluginRegistry.shared.instantiate("OrbiterEntity", at: SIMD3<Float>(0, 1, 0)))
        let kind = try XCTUnwrap(ScenePluginSystem.shared.entityPlugin(on: placed))
        XCTAssertEqual(kind.untoldAttributes().map(\.displayLabel), ["Orbit Height"], "the loaded kind's own properties")
        XCTAssertEqual(
            EditorRepresentationRenderer.drawing(for: placed)?.representation.items,
            [.points([SIMD3<Float>(0, 1.5, 0)], tint: SIMD3<Float>(1, 1, 1))],
            "and its editor representation, read from the loaded library"
        )
        XCTAssertEqual(ScenePluginSystem.shared.slots(on: placed).map(\.typeName), ["Orbiter"])
        XCTAssertEqual(getLocalPosition(entityId: placed), SIMD3<Float>(0, 1, 0))

        destroyEntity(entityId: entity)
        destroyEntity(entityId: placed)
    }

    func test_aCompileErrorComesBackAsADiagnosticWithFileAndLine() throws {
        let environment = try Environment.locate(for: Self.self)
        let scratch = try ScratchDirectory("ComponentLibraryIntegration")
        let basePath = try scratch.directory("Broken/Sources/Broken/GameData")
        let file = try scratch.write("""
        import UntoldComponentKit

        final class Broken: ComponentPlugin {
            @UntoldAttribute var speed: Float = 1
            override func onStart() { speeed = 2 }
        }
        """, to: "Broken/Sources/BrokenPlugins/Broken.swift")

        let layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: environment.sdk)
        Self.revision += 1
        let request = try ComponentCompileRequest(
            unit: XCTUnwrap(layout.units.first),
            revision: Self.revision,
            outputDirectory: scratch.url.appendingPathComponent("cache"),
            sdk: environment.sdk,
            toolchain: environment.toolchain
        )

        let result = ComponentCompiler.compile(request)

        XCTAssertFalse(result.succeeded)
        let error = try XCTUnwrap(result.diagnostics.first { $0.severity == .error })
        XCTAssertEqual(error.file, file.path)
        XCTAssertEqual(error.line, 5)
        XCTAssertTrue(error.message.contains("speeed"))
    }

    // MARK: Fixtures

    private static let componentSource = """
    import UntoldComponentKit
    import UntoldEngine

    final class Orbiter: ComponentPlugin {
        @UntoldAttribute(range: 0 ... 50) var radius: Float = 3
        @UntoldAttribute var clockwise = true

        override func onAttach() {
            setEntityName(entityId: entity, name: "orbiting")
        }
    }

    final class OrbiterEntity: EntityPlugin {
        @UntoldAttribute("Orbit Height", range: 0 ... 10) var height: Float = 1.5

        override class var shelf: UntoldEntityShelf { .primitives }

        override func onCreate() {
            add(Orbiter.self)
        }

        override var editorRepresentation: EditorRepresentation {
            EditorRepresentation([.points([SIMD3<Float>(0, height, 0)], tint: SIMD3<Float>(1, 1, 1))])
        }
    }
    """

    private static let extensionSource = """
    #if UNTOLD_EDITOR
    import UntoldComponentKit

    final class SampleTools: EditorMenuPlugin {
        @UntoldMenu(.debug, "Sample/Verbose") var verbose = false
        @UntoldMenu(.tools, "Sample/Reset") var reset = UntoldMenuAction {}
    }
    #endif
    """

    // MARK: Environment

    private struct Environment {
        let sdk: ComponentSDK
        let toolchain: ComponentToolchain

        static func locate(for testClass: AnyClass) throws -> Environment {
            let bundle = Bundle(for: testClass)
            let products = bundle.bundleURL.deletingLastPathComponent().resolvingSymlinksInPath()
            guard let sdk = ComponentSDK.resolveFromBuildProducts(productsDirectory: products) else {
                throw XCTSkip("no engine and kit modules next to \(products.path)")
            }
            guard case let .success(toolchain) = ComponentToolchain.locate() else {
                throw XCTSkip("xcrun swiftc is not available")
            }
            // XCTest loads this bundle with local scope; the editor's executable is always global.
            guard let binary = bundle.executablePath, dlopen(binary, RTLD_NOW | RTLD_NOLOAD | RTLD_GLOBAL) != nil else {
                throw XCTSkip("could not promote the test bundle to global scope")
            }
            return Environment(sdk: sdk, toolchain: toolchain)
        }
    }
}
