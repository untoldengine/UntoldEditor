//
//  EditorViewportHostView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import MetalKit
import SwiftUI
import UntoldEngine

/// Hosts the engine's Metal view in the editor viewport, and is the canvas:
/// it receives the mouse, the wheel, the trackpad and the keys as any AppKit
/// view does and hands them to the input system. The Metal view only draws.
///
/// Normally the Metal view fills the host. While a resize hold is active
/// (`EditorViewportResizePolicy.beginResizeHold(of:)`) the Metal view is kept
/// at a larger, fixed size and centred, and the host clips it: the frozen frame
/// then extends past the visible area, so growing the window or hiding a panel
/// reveals more scene instead of a blank band.
final class EditorViewportHostView: NSView {
    let metalView: MTKView
    private var hoverTrackingArea: NSTrackingArea?
    private var resignKeyObserver: NSObjectProtocol?

    /// Size to keep the Metal view at, centred, while a hold is active. Nil
    /// lets it fill the host again. Applied immediately.
    var heldMetalViewSize: CGSize? {
        didSet {
            guard heldMetalViewSize != oldValue else { return }
            placeMetalView()
        }
    }

    init(metalView: MTKView) {
        self.metalView = metalView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(metalView)
        placeMetalView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeMetalView()
    }

    override func layout() {
        super.layout()
        placeMetalView()
    }

    private func placeMetalView() {
        let frame = Self.metalViewFrame(in: bounds, held: heldMetalViewSize)
        if metalView.frame != frame {
            metalView.frame = frame
        }
    }

    /// The Metal view fills `bounds`, or keeps `held` and sits centred on whole
    /// points so the frozen frame is not resampled.
    static func metalViewFrame(in bounds: CGRect, held: CGSize?) -> CGRect {
        guard let held else { return bounds }
        return CGRect(
            x: floor(bounds.midX - held.width / 2),
            y: floor(bounds.midY - held.height / 2),
            width: held.width,
            height: held.height
        )
    }

    deinit {
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
    }

    // MARK: - The keyboard

    override var acceptsFirstResponder: Bool {
        true
    }

    /// The events are the host's: the Metal view under the pointer only draws.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === metalView || hit.isDescendant(of: metalView) ? self : hit
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        guard let window else { return }

        InputSystem.shared.setupGestureRecognizers(view: self)
        // A window that stops being key sends no more key or button releases.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            InputSystem.shared.canvasLostTheKeyboard()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        takeKeyboardOnHover()
    }

    override func mouseMoved(with _: NSEvent) {
        takeKeyboardOnHover()
    }

    /// The pointer over the canvas brings the keyboard to it, so the keys fly
    /// the camera without a click first. A text field being typed in keeps the
    /// keyboard until the canvas is clicked.
    private func takeKeyboardOnHover() {
        guard let window,
              window.firstResponder !== self,
              Self.canTakeKeyboardOnHover(from: window.firstResponder),
              InputSystem.isEditorInputViewFrontmost(at: window.mouseLocationOutsideOfEventStream, in: self)
        else {
            return
        }
        window.makeFirstResponder(self)
    }

    /// Whether hovering may take the keyboard from `responder`: from anything
    /// but a text field that is being typed in.
    static func canTakeKeyboardOnHover(from responder: NSResponder?) -> Bool {
        (responder is NSTextView) == false
    }

    override func resignFirstResponder() -> Bool {
        InputSystem.shared.canvasLostTheKeyboard()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if InputSystem.shared.canvasKeyDown(event) == false {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        InputSystem.shared.canvasKeyUp(event)
    }

    override func flagsChanged(with event: NSEvent) {
        InputSystem.shared.canvasFlagsChanged(event)
        super.flagsChanged(with: event)
    }

    // MARK: - The pointer

    /// Where an event happened, in the Metal view, which picking measures in.
    private func location(of event: NSEvent) -> NSPoint {
        metalView.convert(event.locationInWindow, from: nil)
    }

    /// A press on the canvas brings the keyboard to it, from a text field too.
    private func takeKeyboard() {
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        takeKeyboard()
        InputSystem.shared.canvasLeftMouseDown(event, at: location(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        InputSystem.shared.canvasLeftMouseDragged(event, to: location(of: event), in: metalView)
    }

    override func mouseUp(with event: NSEvent) {
        InputSystem.shared.canvasLeftMouseUp(event, at: location(of: event), in: metalView)
    }

    override func rightMouseDown(with event: NSEvent) {
        takeKeyboard()
        InputSystem.shared.canvasRightMouseDown(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        InputSystem.shared.canvasRightMouseDragged(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        InputSystem.shared.canvasRightMouseUp(event)
    }

    override func scrollWheel(with event: NSEvent) {
        InputSystem.shared.canvasScrolled(event)
    }

    override func magnify(with event: NSEvent) {
        InputSystem.shared.canvasMagnified(event)
    }
}
