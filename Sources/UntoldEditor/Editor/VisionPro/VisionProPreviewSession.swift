//
//  VisionProPreviewSession.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
import Combine
import Foundation
import MetalKit
import simd
import UntoldEngine

/// The preview of the scene on an Apple Vision Pro: asked for from the View
/// menu, shown once the headset's wearer accepts, ended from the menu or by
/// the headset. It owns the loop that draws for the headset and puts the
/// editor back as it was. Main thread only, as the editor's other settings.
final class VisionProPreviewSession: ObservableObject {
    static let shared = VisionProPreviewSession()

    enum State: Equatable {
        /// This Mac cannot show a scene on a headset: before macOS 26, or
        /// the system says so.
        case unavailable
        case idle
        /// Asked for; the headset's wearer is being asked to accept.
        case connecting
        case previewing
        case ending
    }

    @Published private(set) var state: State = .unavailable {
        didSet {
            // Escape ends a preview from the moment it is asked for.
            if state == .connecting {
                watchEscape()
            } else if state == .idle || state == .unavailable {
                unwatchEscape()
            }
        }
    }

    private var escapeMonitor: Any?

    /// Opens the remote space; true when it opened. Handed in by the bridge
    /// view, which has SwiftUI's action for it.
    var openSpace: (() async -> Bool)?
    /// Closes the remote space. Handed in by the bridge view too.
    var dismissSpace: (() async -> Void)?
    /// The renderer that draws the viewport, handed in by the editor view.
    weak var renderer: UntoldRenderer?

    private var loop: VisionProPreviewLoop?
    private var loopDone: DispatchSemaphore?
    private var mirror: VisionProMirror?
    private var pointer: VisionProPointerCapture?
    /// How long `end()` waits for the loop to finish the frame it is on
    /// before leaving the rest to the loop's own end; tests shorten it.
    var loopStopTimeout: TimeInterval = 2
    /// The loop outlived the wait: the editor is put back when it ends.
    private(set) var restoreWaitsForTheLoop = false

    var isPreviewing: Bool {
        state == .previewing
    }

    /// Whether this Mac can show a scene on a headset, from the bridge view.
    func setAvailable(_ available: Bool) {
        if available, state == .unavailable {
            state = .idle
        } else if available == false, state == .idle {
            state = .unavailable
        }
    }

    /// The View menu's item: Preview, or Stop while one is asked for or shown.
    func toggle() {
        switch state {
        case .idle:
            begin()
        case .connecting, .previewing:
            end()
        case .unavailable, .ending:
            break
        }
    }

    /// Asks for the preview: the system asks the headset's wearer, and the
    /// space opens on acceptance. Not while the game plays.
    func begin() {
        guard state == .idle, let openSpace, renderer != nil, ViewportCameras.isPlaying == false else {
            return
        }
        state = .connecting
        Task { @MainActor [weak self] in
            let opened = await openSpace()
            guard let self, opened == false, state == .connecting else { return }
            state = .idle
        }
    }

    /// The compositor handed the layer over: the headset shows the space.
    func spaceDidOpen(frames: VisionProFrameSource) {
        guard let renderer, state == .connecting || state == .idle else {
            frames.stop()
            return
        }
        startLoop(renderer: renderer, frames: frames)
        state = .previewing
    }

    /// Ends the preview: the loop stops, the editor is put back, the space
    /// closes.
    func end() {
        guard state == .connecting || state == .previewing else {
            return
        }
        let wasPreviewing = state == .previewing
        state = .ending
        if wasPreviewing {
            stopLoopAndRestore()
        }
        Task { @MainActor [weak self] in
            await self?.dismissSpace?()
            // A loop that outlived the wait puts the editor back, and ends
            // the ending, when it ends.
            guard let self, state == .ending, restoreWaitsForTheLoop == false else { return }
            state = .idle
        }
    }

    /// The loop's thread ended: the headset closed the space, the stream
    /// broke, or a loop that outlived `end()`'s wait is done at last.
    private func loopDidEnd() {
        if restoreWaitsForTheLoop {
            restoreEditor()
            if state == .ending {
                state = .idle
            }
            return
        }
        guard state == .previewing else {
            return
        }
        stopLoopAndRestore()
        state = .idle
    }

    private func startLoop(renderer: UntoldRenderer, frames: VisionProFrameSource) {
        // The headset rides the editor's camera, which the keys and the mouse
        // fly meanwhile; a game camera shown as a locked preview is left for it.
        ViewportCameras.show(.editor)
        let camera = findSceneCamera()
        let pose = VisionProPlacement.pose(of: camera) ?? (eye: .zero, forward: simd_float3(0, 0, -1))

        VisionProPreviewState.shared.isPreviewing = true
        renderer.enterStereo()
        let mirror = VisionProMirror(device: renderInfo.device)
        self.mirror = mirror
        // The viewport shows the headset's eye; the loop drives the engine.
        // The keys keep flying the camera, which the headset rides.
        // The loop flies the camera by the keys; the viewport's frames only
        // let go of a fly key whose key-up was lost, as the editor's own
        // frames do.
        mirror.onFrame = {
            InputSystem.shared.releaseFlyKeysTheKeyboardLetGo()
        }
        renderer.metalView.delegate = mirror
        // The pointer is a second head: its movement turns the view.
        let pointer = VisionProPointerCapture { delta in
            VisionProPreviewState.shared.steerCamera {
                InputSystem.shared.lookAroundSceneCamera(by: delta)
            }
        }
        self.pointer = pointer
        pointer.start()

        let loop = VisionProPreviewLoop(
            renderer: renderer,
            frames: frames,
            start: VisionProPreviewLoop.Start(camera: camera, cameraEye: pose.eye, cameraForward: pose.forward),
            mirror: mirror
        )
        self.loop = loop
        let done = DispatchSemaphore(value: 0)
        loopDone = done
        let thread = Thread { [weak self] in
            loop.run()
            done.signal()
            DispatchQueue.main.async {
                self?.loopDidEnd()
            }
        }
        thread.name = "Vision Pro Preview"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Stops the loop and puts the editor back once the loop has ended: the
    /// loop finishes the frame it is on, through the renderer's stereo targets
    /// and the mirror, so neither is taken from under it. Should the frame
    /// take longer than the wait, as a command buffer that never completes
    /// would, the editor is put back when the loop's thread ends; the session
    /// stays in `ending` meanwhile.
    private func stopLoopAndRestore() {
        loop?.stop()
        guard loopDone?.wait(timeout: .now() + loopStopTimeout) == .success else {
            Logger.log(message: "Vision Pro preview: the headset's loop did not end within \(loopStopTimeout) s; the editor is put back when it does.")
            restoreWaitsForTheLoop = true
            return
        }
        restoreEditor()
    }

    private func restoreEditor() {
        loop = nil
        loopDone = nil
        restoreWaitsForTheLoop = false

        if let renderer {
            renderer.metalView.delegate = renderer
            renderer.leaveStereo(viewport: renderer.metalView)
        }
        pointer?.stop()
        pointer = nil
        // The camera stays where the keys and the mouse flew it.
        mirror = nil
        VisionProPreviewState.shared.isPreviewing = false
    }

    /// Whether a key ends the preview: Escape, while one is asked for or shown.
    static func endsOnKey(_ keyCode: UInt16, state: State) -> Bool {
        keyCode == 53 && (state == .connecting || state == .previewing)
    }

    private func watchEscape() {
        guard escapeMonitor == nil else {
            return
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.endsOnKey(event.keyCode, state: state) else {
                return event
            }
            end()
            return nil
        }
    }

    private func unwatchEscape() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    /// The View menu's item for a state: its title, whether it can be chosen,
    /// and whether it is shown at all.
    static func menuItem(for state: State, isPlaying: Bool) -> (title: String, isEnabled: Bool, isHidden: Bool) {
        switch state {
        case .unavailable:
            return ("Preview on Apple Vision Pro", false, true)
        case .idle:
            return ("Preview on Apple Vision Pro", isPlaying == false, false)
        case .connecting, .previewing:
            return ("Stop the Preview on Apple Vision Pro", true, false)
        case .ending:
            return ("Stop the Preview on Apple Vision Pro", false, false)
        }
    }
}
