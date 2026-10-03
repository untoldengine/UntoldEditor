//
//  SelectionHighlightPassTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import MetalKit
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The highlight pass with several entities selected, drawn by the renderer
/// into its own texture and read back: every selected entity has its box,
/// where the camera sees it.
///
/// The camera stands five units in front of the origin and sees a quarter
/// turn from top to bottom.
@MainActor
final class SelectionHighlightPassTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveEntity: EntityID!
    private var originalActiveCamera: EntityID?
    private var originalPerspective = matrix_identity_float4x4
    private var originalTool: TransformTool!
    private var window: NSWindow!
    private var renderer: UntoldRenderer!
    private var selectionManager: SelectionManager!

    override func setUp() {
        super.setUp()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        guard let created = UntoldRenderer.create() else {
            XCTFail("Failed to initialize the renderer")
            return
        }
        renderer = created
        window.contentView = created.metalView
        created.initResources()

        originalScene = scene
        originalActiveEntity = activeEntity
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalPerspective = renderInfo.perspectiveSpace
        originalTool = EditorViewportSettings.shared.tool

        scene = Scene()
        activeEntity = .invalid
        gizmoTargets = []
        // No gizmo here: the pass under test draws the boxes alone.
        EditorViewportSettings.shared.tool = .select
        selectionManager = SelectionManager()

        let camera = findSceneCamera()
        cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = camera
        renderInfo.perspectiveSpace = matrixPerspectiveRightHand(fovyRadians: .pi / 2, aspectRatio: aspect, nearZ: 0.1, farZ: 100)
    }

    override func tearDown() {
        selectionManager?.clearSelection()
        selectionManager = nil
        gizmoTargets = []
        SelectionHighlights.shared.boxes = []
        EditorViewportSettings.shared.tool = originalTool
        renderInfo.perspectiveSpace = originalPerspective
        CameraSystem.shared.activeCamera = originalActiveCamera
        activeEntity = originalActiveEntity
        scene = originalScene
        originalScene = nil
        renderer = nil
        window = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var target: MTLTexture? {
        textureResources.gizmoColorTexture
    }

    private var aspect: Float {
        guard let target, target.height > 0 else { return 1 }
        return Float(target.width) / Float(target.height)
    }

    private func makeBox(_ name: String, at position: simd_float3, halfExtent: Float = 0.5) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        registerComponent(entityId: entity, componentType: RenderComponent.self)
        scene.get(component: LocalTransformComponent.self, for: entity)?.boundingBox = (
            min: simd_float3(repeating: -halfExtent),
            max: simd_float3(repeating: halfExtent)
        )
        translateTo(entityId: entity, position: position)
        return entity
    }

    /// Runs the highlight pass and hands back what it drew: how bright each
    /// pixel is, row by row from the top.
    private func drawHighlights() throws -> (brightness: [Float], width: Int, height: Int) {
        let texture = try XCTUnwrap(target)
        XCTAssertEqual(texture.pixelFormat, .rgba16Float)
        let commandBuffer = try XCTUnwrap(renderInfo.commandQueue.makeCommandBuffer())

        RenderPasses.highlightExecution(commandBuffer)

        let bytesPerRow = texture.width * 8
        let readBack = try XCTUnwrap(renderInfo.device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared))
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: readBack,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * texture.height
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)

        let channels = readBack.contents().bindMemory(to: UInt16.self, capacity: texture.width * texture.height * 4)
        let brightness = (0 ..< texture.width * texture.height).map { pixel in
            Float(Float16(bitPattern: channels[pixel * 4]))
        }
        return (brightness, texture.width, texture.height)
    }

    /// The pixel a point of the world lands on.
    private func pixel(of point: simd_float3, width: Int, height: Int) throws -> (x: Int, y: Int) {
        let camera = try XCTUnwrap(scene.get(component: CameraComponent.self, for: findSceneCamera()))
        let clip = simd_mul(simd_mul(renderInfo.perspectiveSpace, camera.viewSpace), simd_float4(point, 1))
        let x = (clip.x / clip.w + 1) / 2 * Float(width)
        let y = (1 - clip.y / clip.w) / 2 * Float(height)
        return (Int(x.rounded()), Int(y.rounded()))
    }

    /// Whether something was drawn within `reach` pixels of a pixel.
    private func isDrawn(near pixel: (x: Int, y: Int), in image: (brightness: [Float], width: Int, height: Int), reach: Int = 2) -> Bool {
        for y in max(0, pixel.y - reach) ... min(image.height - 1, pixel.y + reach) {
            for x in max(0, pixel.x - reach) ... min(image.width - 1, pixel.x + reach) where image.brightness[y * image.width + x] > 0.5 {
                return true
            }
        }
        return false
    }

    // MARK: - Tests

    func test_everySelectedEntity_hasItsBoxDrawn_whereTheCameraSeesIt() throws {
        let left = makeBox("Left", at: simd_float3(-2, 0, 0))
        let right = makeBox("Right", at: simd_float3(2, 1, 0))
        _ = makeBox("Not selected", at: simd_float3(0, -2, 0))
        selectionManager.selectEntities([left, right])
        XCTAssertEqual(SelectionHighlights.shared.boxes.count, 2)

        let image = try drawHighlights()

        // The middle of an edge of each box's near face, and a corner of it.
        for point in [
            simd_float3(-2.5, 0, 0.5), simd_float3(-1.5, 0, 0.5), simd_float3(-2, 0.5, 0.5), simd_float3(-2.5, -0.5, 0.5),
            simd_float3(1.5, 1, 0.5), simd_float3(2.5, 1, 0.5), simd_float3(2, 1.5, 0.5), simd_float3(2.5, 0.5, 0.5),
        ] {
            XCTAssertTrue(try isDrawn(near: pixel(of: point, width: image.width, height: image.height), in: image), "an edge at \(point)")
        }
        // Inside a box's face, between the boxes, and around the one not selected.
        for point in [
            simd_float3(-2, 0, 0.5), simd_float3(2, 1, 0.5), simd_float3(0, 0, 0),
            simd_float3(-0.5, -2, 0.5), simd_float3(0, -1.5, 0.5),
        ] {
            XCTAssertFalse(try isDrawn(near: pixel(of: point, width: image.width, height: image.height), in: image), "nothing at \(point)")
        }
    }

    func test_aBoxIsDrawnWhereItsEntityWasMovedTo() throws {
        let first = makeBox("First", at: simd_float3(-2, 0, 0))
        let second = makeBox("Second", at: simd_float3(2, 0, 0))
        selectionManager.selectEntities([first, second])

        translateTo(entityId: first, position: simd_float3(-2, 2, 0))
        let image = try drawHighlights()

        XCTAssertTrue(try isDrawn(near: pixel(of: simd_float3(-2.5, 2, 0.5), width: image.width, height: image.height), in: image))
        XCTAssertFalse(try isDrawn(near: pixel(of: simd_float3(-2.5, 0, 0.5), width: image.width, height: image.height), in: image), "it left where it stood")
    }

    func test_withNothingSelected_nothingIsDrawn() throws {
        _ = makeBox("Box", at: .zero)

        let image = try drawHighlights()

        XCTAssertEqual(image.brightness.max() ?? 0, 0)
    }

    func test_anEntityThatDrawsNothing_hasItsBoxWhereItStands() throws {
        let box = makeBox("Box", at: simd_float3(-2, 0, 0))
        let empty = createEntity()
        registerTransformComponent(entityId: empty)
        registerSceneGraphComponent(entityId: empty)
        translateTo(entityId: empty, position: simd_float3(2, 0, 0))
        selectionManager.selectEntities([box, empty])

        let image = try drawHighlights()

        let half = SelectionHighlightBox.pointExtent / 2
        let edge = try pixel(of: simd_float3(2 - half, 0, half), width: image.width, height: image.height)
        XCTAssertTrue(isDrawn(near: edge, in: image))

        // Lines, not a filled box: nothing is drawn inside its near face. The
        // box stands to the right of the view, so its far face shows through
        // the near one a little to the left: the middle of the near face is
        // next to the far face's right edge, two pixels from it where a point
        // of the window is one pixel. The place looked at is further right,
        // between that edge and the near face's own, and clear of both.
        let inside = try pixel(of: simd_float3(2 + half * 0.6, 0, half), width: image.width, height: image.height)
        let nearEdge = try pixel(of: simd_float3(2 + half, 0, half), width: image.width, height: image.height)
        let farEdge = try pixel(of: simd_float3(2 + half, 0, -half), width: image.width, height: image.height)
        try XCTSkipIf(min(nearEdge.x - inside.x, inside.x - farEdge.x) < 3, "the box is too few pixels wide here to tell lines from a fill")
        XCTAssertFalse(isDrawn(near: inside, in: image, reach: 1), "lines, not a filled box")
    }
}
