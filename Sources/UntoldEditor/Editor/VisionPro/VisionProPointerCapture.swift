//
//  VisionProPointerCapture.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import simd

/// The pointer as a second head while the headset shows the scene: its
/// movement turns the view, with no button held, on top of what the real
/// head does, since looking back is hard sitting down. Taken as a game takes
/// it: the cursor hidden and held where it is, so that the movement never
/// leaves the viewport, and every mouse, Magic Mouse or finger on a trackpad
/// does the same. Let go while the editor is not the active app, and when
/// the preview ends.
final class VisionProPointerCapture {
    /// The turn a movement of the pointer asks for, in the units of a look
    /// drag: to the right for a move to the right, up for a move up (the
    /// event's Y grows down the screen).
    static func turn(forPointerDelta delta: simd_float2) -> simd_float2 {
        guard delta.x.isFinite, delta.y.isFinite else {
            return .zero
        }
        return simd_float2(delta.x, -delta.y)
    }

    private(set) var isCapturing = false
    private var isHolding = false
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private let onTurn: (simd_float2) -> Void

    init(onTurn: @escaping (simd_float2) -> Void) {
        self.onTurn = onTurn
    }

    deinit {
        stop()
    }

    /// Takes the pointer: from now until `stop()`, its movement turns.
    func start() {
        guard isCapturing == false else {
            return
        }
        isCapturing = true
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            guard let self, isHolding else {
                return event
            }
            onTurn(Self.turn(forPointerDelta: simd_float2(Float(event.deltaX), Float(event.deltaY))))
            return event
        }) {
            monitors.append(monitor)
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hold()
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.release()
        })
        if NSApp.isActive {
            hold()
        }
    }

    /// Gives the pointer back.
    func stop() {
        guard isCapturing else {
            return
        }
        release()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        isCapturing = false
    }

    /// Hides the cursor and holds it where it is; the movement still arrives.
    private func hold() {
        guard isCapturing, isHolding == false else {
            return
        }
        isHolding = true
        NSApp.windows.forEach { $0.acceptsMouseMovedEvents = true }
        CGAssociateMouseAndMouseCursorPosition(0)
        NSCursor.hide()
    }

    private func release() {
        guard isHolding else {
            return
        }
        isHolding = false
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }
}
