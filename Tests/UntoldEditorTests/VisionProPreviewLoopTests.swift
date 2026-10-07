//
//  VisionProPreviewLoopTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Metal
import MetalKit
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The loop that draws for the headset, run with frames of the test's own:
/// the scene is drawn into both eyes from where the editor's camera stood,
/// the engine is switched to stereo and back, and the viewport's mirror gets
/// the left eye.
@MainActor
final class VisionProPreviewLoopTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalRenderEnvironment = false
    private var window: NSWindow!
    private var renderer: UntoldRenderer!

    override func setUp() {
        super.setUp()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
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
        originalActiveCamera = CameraSystem.shared.activeCamera
        // The background is the engine's clear colour, whatever another test
        // left on.
        originalRenderEnvironment = renderEnvironment
        renderEnvironment = false
    }

    override func tearDown() {
        renderEnvironment = originalRenderEnvironment
        renderer?.leaveStereo(viewport: renderer.metalView)
        CameraSystem.shared.activeCamera = originalActiveCamera
        scene = originalScene
        originalScene = nil
        renderer = nil
        window = nil
        super.tearDown()
    }

    /// A lit cube of a unit at the origin, and the active camera five units
    /// in front of it, looking at it.
    private func makeCubeInFrontOfTheCamera() -> EntityID {
        let cube = createEntity()
        setEntityName(entityId: cube, name: "Cube")
        setEntityMeshDirect(entityId: cube, meshes: BasicPrimitives.createCube(extent: 1), assetName: "Cube")
        if let camera = CameraSystem.shared.activeCamera {
            cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        }
        return cube
    }

    private func start() -> VisionProPreviewLoop.Start {
        VisionProPreviewLoop.Start(cameraEye: simd_float3(0, 0, 5), cameraForward: simd_float3(0, 0, -1))
    }

    private func brightness(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Int {
        Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
    }

    func test_theSceneIsDrawnIntoBothEyes_fromWhereTheCameraStood() throws {
        _ = makeCubeInFrontOfTheCamera()
        // The culling of one frame is drawn a frame or two later, as in the
        // engine's own loop: a few frames, and the last one is looked at.
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (256, 192), count: 6)
        renderer.enterStereo()
        let loop = VisionProPreviewLoop(renderer: renderer, frames: frames, start: start(), mirror: nil)

        loop.run()
        try XCTUnwrap(frames.frames.last?.presentedIn).waitUntilCompleted()

        XCTAssertEqual(loop.framesDrawn, 6)
        XCTAssertEqual(renderInfo.viewPort, simd_float2(256, 192), "the engine's targets took the eye's size")
        XCTAssertTrue(renderInfo.isXRStereoMode)
        for (index, eye) in frames.colorTextures.enumerated() {
            let middle = VisionProFakeFrames.pixel(of: eye, x: 128, y: 96)
            let corner = VisionProFakeFrames.pixel(of: eye, x: 4, y: 4)
            // The corner shows the background; the middle shows the lit cube.
            let farCorner = VisionProFakeFrames.pixel(of: eye, x: 251, y: 187)
            XCTAssertEqual(brightness(corner), brightness(farCorner), accuracy: 6, "eye \(index) shows the same background in both corners: \(corner), \(farCorner)")
            XCTAssertGreaterThan(abs(brightness(middle) - brightness(corner)), 40, "eye \(index) shows the cube in the middle: \(middle) over \(corner)")
        }
        XCTAssertEqual(frames.frames[0].phases, ["beginUpdate", "endUpdate", "wait", "beginDrawing", "acquire", "present", "endDrawing"])
        XCTAssertTrue(frames.frames.allSatisfy(\.cameraWasHeldAtPresent), "the keys and the mouse wait while the eyes are drawn")
    }

    func test_theHeadsetIsPlacedAtTheCamera_byItsFirstPose() {
        _ = makeCubeInFrontOfTheCamera()
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (128, 96), count: 1)
        // The headset began a metre and a half up, looking to its left.
        frames.originFromDevice = simd_mul(matrix4x4Translation(0, 1.5, 0), simd_float4x4(simd_quatf(angle: .pi / 2, axis: simd_float3(0, 1, 0))))
        renderer.enterStereo()
        let loop = VisionProPreviewLoop(renderer: renderer, frames: frames, start: start(), mirror: nil)

        XCTAssertNil(loop.placement, "placed by the first pose, not before")
        loop.run()

        let placement = loop.placement
        XCTAssertNotNil(placement)
        if let placement {
            let headset = simd_mul(placement, simd_float4(0, 1.5, 0, 1))
            XCTAssertEqual(headset.x, 0, accuracy: 0.001)
            XCTAssertEqual(headset.y, 0, accuracy: 0.001)
            XCTAssertEqual(headset.z, 5, accuracy: 0.001)
        }
    }

    func test_theHeadsetRidesTheCamera_whereTheKeysFlyIt() throws {
        _ = makeCubeInFrontOfTheCamera()
        let camera = try XCTUnwrap(CameraSystem.shared.activeCamera)
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil)
        frames.showsEyesWhileOpen = true
        renderer.enterStereo()
        let loop = VisionProPreviewLoop(
            renderer: renderer, frames: frames,
            start: VisionProPreviewLoop.Start(camera: camera, cameraEye: .zero, cameraForward: simd_float3(0, 0, -1)),
            mirror: nil
        )
        let thread = Thread { loop.run() }
        thread.start()
        defer { loop.stop() }

        try waitUntil { loop.framesDrawn >= 2 }
        let before = try XCTUnwrap(loop.placement)
        XCTAssertEqual(before.columns.3.z, 5, accuracy: 0.001, "the headset began where the camera stood")

        // The keys flew the camera three units to the right.
        cameraLookAt(entityId: camera, eye: simd_float3(3, 0, 5), target: simd_float3(3, 0, 0), up: simd_float3(0, 1, 0))
        let drawn = loop.framesDrawn
        try waitUntil { loop.framesDrawn >= drawn + 2 }

        let after = try XCTUnwrap(loop.placement)
        XCTAssertEqual(after.columns.3.x, 3, accuracy: 0.001, "the headset went with the camera")
        XCTAssertEqual(after.columns.3.z, 5, accuracy: 0.001)
    }

    private func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(5)
        while condition() == false {
            guard Date() < deadline else {
                throw XCTSkip("the loop did not get there in time")
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func test_theCamerasPose_comesFromWhatTheKeysAndTheMouseMove_notFromLookAtAlone() throws {
        let camera = try XCTUnwrap(CameraSystem.shared.activeCamera)
        cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
        var pose = try XCTUnwrap(VisionProPlacement.pose(of: camera))
        XCTAssertEqual(simd_distance(pose.eye, simd_float3(0, 0, 5)), 0, accuracy: 0.001)
        XCTAssertEqual(simd_distance(pose.forward, simd_float3(0, 0, -1)), 0, accuracy: 0.001)

        // The D key: two to the right. `eye` is left behind, the pose is not.
        moveCameraBy(entityId: camera, delU: 2, delV: 0, delN: 0)
        pose = try XCTUnwrap(VisionProPlacement.pose(of: camera))
        XCTAssertEqual(simd_distance(pose.eye, simd_float3(2, 0, 5)), 0, accuracy: 0.001)
        XCTAssertEqual(getCameraEye(entityId: camera).x, 0, accuracy: 0.001, "what cameraLookAt wrote stays")

        // The mouse: a quarter turn. The W key then flies the way the pose faces.
        rotateCamera(entityId: camera, pitch: 0, yaw: .pi / 2)
        pose = try XCTUnwrap(VisionProPlacement.pose(of: camera))
        XCTAssertEqual(pose.forward.y, 0, accuracy: 0.001, "a turn about the vertical axis keeps the view level")
        XCTAssertEqual(abs(pose.forward.x), 1, accuracy: 0.001)
        let before = pose.eye
        moveCameraBy(entityId: camera, delU: 0, delV: 0, delN: -1)
        let after = try XCTUnwrap(VisionProPlacement.pose(of: camera)).eye
        XCTAssertEqual(simd_distance(after - before, pose.forward), 0, accuracy: 0.01, "W goes where the pose faces")
    }

    func test_theHeadMovingAbout_doesNotMoveThePlacement() throws {
        _ = makeCubeInFrontOfTheCamera()
        let camera = try XCTUnwrap(CameraSystem.shared.activeCamera)
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil)
        frames.showsEyesWhileOpen = true
        frames.originFromDevice = matrix4x4Translation(0, 1.6, 0)
        renderer.enterStereo()
        let loop = VisionProPreviewLoop(
            renderer: renderer, frames: frames,
            start: VisionProPreviewLoop.Start(camera: camera, cameraEye: .zero, cameraForward: simd_float3(0, 0, -1)),
            mirror: nil
        )
        let thread = Thread { loop.run() }
        thread.start()
        defer { loop.stop() }
        try waitUntil { loop.framesDrawn >= 2 }
        let before = try XCTUnwrap(loop.placement)

        // The wearer walks half a metre to the right and a little forward.
        frames.originFromDevice = matrix4x4Translation(0.5, 1.6, -0.3)
        let drawn = loop.framesDrawn
        try waitUntil { loop.framesDrawn >= drawn + 3 }

        let after = try XCTUnwrap(loop.placement)
        for column in 0 ..< 4 {
            XCTAssertEqual(simd_distance(before[column], after[column]), 0, accuracy: 0.001, "the placement stands still while the head moves")
        }
        let cameraPose = try XCTUnwrap(VisionProPlacement.pose(of: camera))
        XCTAssertEqual(simd_distance(cameraPose.eye, simd_float3(0, 0, 5)), 0, accuracy: 0.001, "the head's motion is not written into the camera")
    }

    func test_theLoopFliesTheCamera_byTheKeysHeld_levelAndAtTheEditorsSpeed() throws {
        _ = makeCubeInFrontOfTheCamera()
        let camera = try XCTUnwrap(CameraSystem.shared.activeCamera)
        // The camera looks down at the cube; W must not take it down.
        cameraLookAt(entityId: camera, eye: simd_float3(0, 2, 5), target: .zero, up: simd_float3(0, 1, 0))
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil)
        frames.showsEyesWhileOpen = true
        renderer.enterStereo()
        let loop = VisionProPreviewLoop(
            renderer: renderer, frames: frames,
            start: VisionProPreviewLoop.Start(camera: camera, cameraEye: .zero, cameraForward: simd_float3(0, 0, -1)),
            mirror: nil
        )
        let held = HeldKeys(VisionProFlight.Keys(w: true))
        loop.keysHeld = { held.value }
        loop.flyingSpeed = { 1 }
        let thread = Thread { loop.run() }
        thread.start()
        defer { loop.stop() }
        let started = Date()

        try waitUntil { (VisionProPlacement.pose(of: camera)?.eye.z ?? 5) < 4 }
        let flown = Date().timeIntervalSince(started)
        // W let go: the camera stands, and the headset's placement catches up.
        held.value = VisionProFlight.Keys()
        let drawn = loop.framesDrawn
        try waitUntil { loop.framesDrawn >= drawn + 2 }
        let pose = try XCTUnwrap(VisionProPlacement.pose(of: camera))

        XCTAssertEqual(pose.eye.y, 2, accuracy: 0.001, "W keeps the height")
        XCTAssertEqual(pose.eye.x, 0, accuracy: 0.001)
        XCTAssertLessThan(flown, 2, "a unit at the editor's speed takes a sixth of a second")
        let placement = try XCTUnwrap(loop.placement)
        XCTAssertEqual(placement.columns.3.z, pose.eye.z, accuracy: 0.001, "the headset went along")
    }

    /// The keys a test holds, read from the loop's thread.
    private final class HeldKeys {
        private let lock = NSLock()
        private var keys: VisionProFlight.Keys

        init(_ keys: VisionProFlight.Keys) {
            self.keys = keys
        }

        var value: VisionProFlight.Keys {
            get {
                lock.lock()
                defer { lock.unlock() }
                return keys
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                keys = newValue
            }
        }
    }

    func test_theEditorsOwnFlying_standsDown_whileAHeadsetPreviews() throws {
        // The editor's camera, steered: whatever camera another test left active.
        let camera = findSceneCamera()
        CameraSystem.shared.activeCamera = camera
        InputSystem.shared.cameraControlMode = .idle
        // The camera looks up the hall; the editor's own W would climb.
        cameraLookAt(entityId: camera, eye: simd_float3(0, 1, 5), target: simd_float3(0, 3, 0), up: simd_float3(0, 1, 0))
        let keysBefore = InputSystem.shared.keyState
        InputSystem.shared.keyState.wPressed = true
        defer { InputSystem.shared.keyState = keysBefore }
        let state = VisionProPreviewState.shared
        state.isPreviewing = true
        defer { state.isPreviewing = false }

        renderer.handleSceneInput()

        let held = try XCTUnwrap(VisionProPlacement.pose(of: camera))
        XCTAssertEqual(simd_distance(held.eye, simd_float3(0, 1, 5)), 0, accuracy: 0.001, "the headset's loop flies, the editor's own frame does not")

        state.isPreviewing = false
        renderer.handleSceneInput()
        let flown = try XCTUnwrap(VisionProPlacement.pose(of: camera))
        XCTAssertGreaterThan(flown.eye.y, 1, "without a headset the editor's own W climbs where the camera looks")
    }

    func test_aFrameWithMoreEyesThanTheEngineDraws_getsTwo_andClobbersNone() throws {
        _ = makeCubeInFrontOfTheCamera()
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (128, 96), count: 6, eyes: 3)
        renderer.enterStereo()
        let loop = VisionProPreviewLoop(renderer: renderer, frames: frames, start: start(), mirror: nil)

        loop.run()
        try XCTUnwrap(frames.frames.last?.presentedIn).waitUntilCompleted()

        XCTAssertEqual(loop.framesDrawn, 6)
        for index in 0 ..< 2 {
            let eye = frames.colorTextures[index]
            let middle = VisionProFakeFrames.pixel(of: eye, x: 64, y: 48)
            let corner = VisionProFakeFrames.pixel(of: eye, x: 4, y: 4)
            XCTAssertGreaterThan(abs(brightness(middle) - brightness(corner)), 40, "eye \(index) shows the cube")
        }
        let third = VisionProFakeFrames.pixel(of: frames.colorTextures[2], x: 64, y: 48)
        XCTAssertEqual(brightness(third), 0, "the third eye is left as it was: nothing drawn, nothing clobbered")
    }

    func test_aFrameWithoutEyes_isPresentedWithNothingDrawn() {
        _ = makeCubeInFrontOfTheCamera()
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: 1)
        let loop = VisionProPreviewLoop(renderer: renderer, frames: frames, start: start(), mirror: nil)
        let untracked = VisionProFakeFrames.Frame(eyes: VisionProFrameEyes(originFromDevice: nil, eyes: []))
        let source = SingleFrame(frame: untracked)

        VisionProPreviewLoop(renderer: renderer, frames: source, start: start(), mirror: nil).run()

        XCTAssertEqual(untracked.phases, ["beginUpdate", "endUpdate", "wait", "beginDrawing", "acquire", "present", "endDrawing"])
        XCTAssertNotNil(untracked.presentedIn, "the compositor wants every frame presented")
        XCTAssertEqual(loop.framesDrawn, 0)
        _ = frames
    }

    func test_theMirrorGetsTheLeftEye() throws {
        _ = makeCubeInFrontOfTheCamera()
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (160, 120), count: 1)
        let mirror = VisionProMirror(device: renderInfo.device)
        renderer.enterStereo()

        VisionProPreviewLoop(renderer: renderer, frames: frames, start: start(), mirror: mirror).run()
        try XCTUnwrap(frames.frames.last?.presentedIn).waitUntilCompleted()

        let eye = try XCTUnwrap(mirror.latestEye)
        XCTAssertEqual(eye.width, 160)
        XCTAssertEqual(eye.height, 120)
        XCTAssertEqual(eye.pixelFormat, frames.colorTextures[0].pixelFormat)
    }

    func test_leavingStereo_givesTheViewportItsTargetsBack() {
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (256, 192), count: 1)
        let before = renderInfo.viewPort
        renderer.enterStereo()
        VisionProPreviewLoop(renderer: renderer, frames: frames, start: start(), mirror: nil).run()
        XCTAssertEqual(renderInfo.viewPort, simd_float2(256, 192))

        renderer.leaveStereo(viewport: renderer.metalView)

        XCTAssertFalse(renderInfo.isXRStereoMode)
        XCTAssertEqual(renderInfo.currentEye, 0)
        XCTAssertEqual(renderInfo.viewPort, before)
    }

    /// One frame, then none.
    private final class SingleFrame: VisionProFrameSource {
        private var frame: VisionProFakeFrames.Frame?

        init(frame: VisionProFakeFrames.Frame) {
            self.frame = frame
        }

        func nextFrame() -> VisionProFrame? {
            defer { frame = nil }
            return frame
        }

        func stop() {
            frame = nil
        }
    }
}
