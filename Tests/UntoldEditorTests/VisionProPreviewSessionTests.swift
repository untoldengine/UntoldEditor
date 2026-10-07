//
//  VisionProPreviewSessionTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import MetalKit
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The preview as the View menu drives it: asked for, shown once the space
/// opens, ended from the menu or by the headset, with the editor put back.
@MainActor
final class VisionProPreviewSessionTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false
    private var window: NSWindow!
    private var renderer: UntoldRenderer!
    private var session: VisionProPreviewSession!

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
        originalGameMode = gameMode
        gameMode = false
        session = VisionProPreviewSession()
        session.renderer = renderer
        session.setAvailable(true)
    }

    override func tearDown() {
        session.end()
        session = nil
        VisionProPreviewState.shared.isPreviewing = false
        gameMode = originalGameMode
        CameraSystem.shared.activeCamera = originalActiveCamera
        scene = originalScene
        originalScene = nil
        renderer = nil
        window = nil
        super.tearDown()
    }

    /// Waits until the session is in `state`, or fails.
    private func waitForState(_ state: VisionProPreviewSession.State, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while session.state != state, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(session.state, state, file: file, line: line)
    }

    func test_beforeTheBridgeSaysSo_thereIsNoPreview() {
        let fresh = VisionProPreviewSession()

        XCTAssertEqual(fresh.state, .unavailable)
        fresh.begin()
        XCTAssertEqual(fresh.state, .unavailable)
    }

    func test_askingForThePreview_opensTheSpace_andAHeadsetThatDeclines_leavesItIdle() {
        var asked = 0
        session.openSpace = {
            asked += 1
            return false
        }

        session.begin()

        XCTAssertEqual(session.state, .connecting)
        waitForState(.idle)
        XCTAssertEqual(asked, 1)
    }

    func test_whileTheSpaceOpens_theSceneIsPreviewed_andTheEditorIsLockedOut() {
        session.openSpace = { true }
        session.begin()
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil)

        session.spaceDidOpen(frames: frames)

        XCTAssertEqual(session.state, .previewing)
        XCTAssertTrue(VisionProPreviewState.shared.isPreviewing)
        XCTAssertTrue(ViewportCameras.isLockedPreview)
        XCTAssertEqual(ViewportCameras.steered, findSceneCamera(), "the keys and the mouse fly the camera the headset rides")
        XCTAssertTrue(renderInfo.isXRStereoMode)
        XCTAssertFalse(renderer.metalView.delegate === renderer, "the viewport shows the mirror")
    }

    func test_steeringTheCamera_waitsForTheEyes_onlyWhileAHeadsetPreviews() {
        let state = VisionProPreviewState.shared
        state.isPreviewing = false
        state.steerCamera {
            XCTAssertTrue(state.cameraLock.try(), "nothing is held while no headset previews")
            state.cameraLock.unlock()
        }

        state.isPreviewing = true
        defer { state.isPreviewing = false }
        state.steerCamera {
            XCTAssertFalse(state.cameraLock.try(), "a move of the camera holds what the loop holds while it draws the eyes")
        }
    }

    func test_escapeEndsThePreview_fromTheMomentItIsAskedFor() {
        XCTAssertTrue(VisionProPreviewSession.endsOnKey(53, state: .connecting))
        XCTAssertTrue(VisionProPreviewSession.endsOnKey(53, state: .previewing))
        XCTAssertFalse(VisionProPreviewSession.endsOnKey(53, state: .idle))
        XCTAssertFalse(VisionProPreviewSession.endsOnKey(53, state: .ending))
        XCTAssertFalse(VisionProPreviewSession.endsOnKey(13, state: .previewing), "W flies")
    }

    func test_thePointerCapture_startsAndStopsOnce_andTurnsOnlyWhileHeld() {
        var turns: [simd_float2] = []
        let capture = VisionProPointerCapture { turns.append($0) }
        XCTAssertFalse(capture.isCapturing)
        capture.start()
        capture.start()
        XCTAssertTrue(capture.isCapturing)
        capture.stop()
        capture.stop()
        XCTAssertFalse(capture.isCapturing)
        XCTAssertTrue(turns.isEmpty)
    }

    func test_aLoopThatOutlivesTheStop_putsTheEditorBack_whenItEnds() {
        session.loopStopTimeout = 0.05
        var dismissed = 0
        session.openSpace = { true }
        session.dismissSpace = { dismissed += 1 }
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil)
        // The loop is held in the middle of a frame, as a command buffer that
        // never completes would hold it.
        let gate = DispatchSemaphore(value: 0)
        let arrived = DispatchSemaphore(value: 0)
        frames.beforeEachFrame = {
            arrived.signal()
            gate.wait()
        }
        session.begin()
        session.spaceDidOpen(frames: frames)
        XCTAssertEqual(arrived.wait(timeout: .now() + .seconds(5)), .success, "the loop reached the frame it is held in")

        session.end()

        XCTAssertEqual(session.state, .ending, "the ending waits for the loop")
        XCTAssertTrue(session.restoreWaitsForTheLoop)
        XCTAssertTrue(VisionProPreviewState.shared.isPreviewing, "the loop still draws: nothing is taken from under it")
        XCTAssertTrue(renderInfo.isXRStereoMode)
        XCTAssertFalse(renderer.metalView.delegate === renderer)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(session.state, .ending, "the dismiss alone does not end the ending")

        gate.signal()
        waitForState(.idle)

        XCTAssertFalse(session.restoreWaitsForTheLoop)
        XCTAssertFalse(VisionProPreviewState.shared.isPreviewing)
        XCTAssertFalse(renderInfo.isXRStereoMode)
        XCTAssertTrue(renderer.metalView.delegate === renderer)
        XCTAssertEqual(dismissed, 1)
    }

    func test_endingThePreview_putsTheEditorBack() {
        let camera = findSceneCamera()
        cameraLookAt(entityId: camera, eye: simd_float3(1, 2, 3), target: .zero, up: simd_float3(0, 1, 0))
        var dismissed = 0
        session.openSpace = { true }
        session.dismissSpace = { dismissed += 1 }
        session.begin()
        session.spaceDidOpen(frames: VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil))
        // The keys flew the camera meanwhile.
        cameraLookAt(entityId: camera, eye: simd_float3(4, 5, 6), target: .zero, up: simd_float3(0, 1, 0))

        session.end()

        XCTAssertFalse(VisionProPreviewState.shared.isPreviewing)
        XCTAssertFalse(ViewportCameras.isLockedPreview)
        XCTAssertFalse(renderInfo.isXRStereoMode)
        XCTAssertTrue(renderer.metalView.delegate === renderer)
        let eye = getCameraEye(entityId: camera)
        XCTAssertEqual(eye.x, 4, accuracy: 0.001, "the camera stays where it was flown")
        XCTAssertEqual(eye.y, 5, accuracy: 0.001)
        XCTAssertEqual(eye.z, 6, accuracy: 0.001)
        waitForState(.idle)
        XCTAssertEqual(dismissed, 1)
    }

    func test_aHeadsetThatCloses_endsThePreviewByItself() {
        session.openSpace = { true }
        session.begin()
        let frames = VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil)
        session.spaceDidOpen(frames: frames)

        frames.stop()

        waitForState(.idle)
        XCTAssertFalse(VisionProPreviewState.shared.isPreviewing)
        XCTAssertFalse(renderInfo.isXRStereoMode)
    }

    func test_anotherCameraTakingOver_endsThePreview_andLeavesThatCameraAlone() {
        session.openSpace = { true }
        session.begin()
        session.spaceDidOpen(frames: VisionProFakeFrames(device: renderInfo.device, eyeSize: (64, 48), count: nil))

        // The scene was loaded again: a new camera is the active one.
        let newCamera = createEntity()
        registerComponent(entityId: newCamera, componentType: CameraComponent.self)
        cameraLookAt(entityId: newCamera, eye: simd_float3(7, 8, 9), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = newCamera

        waitForState(.idle)
        XCTAssertFalse(VisionProPreviewState.shared.isPreviewing)
        XCTAssertFalse(renderInfo.isXRStereoMode)
        let eye = getCameraEye(entityId: newCamera)
        XCTAssertEqual(eye.x, 7, accuracy: 0.001, "the new camera is left where the scene put it")
        XCTAssertEqual(eye.y, 8, accuracy: 0.001)
        XCTAssertEqual(eye.z, 9, accuracy: 0.001)
    }

    func test_thePreviewIsNotAskedFor_whileTheGamePlays() {
        gameMode = true
        session.openSpace = { true }

        session.begin()

        XCTAssertEqual(session.state, .idle)
    }

    func test_theMenuItem_followsTheState() {
        XCTAssertTrue(VisionProPreviewSession.menuItem(for: .unavailable, isPlaying: false).isHidden)
        let idle = VisionProPreviewSession.menuItem(for: .idle, isPlaying: false)
        XCTAssertEqual(idle.title, "Preview on Apple Vision Pro")
        XCTAssertTrue(idle.isEnabled)
        XCTAssertFalse(idle.isHidden)
        XCTAssertFalse(VisionProPreviewSession.menuItem(for: .idle, isPlaying: true).isEnabled, "not while the game plays")
        let previewing = VisionProPreviewSession.menuItem(for: .previewing, isPlaying: false)
        XCTAssertEqual(previewing.title, "Stop the Preview on Apple Vision Pro")
        XCTAssertTrue(previewing.isEnabled)
        XCTAssertEqual(VisionProPreviewSession.menuItem(for: .connecting, isPlaying: false).title, "Stop the Preview on Apple Vision Pro")
        XCTAssertFalse(VisionProPreviewSession.menuItem(for: .ending, isPlaying: false).isEnabled)
    }
}
