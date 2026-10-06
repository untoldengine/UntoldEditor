//
//  VisionProPreviewState.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// Whether the scene is previewed on a headset now. The session writes it
/// on the main thread; the input system and the render extension read it,
/// the latter from the headset's render thread, so it is kept under a lock.
final class VisionProPreviewState: @unchecked Sendable {
    static let shared = VisionProPreviewState()

    private let lock = NSLock()
    private var previewing = false

    var isPreviewing: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return previewing
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            previewing = newValue
        }
    }

    /// Held by the headset's loop while it draws the eyes, and by the main
    /// thread while it steers the camera: the engine keeps the camera's view
    /// matrix in the camera itself, and the per-eye render sets and reads it,
    /// so a move from the keys or the mouse in the middle of an eye would
    /// draw part of that eye from the camera's own view, stuck to the head.
    let cameraLock = NSLock()

    /// Runs a move of the camera from the keys or the mouse: while a headset
    /// previews, between two of its frames.
    func steerCamera<T>(_ body: () throws -> T) rethrows -> T {
        guard isPreviewing else {
            return try body()
        }
        cameraLock.lock()
        defer { cameraLock.unlock() }
        return try body()
    }
}
