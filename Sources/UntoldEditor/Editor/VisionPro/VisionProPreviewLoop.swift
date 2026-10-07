//
//  VisionProPreviewLoop.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import Metal
import QuartzCore
import simd
import UntoldEngine

/// Draws the scene for the headset, frame after frame, on a thread of its
/// own: the headset asks for frames at its own rate, and the compositor
/// wants each frame's update, wait and drawing in order. It drives the
/// engine as the engine's own visionOS loop does, through the engine's
/// public API: one update, the culling once, then each eye.
final class VisionProPreviewLoop {
    /// The camera the headset rides, and where it stood when the preview
    /// began. The headset, as it stood when its first tracked pose arrived,
    /// stands where the camera stands and faces its way; the camera's pose is
    /// read again every frame, so the keys and the mouse carry the headset.
    struct Start {
        /// The engine's active camera at the start, whose pose the headset
        /// follows; the loop ends once another takes its place, as a scene
        /// load or a change of camera does. Nil keeps the pose below, for tests.
        var camera: EntityID?
        let cameraEye: simd_float3
        let cameraForward: simd_float3
    }

    private let renderer: UntoldRenderer
    private let frames: VisionProFrameSource
    private let start: Start
    private let mirror: VisionProMirror?

    private let lock = NSLock()
    private var stopped = false
    private var sceneFromOrigin: simd_float4x4?
    private var originFromScene = matrix_identity_float4x4
    /// The headset's first tracked pose: what stands on the camera.
    private var deviceStart: simd_float4x4?
    /// One per eye the engine draws: its stereo path has two, left and right
    /// (`renderInfo.currentEye`). A frame with more eyes gets these two drawn
    /// and the rest left, said once.
    private let passDescriptors = [MTLRenderPassDescriptor(), MTLRenderPassDescriptor()]
    private var saidTooManyEyes = false

    /// Frames in which the eyes were drawn, for the tests.
    private(set) var framesDrawn = 0

    /// The fly keys held now and the editor's flying speed, read once a
    /// frame; tests put their own here.
    var keysHeld: () -> VisionProFlight.Keys = {
        let state = InputSystem.shared.keyState
        return VisionProFlight.Keys(w: state.wPressed, a: state.aPressed, s: state.sPressed, d: state.dPressed, q: state.qPressed, e: state.ePressed)
    }

    var flyingSpeed: () -> Float = { EditorViewportSettings.shared.speedMultiplier }
    private var lastFlight: CFTimeInterval?

    init(renderer: UntoldRenderer, frames: VisionProFrameSource, start: Start, mirror: VisionProMirror?) {
        self.renderer = renderer
        self.frames = frames
        self.start = start
        self.mirror = mirror
    }

    /// Where the headset's coordinates land in the scene, once its first
    /// tracked pose placed it on the camera; nil before. It follows the
    /// camera frame by frame.
    var placement: simd_float4x4? {
        lock.lock()
        defer { lock.unlock() }
        return sceneFromOrigin
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Draws frames until the source ends, `stop()` is called, or the camera
    /// the headset drives is no longer the engine's active one. Blocking:
    /// call it on a thread of its own.
    func run() {
        while isStopped == false, drivesTheActiveCamera, let frame = frames.nextFrame() {
            autoreleasepool {
                draw(frame)
            }
        }
    }

    private var drivesTheActiveCamera: Bool {
        guard let camera = start.camera else { return true }
        return CameraSystem.shared.activeCamera == camera
    }

    /// Ends the loop after the frame it is on.
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        frames.stop()
    }

    private func draw(_ frame: VisionProFrame) {
        frame.beginUpdate()
        fly()
        // The progressive loader wants the main thread, as the engine's own
        // loop gives it.
        DispatchQueue.main.async {
            ProgressiveAssetLoader.shared.tick()
        }
        let loading = AssetLoadingGate.shared.isLoadingAny

        // The engine's own loop would write the headset's position into the
        // camera here, for streaming and LOD to follow it. Not this one: the
        // camera is what the keys and the mouse fly and what the headset rides,
        // read back every frame, so a write would feed the head's motion back
        // into the placement. Streaming, LOD and shading go by the camera,
        // which the headset stays within a room of.
        if !loading {
            renderer.updateXR(useExternalStatsLifecycle: true)
        }
        frame.endUpdate()

        frame.waitForDrawingTime()
        guard isStopped == false, frame.beginDrawing() else {
            return
        }
        // No eyes this frame: the compositor's frame is left as it is, as
        // the engine's own loop leaves it.
        guard let acquired = frame.acquireEyes() else {
            return
        }
        submit(acquired, frame: frame, loading: loading)
        frame.endDrawing()
        renderer.finalizeXRStatsAndMonitors(frameStartTime: 0)
    }

    private func submit(_ acquired: VisionProFrameEyes, frame: VisionProFrame, loading: Bool) {
        commandBufferSemaphore.wait()
        guard let commandBuffer = renderInfo.commandQueue.makeCommandBuffer() else {
            commandBufferSemaphore.signal()
            return
        }
        commandBuffer.label = "Vision Pro Preview"
        renderInfo.currentInFlightFrameSlot = acquireUniformFrameSlot()
        if let first = acquired.eyes.first {
            renderer.fitStereoTargets(to: simd_float2(Float(first.colorTexture.width), Float(first.colorTexture.height)))
        }
        if !loading {
            visibleEntityIds = tripleVisibleEntities.snapshotForRead(frame: cullFrameIndex)
        }

        // No move of the camera from the keys or the mouse until both eyes
        // are drawn and the frame is handed over: `VisionProPreviewState.cameraLock`.
        let drawsEyes = acquired.originFromDevice != nil && acquired.eyes.isEmpty == false
        if drawsEyes {
            VisionProPreviewState.shared.cameraLock.lock()
        }
        defer {
            if drawsEyes {
                VisionProPreviewState.shared.cameraLock.unlock()
            }
        }
        if let originFromDevice = acquired.originFromDevice, acquired.eyes.isEmpty == false {
            place(originFromDevice)

            // The culling and the splat sort once for both eyes, as the
            // engine's own loop does.
            if !loading {
                SceneRootTransform.shared.updateIfNeeded()
                performFrustumCulling(commandBuffer: commandBuffer)
                executeGaussianFrustumCulling(commandBuffer)
                executeGaussianPreprocess(commandBuffer)
                executeRadixSort(commandBuffer)
            }

            if acquired.eyes.count > passDescriptors.count, saidTooManyEyes == false {
                saidTooManyEyes = true
                Logger.log(message: "Vision Pro preview: the headset's frame has \(acquired.eyes.count) eyes; the engine draws two, the rest are left blank.")
            }
            for (index, eye) in acquired.eyes.prefix(passDescriptors.count).enumerated() {
                let descriptor = passDescriptors[index]
                descriptor.colorAttachments[0].texture = eye.colorTexture
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].storeAction = .store
                descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                descriptor.depthAttachment.texture = eye.depthTexture
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.storeAction = .store
                // Reverse Z, as the engine keeps depth.
                descriptor.depthAttachment.clearDepth = 0

                renderInfo.currentEye = index
                renderer.renderXR(
                    commandBuffer: commandBuffer,
                    passDescriptor: descriptor,
                    viewMatrix: simd_mul(eye.viewFromOrigin, originFromScene),
                    projectionMatrix: eye.projection,
                    eyeIndex: index
                )
            }
            buildHZBDepthPyramid(commandBuffer)
            if let left = acquired.eyes.first {
                mirror?.copy(eye: left.colorTexture, commandBuffer: commandBuffer)
            }
            framesDrawn += 1
        }

        frame.present(commandBuffer: commandBuffer)
        commandBuffer.addCompletedHandler { _ in
            commandBufferSemaphore.signal()
        }
        commandBuffer.commit()
    }

    /// Flies the camera the headset rides by the keys held, once a frame, by
    /// the time since the last frame: level, as `VisionProFlight` has it. On
    /// this thread, so that every frame of the headset sees a fresh step, and
    /// between the eyes of two frames, as every move of the camera is.
    private func fly() {
        guard let camera = start.camera else {
            return
        }
        let now = CACurrentMediaTime()
        defer { lastFlight = now }
        guard let last = lastFlight else {
            return
        }
        let deltaTime = Float(min(max(now - last, 0), 0.1))
        VisionProPreviewState.shared.steerCamera {
            VisionProFlight.fly(camera: camera, keys: keysHeld(), speed: flyingSpeed(), deltaTime: deltaTime)
        }
    }

    /// Puts the headset, as it first stood, on the camera as it stands now.
    private func place(_ originFromDevice: simd_float4x4) {
        let (eye, forward) = cameraPose()
        lock.lock()
        defer { lock.unlock() }
        if deviceStart == nil {
            deviceStart = originFromDevice
        }
        let placed = VisionProPlacement.sceneFromOrigin(
            cameraEye: eye,
            cameraForward: forward,
            originFromDevice: deviceStart ?? originFromDevice
        )
        sceneFromOrigin = placed
        originFromScene = simd_inverse(placed)
    }

    /// Where the camera stands and faces now: the camera the headset rides,
    /// or the start's pose when there is none.
    private func cameraPose() -> (eye: simd_float3, forward: simd_float3) {
        guard let camera = start.camera, let pose = VisionProPlacement.pose(of: camera) else {
            return (start.cameraEye, start.cameraForward)
        }
        return pose
    }
}
