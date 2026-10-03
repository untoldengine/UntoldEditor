//
//  EditorInputSystemAppKit.swift
//  Untold Engine
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//  Copyright © 2024 Untold Engine Studios. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Cocoa
    import simd
    import UntoldEngine

    private final class EditorInputTargetViewRef {
        weak var view: NSView?
        /// Where the left button went down on the canvas; nil while it is up.
        var leftDownLocation: NSPoint?
        /// True once the left button's press became a drag, which works on the
        /// selection's gizmo. A press released before that is a click.
        var isObjectDragActive = false
        /// True while the right button, pressed on the canvas, steers the camera.
        var isCameraDragActive = false
        /// True while the pointer is over a control the editor draws over the
        /// canvas, such as the navigation gizmo.
        var isPointerOverViewportControl = false
        /// What the right button's drag does to the camera. Resolved once when
        /// it begins so a modifier released mid-drag does not flip a pan into a
        /// look halfway through.
        var activeDragAction: CameraDragAction = .none
        /// Set when a left-button drag began as a ⇧-drag with a selection, which
        /// moves that entity from the mouse deltas and takes no gizmo handle.
        var isEntityDragReserved = false
        /// Where a left-button drag that took no gizmo handle began: it draws
        /// the rectangle that selects what is inside it. Nil while none is drawn.
        var marqueeStart: NSPoint?
        /// The rectangle as the drag last left it, in the canvas's points from
        /// its bottom left, the size of the canvas it is measured in, and the
        /// canvas's pixels to a point.
        var marqueeRect: CGRect = .zero
        var marqueeViewSize: CGSize = .zero
        var marqueeScale: CGFloat = 1
        /// Whether the keyboard itself holds a key down, asked of the system and
        /// not of the events. Tests replace it.
        var isKeyPhysicallyDown: (UInt16) -> Bool = { keyCode in
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        }

        /// True once the keyboard's own state has agreed with a key-down event,
        /// which shows it can be read here. Until then no key is let go on its word.
        var isPhysicalKeyStateTrusted = false
        /// Whether a key let go without its key-up event has been reported.
        var hasReportedLostKeyUp = false
        /// When the last scroll event navigated the camera. A gap longer than
        /// `InputSystem.scrollSessionGap` starts a new session, which re-anchors
        /// the pivot; inside a session the pivot stays put so an orbit in
        /// progress does not wander.
        var lastScrollNavigationTime: TimeInterval = 0
    }

    private let editorInputTargetViewRef = EditorInputTargetViewRef()

    public extension InputSystem {
        /// Tells the input system which view is the canvas. On macOS the viewport's
        /// view receives the mouse, the wheel, the trackpad and the keys itself, as
        /// any AppKit view does, and hands them over through the `canvas…` functions
        /// below, so no gesture recogniser is attached.
        func setupGestureRecognizers(view: NSView) {
            editorInputTargetViewRef.view = view
        }

        /// The one shortcut that is the window's and not the canvas's: ⌘Z and ⇧⌘Z
        /// undo and redo wherever the keyboard is, except in a text field.
        func setupEventMonitors() {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self?.isTextBeingEdited == false,
                      event.modifierFlags.contains(.command),
                      event.charactersIgnoringModifiers?.lowercased() == "z"
                else {
                    return event
                }
                if event.modifierFlags.contains(.shift) {
                    EditorUndoManager.shared.redo()
                } else {
                    EditorUndoManager.shared.undo()
                }
                return nil
            }
        }

        /// Whether the keys the canvas receives are for the scene: the pointer is
        /// over the canvas or over one of its own controls, or a button pressed
        /// on it is still held, wherever the drag went. An overlay such as the
        /// project gallery must not drive the camera behind it.
        internal var canvasOwnsKeys: Bool {
            editorInputTargetViewRef.isCameraDragActive
                || editorInputTargetViewRef.leftDownLocation != nil
                || editorInputTargetViewRef.isPointerOverViewportControl
                || isPointerOverEditorInputView()
        }

        /// The pointer went over, or left, a control the editor draws over the
        /// canvas. There the keys still fly the camera, as they do beside it.
        internal func pointerIsOverViewportControl(_ isOver: Bool) {
            editorInputTargetViewRef.isPointerOverViewportControl = isOver
        }

        /// The keys that fly the camera, by their flag in the key state and their
        /// macOS virtual key code: W, A, S, D, Q and E.
        internal static let flyKeys: [(flag: WritableKeyPath<KeyState, Bool>, keyCode: UInt16)] = [
            (\.wPressed, 13), (\.aPressed, 0), (\.sPressed, 1), (\.dPressed, 2), (\.qPressed, 12), (\.ePressed, 14),
        ]

        /// Reads whether the keyboard itself holds a key down. Tests replace it.
        internal var physicalKeyState: (UInt16) -> Bool {
            get { editorInputTargetViewRef.isKeyPhysicallyDown }
            set { editorInputTargetViewRef.isKeyPhysicallyDown = newValue }
        }

        /// Whether the keyboard's own state has been seen to agree with the events.
        internal var isPhysicalKeyStateTrusted: Bool {
            get { editorInputTargetViewRef.isPhysicalKeyStateTrusted }
            set { editorInputTargetViewRef.isPhysicalKeyStateTrusted = newValue }
        }

        /// A key-down event for a fly key: when the keyboard's own state agrees
        /// that the key is down, that state can be trusted from here on.
        internal func noteKeyDown(_ keyCode: UInt16) {
            guard editorInputTargetViewRef.isPhysicalKeyStateTrusted == false,
                  InputSystem.flyKeys.contains(where: { $0.keyCode == keyCode }),
                  editorInputTargetViewRef.isKeyPhysicallyDown(keyCode)
            else {
                return
            }
            editorInputTargetViewRef.isPhysicalKeyStateTrusted = true
        }

        /// Lets go of the fly keys the keyboard no longer holds. A key-up event
        /// can be lost: macOS sends none while ⌘ is down, nor to a window that
        /// stopped being key, and a lost one would fly the camera forever.
        internal func releaseFlyKeysTheKeyboardLetGo() {
            guard editorInputTargetViewRef.isPhysicalKeyStateTrusted else {
                return
            }
            var letGo = false
            for key in InputSystem.flyKeys where keyState[keyPath: key.flag] {
                if editorInputTargetViewRef.isKeyPhysicallyDown(key.keyCode) == false {
                    keyState[keyPath: key.flag] = false
                    letGo = true
                }
            }
            if letGo, editorInputTargetViewRef.hasReportedLostKeyUp == false {
                editorInputTargetViewRef.hasReportedLostKeyUp = true
                Logger.log(message: "A camera key was released without its key-up event; the editor let it go from the keyboard's own state.")
            }
        }

        /// True for W, A, S, D, Q or E pressed with ⌘ while the right button
        /// steers the camera, which the canvas takes: the menu must not have it
        /// for a shortcut. It flies the camera when the keyboard's own state can
        /// be read, since macOS sends no key up while ⌘ is down; else it is dropped.
        internal func takesCommandKeyDuringCameraDrag(_ event: NSEvent) -> Bool {
            guard keyState.rightMousePressed,
                  event.modifierFlags.contains(.command),
                  InputSystem.flyKeys.contains(where: { $0.keyCode == event.keyCode })
            else {
                return false
            }
            noteKeyDown(event.keyCode)
            if editorInputTargetViewRef.isPhysicalKeyStateTrusted {
                keyPressed(event.keyCode)
            }
            return true
        }

        /// The tool a key press picks: ⌥ with 1, 2, 3 or 4 while editing.
        internal func toolShortcut(for event: NSEvent) -> TransformTool? {
            guard ViewportCameras.isPlaying == false, event.modifierFlags.contains(.option) else {
                return nil
            }
            return TransformTool.tool(forKeyCode: event.keyCode)
        }

        /// True while a text field has the keyboard, which then is not the editor's.
        private var isTextBeingEdited: Bool {
            NSApp.keyWindow?.firstResponder is NSTextView
        }

        // MARK: - The canvas's events

        // The viewport's view receives the mouse, the wheel, the trackpad and the
        // keys as any AppKit view does and hands each event over here. The left
        // button works on the scene, the right one steers the camera, and the
        // keys fly it.

        /// How far the pointer may travel between press and release and still click.
        static let clickSlop: CGFloat = 3

        /// False while the viewport is a locked preview of a game camera: the
        /// pointer would not pick through what is on screen.
        private var canvasTakesThePointer: Bool {
            ViewportCameras.isLockedPreview == false
        }

        /// The camera the keys and the mouse steer now, or nil when they steer none.
        private var steeredCamera: EntityID? {
            ViewportCameras.steered
        }

        func canvasLeftMouseDown(_ event: NSEvent, at location: NSPoint) {
            syncModifiers(from: event)
            leftMouseDown(event)
            editorInputTargetViewRef.leftDownLocation = location
            editorInputTargetViewRef.isObjectDragActive = false
        }

        func canvasLeftMouseDragged(_ event: NSEvent, to location: NSPoint, in view: NSView) {
            leftMouseDragged(simd_float2(Float(event.deltaX), Float(event.deltaY)))
            guard canvasTakesThePointer, let start = editorInputTargetViewRef.leftDownLocation else {
                return
            }

            if editorInputTargetViewRef.isObjectDragActive == false {
                guard hypot(location.x - start.x, location.y - start.y) > InputSystem.clickSlop else {
                    return
                }
                editorInputTargetViewRef.isObjectDragActive = true
                beginObjectDrag(at: start, in: view)
            }
            continueObjectDrag(to: location, translation: NSPoint(x: location.x - start.x, y: location.y - start.y), in: view)
        }

        func canvasLeftMouseUp(_ event: NSEvent, at location: NSPoint, in view: NSView) {
            leftMouseUp(event)
            let wasPressedOnTheCanvas = editorInputTargetViewRef.leftDownLocation != nil
            let wasDragging = editorInputTargetViewRef.isObjectDragActive
            editorInputTargetViewRef.leftDownLocation = nil
            editorInputTargetViewRef.isObjectDragActive = false

            if wasDragging {
                endObjectDrag()
            } else if wasPressedOnTheCanvas, canvasTakesThePointer {
                selectEntity(at: location, in: view)
            }
        }

        func canvasRightMouseDown(_ event: NSEvent) {
            syncModifiers(from: event)
            keyState.rightMousePressed = true
            beginCameraDrag()
        }

        func canvasRightMouseDragged(_ event: NSEvent) {
            // The event's Y grows down the screen; the view's Y points up.
            moveCameraDrag(by: simd_float2(Float(event.deltaX), Float(-event.deltaY)))
        }

        func canvasRightMouseUp(_: NSEvent) {
            keyState.rightMousePressed = false
            endCameraDrag()
        }

        func canvasScrolled(_ event: NSEvent) {
            syncModifiers(from: event)
            handleMouseScroll(event)
        }

        func canvasMagnified(_ event: NSEvent) {
            handleMagnify(by: event.magnification, phase: event.phase)
        }

        /// A key pressed while the canvas has the keyboard. False when the key is
        /// not the canvas's to take, so the view passes it on.
        func canvasKeyDown(_ event: NSEvent) -> Bool {
            syncModifiers(from: event)

            // ⌘ with the right button held moves the camera. A fly key pressed
            // then is the canvas's, not the menu's, where ⌘Q would quit the
            // editor: the view takes it as a key equivalent before the menu
            // sees it, and here as well should it still arrive as a key-down.
            if takesCommandKeyDuringCameraDrag(event) {
                return true
            }
            // Every other ⌘ shortcut is the menus'.
            if event.modifierFlags.contains(.command) {
                return false
            }

            // ⌥1 to ⌥4 pick the tool. The letters stay with the camera, which they fly.
            if let tool = toolShortcut(for: event) {
                if event.isARepeat == false {
                    NotificationCenter.default.post(name: .editorSelectTool, object: nil, userInfo: ["tool": tool.rawValue])
                }
                return true
            }

            guard canvasOwnsKeys else {
                return false
            }
            keyPressed(event.keyCode)
            noteKeyDown(event.keyCode)
            return true
        }

        /// A key released while the canvas has the keyboard. Never gated by where
        /// the pointer is, so a key pressed over the canvas cannot stay down.
        func canvasKeyUp(_ event: NSEvent) {
            syncModifiers(from: event)
            keyReleased(event.keyCode)
        }

        func canvasFlagsChanged(_ event: NSEvent) {
            syncModifiers(from: event)
        }

        /// The canvas stopped receiving the keys: another view took the keyboard,
        /// or the window stopped being key. Every key and button it held is let
        /// go and its drags end, since their releases will go elsewhere.
        func canvasLostTheKeyboard() {
            for key in InputSystem.flyKeys {
                keyState[keyPath: key.flag] = false
            }
            keyState.spacePressed = false
            keyState.shiftPressed = false
            keyState.ctrlPressed = false
            keyState.commandPressed = false
            keyState.altPressed = false
            keyState.leftMousePressed = false
            keyState.rightMousePressed = false
            mouseActive = false

            // A rectangle left half drawn selects nothing.
            cancelMarquee()
            if editorInputTargetViewRef.isObjectDragActive {
                endObjectDrag()
            }
            editorInputTargetViewRef.leftDownLocation = nil
            editorInputTargetViewRef.isObjectDragActive = false
            endCameraDrag()
        }

        func handleMouseScroll(_ event: NSEvent) {
            let rawDelta = simd_float2(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY))
            guard rawDelta.x.isFinite, rawDelta.y.isFinite else {
                return
            }
            let precise = event.hasPreciseScrollingDeltas

            let now = ProcessInfo.processInfo.systemUptime
            if now - editorInputTargetViewRef.lastScrollNavigationTime > InputSystem.scrollSessionGap {
                reanchorSceneCameraTarget()
            }
            editorInputTargetViewRef.lastScrollNavigationTime = now

            // Orbit and zoom lock to the dominant axis, with X inverted and a
            // one-unit dead zone, as they always have.
            var deltaX = rawDelta.x
            var deltaY = rawDelta.y

            if abs(deltaX) < abs(deltaY) {
                deltaX = 0.0
            } else {
                deltaY = 0.0
                deltaX = -1.0 * deltaX
            }

            if abs(deltaX) <= 1.0 {
                deltaX = 0.0
            }

            if abs(deltaY) <= 1.0 {
                deltaY = 0.0
            }

            scrollDelta = 0.01 * simd_float2(deltaX, deltaY)

            switch EditorNavigationSettings.shared.scrollAction(
                shiftPressed: keyState.shiftPressed,
                commandPressed: keyState.commandPressed
            ) {
            case .orbit:
                // Scroll Y is document-style (positive moves content down), the
                // opposite of the drag's view Y, so flip it to orbit the same way.
                orbitSceneCamera(byScroll: simd_float2(deltaX, -deltaY), precise: precise)
            case .pan:
                // A pan follows both axes at once; no lock or dead zone.
                panSceneCamera(byScroll: rawDelta, precise: precise)
            case .zoom:
                if deltaY != 0.0 {
                    let zoomScale: Float = precise ? 0.025 : 0.15
                    zoomSceneCamera(by: deltaY * zoomScale)
                }
            }
        }

        /// Pan per line of a mouse wheel relative to a point of trackpad scroll;
        /// a wheel reports a few units per notch where a swipe reports points.
        static let scrollWheelPanMultiplier: Float = 10

        /// Pans from a scroll delta. Scroll deltas are document-style (positive Y
        /// means the content moves down the screen) while the view's Y points up,
        /// so Y is flipped before the shared pan moves the scene with the scroll.
        func panSceneCamera(byScroll delta: simd_float2, precise: Bool) {
            let viewDelta = simd_float2(delta.x, -delta.y) * (precise ? 1 : InputSystem.scrollWheelPanMultiplier)
            panSceneCamera(by: viewDelta)
        }

        /// Idle time between scroll events that starts a new navigation session.
        static let scrollSessionGap: TimeInterval = 0.35
        /// Nearest and farthest the pivot may sit ahead of the camera.
        static let minimumOrbitPivotDistance: Float = 0.25
        static let maximumOrbitPivotDistance: Float = 100
        /// Pivot distance when nothing within range lies ahead (sky, far ground).
        static let defaultOrbitPivotDistance: Float = 10

        /// Where the camera should orbit, zoom and pan around, always on the view
        /// ray so adopting it never turns the camera. The nearest of three depths
        /// wins, each only if it lies within range: the scene geometry under the
        /// view centre (`sceneHitDistance`), the ground plane, and the previous
        /// target's depth. Nearest, so zooming in close keeps a close pivot even
        /// when the view skims over the object to ground far behind it, while
        /// flying away from a stale target lets the ground or an object take
        /// over. With no candidate (sky, nothing ahead) a default depth is used.
        static func orbitPivot(
            eye: simd_float3,
            forward: simd_float3,
            currentTarget: simd_float3,
            sceneHitDistance: Float? = nil
        ) -> simd_float3 {
            let forwardLength = simd_length(forward)
            guard forwardLength > 0.0001, forwardLength.isFinite else {
                return currentTarget
            }
            let direction = forward / forwardLength

            var candidates: [Float] = []
            if let sceneHitDistance {
                candidates.append(sceneHitDistance)
            }
            if let hit = pickGroundPosition(rayOrigin: eye, rayDirection: direction) {
                candidates.append(hit.distance)
            }
            candidates.append(simd_dot(currentTarget - eye, direction))

            let depth = candidates
                .filter { $0.isFinite && $0 >= minimumOrbitPivotDistance && $0 <= maximumOrbitPivotDistance }
                .min() ?? defaultOrbitPivotDistance
            return eye + direction * depth
        }

        /// Re-anchors the steered camera's target on `orbitPivot` before a navigation
        /// session. The target is only ever set by a look-at, so flying with WASD,
        /// loading a scene or zooming leaves it where it was, sometimes far away or
        /// behind the camera, and every orbit, zoom and pan step is measured from it.
        func reanchorSceneCameraTarget() {
            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                return
            }
            let eye = cameraComponent.localPosition
            // The camera looks down its negative Z axis, as the spawn code assumes.
            let forward = -forwardDirectionVector(from: cameraComponent.rotation)
            let pivot = InputSystem.orbitPivot(
                eye: eye,
                forward: forward,
                currentTarget: getCameraTarget(entityId: camera),
                sceneHitDistance: sceneDepthUnderViewCentre(eye: eye, forward: forward)
            )
            let currentUp = getCameraUp(entityId: camera)
            let up = simd_length(currentUp) > 0.001 ? currentUp : cameraUpDefault
            cameraLookAt(entityId: camera, eye: eye, target: pivot, up: up)
        }

        /// Distance along the view ray to the first thing in the scene: meshes
        /// through the scene pick, and Gaussian splats through their bounding
        /// boxes, which the pick's octree does not know about.
        func sceneDepthUnderViewCentre(eye: simd_float3, forward: simd_float3) -> Float? {
            var candidates: [Float] = []
            if let hit = pickEntity(
                rayOrigin: eye,
                rayDirection: forward,
                options: ScenePickOptions(isGizmoActive: gizmoActive, backend: .octreeGPUPreferred)
            ) {
                candidates.append(hit.distance)
            }
            if let gaussian = InputSystem.gaussianBoundsHit(rayOrigin: eye, rayDirection: forward) {
                candidates.append(gaussian.distance)
            }
            return candidates.min()
        }

        /// Distance along the ray to the nearest Gaussian splat entity's world-space
        /// bounding box, or to its centre's depth when the ray starts inside the box
        /// (zoomed right into a capture). `nil` when the ray meets none.
        static func gaussianBoundsDepth(rayOrigin: simd_float3, rayDirection: simd_float3) -> Float? {
            gaussianBoundsHit(rayOrigin: rayOrigin, rayDirection: rayDirection)?.distance
        }

        /// The nearest meshless Gaussian entity intersected by the ray. Gaussian assets keep
        /// their rendered extent in `LocalTransformComponent.boundingBox`, so they can be
        /// selected without manufacturing a proxy mesh solely for picking.
        static func gaussianBoundsHit(
            rayOrigin: simd_float3,
            rayDirection: simd_float3
        ) -> (entityId: EntityID, distance: Float)? {
            let length = simd_length(rayDirection)
            guard length > 0.0001, length.isFinite else { return nil }
            let direction = rayDirection / length

            var nearest: (entityId: EntityID, distance: Float)?
            let gaussianId = getComponentId(for: GaussianComponent.self)
            for entityId in queryEntitiesWithComponentIds([gaussianId], in: scene) {
                // A captured twin with a real mesh is already handled more precisely by
                // ScenePickingSystem. Only splat-only entities need the bounds fallback.
                if let render = scene.get(component: RenderComponent.self, for: entityId),
                   render.mesh.isEmpty == false
                {
                    continue
                }
                guard let local = scene.get(component: LocalTransformComponent.self, for: entityId),
                      let world = scene.get(component: WorldTransformComponent.self, for: entityId)
                else { continue }

                var boxMin = simd_float3(repeating: .greatestFiniteMagnitude)
                var boxMax = simd_float3(repeating: -.greatestFiniteMagnitude)
                for corner in 0 ..< 8 {
                    let point = simd_float4(
                        corner & 1 == 0 ? local.boundingBox.min.x : local.boundingBox.max.x,
                        corner & 2 == 0 ? local.boundingBox.min.y : local.boundingBox.max.y,
                        corner & 4 == 0 ? local.boundingBox.min.z : local.boundingBox.max.z,
                        1
                    )
                    let moved = simd_mul(world.space, point)
                    boxMin = simd_min(boxMin, simd_float3(moved.x, moved.y, moved.z))
                    boxMax = simd_max(boxMax, simd_float3(moved.x, moved.y, moved.z))
                }

                var entry: Float = 0
                guard rayIntersectsAABB(rayOrigin: rayOrigin, rayDir: direction, boxMin: boxMin, boxMax: boxMax, tmin: &entry) else {
                    continue
                }
                let depth = entry >= 0 ? entry : simd_dot((boxMin + boxMax) / 2 - rayOrigin, direction)
                guard depth > 0, depth.isFinite else { continue }
                if depth < (nearest?.distance ?? .greatestFiniteMagnitude) {
                    nearest = (entityId, depth)
                }
            }
            return nearest
        }

        /// Orbit per point of trackpad scroll, matching the drag orbit's feel.
        static let scrollOrbitSpeedPrecise: Float = 0.005
        /// Orbit per line of a mouse wheel, which reports a few units per notch.
        static let scrollOrbitSpeedWheel: Float = 0.05

        /// Orbits the scene camera around its target from a scroll delta that the
        /// caller has already locked to its dominant axis, with X negated the way
        /// the drag orbit does. Each event orbits around the current target, as
        /// a drag does when it begins, so pans and zooms in between are respected.
        func orbitSceneCamera(byScroll delta: simd_float2, precise: Bool) {
            guard delta.x.isFinite, delta.y.isFinite, delta.x != 0 || delta.y != 0 else {
                return
            }
            let speed = (precise ? InputSystem.scrollOrbitSpeedPrecise : InputSystem.scrollOrbitSpeedWheel) * EditorViewportSettings.shared.speedMultiplier
            orbitSteeredCamera(by: delta * speed)
        }

        /// Turns the steered camera around its target by `angles` radians: the
        /// first about the world's up axis, the second tilting it. The engine's
        /// `orbitAround` is not used: it has no right axis where the camera
        /// stands straight over or under its target, which the Top and Bottom
        /// presets put it, and writes NaN into the camera from there.
        private func orbitSteeredCamera(by angles: simd_float2) {
            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }
            let pivot = getCameraTarget(entityId: camera)
            guard let step = InputSystem.orbitStep(
                eye: cameraComponent.localPosition,
                pivot: pivot,
                cameraUp: upDirectionVector(from: cameraComponent.rotation),
                angles: angles
            ) else {
                return
            }
            cameraLookAt(entityId: camera, eye: step.eye, target: pivot, up: step.up)
        }

        /// How close to straight over or under the pivot a view counts as
        /// vertical, as the sine of its elevation: there the world's up axis
        /// gives no right axis and the camera's own is used instead.
        static let verticalViewSine: Float = 0.9999

        /// Where an orbit step takes the eye around `pivot`, and which up vector
        /// to look at the pivot with from there. `angles.x` turns the eye about
        /// the world's up axis and `angles.y` tilts it about the right axis, in
        /// radians, the way the engine's `orbitAround` does; the tilt stops at
        /// straight above or below the pivot instead of passing over it. The
        /// right axis is the world's up crossed with the view, or where the
        /// view is vertical and that cross is nothing, the camera's own, which
        /// is horizontal too. The up vector is the world's, or where the view is
        /// vertical the camera's own, `cameraUp`, turned the same way; the
        /// world's would be along the view there and give no frame.
        static func orbitStep(
            eye: simd_float3,
            pivot: simd_float3,
            cameraUp: simd_float3,
            angles: simd_float2
        ) -> (eye: simd_float3, up: simd_float3)? {
            let offset = eye - pivot
            let distance = simd_length(offset)
            guard distance > 0.0001, distance.isFinite, angles.x.isFinite, angles.y.isFinite,
                  simd_length_squared(cameraUp) > 0.0001
            else {
                return nil
            }
            let worldUp = simd_float3(0, 1, 0)

            let yaw = simd_quatf(angle: angles.x, axis: worldUp)
            var direction = simd_normalize(simd_act(yaw, offset / distance))
            var up = simd_normalize(simd_act(yaw, cameraUp))

            var right = simd_cross(worldUp, direction)
            if simd_length_squared(right) < 1e-6 {
                right = simd_cross(up, direction)
            }
            guard simd_length_squared(right) > 1e-12 else {
                return nil
            }
            right = simd_normalize(right)

            // The tilt moves the elevation by its angle, up or down according
            // to which way the right axis points; it may reach a pole and not
            // pass it. At a pole every tilt leads away from it.
            let elevation = asin(Swift.min(Swift.max(direction.y, -1), 1))
            let rise = simd_cross(right, direction).y
            var tilt = angles.y
            if abs(rise) > 1e-6 {
                let sign: Float = rise > 0 ? 1 : -1
                let reached = Swift.min(Swift.max(elevation + sign * tilt, -.pi / 2), .pi / 2)
                tilt = (reached - elevation) * sign
            }
            let pitch = simd_quatf(angle: tilt, axis: right)
            direction = simd_normalize(simd_act(pitch, direction))
            up = simd_normalize(simd_act(pitch, up))

            let lookUp = abs(direction.y) < InputSystem.verticalViewSine ? worldUp : up
            return (pivot + direction * distance, lookUp)
        }

        /// Whether the pointer currently sits over the visible canvas of the key
        /// window. Used to gate key events, which carry no location of their own.
        private func isPointerOverEditorInputView() -> Bool {
            guard let view = editorInputTargetViewRef.view,
                  let window = view.window,
                  NSApp.keyWindow === window
            else {
                return false
            }

            let locationInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return InputSystem.isEditorInputViewFrontmost(at: locationInWindow, in: view)
        }

        /// True only when the view AppKit would deliver a mouse event to at
        /// `locationInWindow` is the canvas (or one of its subviews).
        ///
        /// A bounds check is not enough: SwiftUI overlays hosted in front of the
        /// canvas (project gallery, side panels, toolbars) occupy the same
        /// region, and their scrolling and clicks must not reach the camera.
        /// Hit testing resolves the frontmost view, so those overlays win.
        static func isEditorInputViewFrontmost(at locationInWindow: NSPoint, in view: NSView) -> Bool {
            guard view.isHiddenOrHasHiddenAncestor == false,
                  let window = view.window,
                  let contentView = window.contentView
            else {
                return false
            }

            // hitTest(_:) expects the point in the receiver's superview coordinates.
            let point = contentView.superview?.convert(locationInWindow, from: nil) ?? locationInWindow
            guard let hitView = contentView.hitTest(point) else {
                return false
            }

            return hitView === view || hitView.isDescendant(of: view)
        }

        /// A pinch on the trackpad zooms. `magnification` is the change since the
        /// last event of the pinch.
        func handleMagnify(by magnification: CGFloat, phase: NSEvent.Phase) {
            if phase.contains(.began) {
                previousScale = 1.0
                currentPinchGestureState = .began
            }

            if magnification != 0 {
                pinchDelta = 3.0 * simd_float3(0.0, 0.0, Float(magnification))
                zoomSceneCamera(by: Float(magnification) * 8.0)
                previousScale += magnification
                currentPinchGestureState = .changed
            }

            if phase.contains(.ended) || phase.contains(.cancelled) {
                previousScale = 1.0
                pinchDelta = .init(0, 0, 0)
                currentPinchGestureState = .ended
            }
        }

        private func zoomSceneCamera(by delta: Float) {
            guard delta.isFinite, abs(delta) > 0.0001 else {
                return
            }

            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let target = getCameraTarget(entityId: camera)
            let eye = cameraComponent.localPosition
            let targetVector = target - eye
            let distance = simd_length(targetVector)

            guard distance > 0.001 else {
                moveCameraAlongAxis(entityId: camera, uDelta: simd_float3(0, 0, delta))
                return
            }

            let minDistance: Float = 0.25
            let maxForwardStep = max(0.0, distance - minDistance)
            let maxBackwardStep = max(5.0, distance * 0.5)
            let clampedDelta: Float = Swift.min(Swift.max(delta, -maxBackwardStep), maxForwardStep)
            guard abs(clampedDelta) > 0.0001 else {
                return
            }

            let direction = simd_normalize(targetVector)
            let newEye = eye + direction * clampedDelta
            let currentUp = getCameraUp(entityId: camera)
            let up = simd_length(currentUp) > 0.001 ? currentUp : cameraUpDefault

            cameraLookAt(entityId: camera, eye: newEye, target: target, up: up)
        }

        /// Slides the camera and its orbit target along the view plane so the
        /// scene follows the cursor (Blender ⇧-drag). The step scales with the
        /// distance to the target so panning feels the same at any zoom level.
        private func panSceneCamera(by delta: simd_float2) {
            guard delta.x.isFinite, delta.y.isFinite, simd_length(delta) > 0.0001 else {
                return
            }

            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let target = getCameraTarget(entityId: camera)
            let eye = cameraComponent.localPosition
            let rawDistance = simd_length(target - eye)
            guard rawDistance > 0.001 else {
                return
            }
            let distance = Swift.max(rawDistance, 0.25)
            let currentUp = getCameraUp(entityId: camera)
            let up = simd_length(currentUp) > 0.001 ? simd_normalize(currentUp) : cameraUpDefault

            let right = simd_normalize(simd_cross(up, (eye - target) / rawDistance))
            guard right.x.isFinite, right.y.isFinite, right.z.isFinite else {
                return
            }

            // Move the camera opposite to the cursor so the scene tracks it.
            // View y already points up in the (non-flipped) canvas.
            let offset = (-right * delta.x - up * delta.y) * distance * InputSystem.dragPanSpeed * EditorViewportSettings.shared.speedMultiplier
            cameraLookAt(entityId: camera, eye: eye + offset, target: target + offset, up: up)
        }

        /// Dollies toward / away from the orbit target from a drag (Blender
        /// ⌘-drag). Dragging up or right zooms in; the step scales with the
        /// distance to the target.
        private func dragZoomSceneCamera(by delta: simd_float2) {
            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }
            let distance = Swift.max(simd_length(getCameraTarget(entityId: camera) - cameraComponent.localPosition), 0.5)
            let amount = InputSystem.dragZoomAmount(delta: delta, distance: distance)
            zoomSceneCamera(by: amount)
        }

        /// Pan distance per point of drag, as a fraction of the camera-to-target distance.
        static let dragPanSpeed: Float = 0.002

        /// World-space dolly step for a drag delta (in points) at a given
        /// camera-to-target distance. Up / right zooms in.
        static func dragZoomAmount(delta: simd_float2, distance: Float) -> Float {
            guard delta.x.isFinite, delta.y.isFinite else {
                return 0
            }
            return (delta.y + delta.x) * 0.005 * distance
        }

        /// A left click: selects what is under the pointer, or clears the
        /// selection when nothing is there, so the Inspector empties. With ⇧
        /// held what is under the pointer joins the selection, or leaves it. A
        /// click on a gizmo handle is left to the drag that moves it. While the
        /// game plays a click is the game's and selects nothing.
        func selectEntity(at currentLocation: NSPoint, in view: NSView) {
            guard editorController?.isEnabled == true, ViewportCameras.isPlaying == false else {
                return
            }

            guard scene.get(component: CameraComponent.self, for: findSceneCamera()) != nil else {
                handleError(.noActiveCamera)
                return
            }

            if keyState.shiftPressed {
                toggleEntity(at: currentLocation, in: view)
                return
            }

            let rayContext = raycastContext(currentLocation: currentLocation, view: view)

            let (entityId, hit) = entityForClick(at: currentLocation, in: view)

            if hitGizmoToolAxis(entityId: entityId) {
                return
            }

            gizmoActive = false
            removeGizmo()
            editorController?.activeMode = .none
            editorController?.activeAxis = .none
            activeHitGizmoEntity = .invalid

            // A handle of an entity written in code (a spline's control point) is drawn over
            // everything, so it takes the click before whatever mesh lies under it.
            if selectHandleUnderCursor(currentLocation: currentLocation, view: view) {
                return
            }
            EditorRepresentationHandles.select(nil)

            if hit {
                if hasComponent(entityId: entityId, componentType: GizmoComponent.self) {
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didSelectEntity(entityId)
                } else if keyState.commandPressed {
                    // Cmd+click selects the top-level asset root, for moving/rotating
                    // the whole imported group at once.
                    let transformEntityId = editableAssetRootEntity(for: entityId)
                    activeEntity = selectableTransformEntity(for: transformEntityId)
                    selectionDelegate?.didSelectEntity(entityId)
                } else if let rayContext,
                          let meshIndex = pickMeshIndexForEntity(
                              entityId: entityId,
                              rayOrigin: rayContext.rayOrigin,
                              rayDirection: rayContext.rayDirection
                          )
                {
                    // Default: click selects the specific child mesh under the cursor.
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didInspectMesh(entityId, meshIndex: meshIndex)
                } else {
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didSelectEntity(entityId)
                }
                selectionDelegate?.resetActiveAxis()

            } else {
                clearViewportSelection()
            }
        }

        /// Selects the handle under the cursor, if there is one: its entity becomes the
        /// selection and the move gizmo goes on the point. Returns `false` when no handle is there.
        func selectHandleUnderCursor(currentLocation: NSPoint, view: NSView) -> Bool {
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: findSceneCamera()),
                  let handle = EditorRepresentationHandles.pick(
                      atViewLocation: currentLocation,
                      viewSize: view.bounds.size,
                      viewSpace: cameraComponent.viewSpace,
                      perspectiveSpace: renderInfo.perspectiveSpace
                  )
            else {
                return false
            }

            gizmoActive = false
            removeGizmo()
            editorController?.activeMode = .none
            editorController?.activeAxis = .none
            activeHitGizmoEntity = .invalid
            EditorRepresentationHandles.select(handle)
            activeEntity = handle.entityId
            selectionDelegate?.didSelectEntity(handle.entityId)
            selectionDelegate?.resetActiveAxis()
            return true
        }

        /// Drops the engine-side selection and tells the editor so the SwiftUI
        /// selection (Inspector, hierarchy highlight) follows.
        func clearViewportSelection() {
            activeEntity = .invalid
            EditorRepresentationHandles.select(nil)
            removeGizmo()
            selectionDelegate?.didClearSelection()
        }

        /// What a click picks: the handle of the gizmo under the pointer, and
        /// with none there the entity of the scene. While a gizmo shows the
        /// engine picks nothing but the gizmo, so a click on another entity
        /// found nothing and cleared the selection; a second click selected it.
        func entityForClick(at location: NSPoint, in view: NSView) -> (entityId: EntityID, hit: Bool) {
            let picked = getRaycastedEntity(currentLocation: location, view: view)
            guard picked.hit == false, gizmoActive, keyState.shiftPressed == false else {
                return picked
            }
            return sceneEntity(at: location, in: view)
        }

        /// The entity of the scene under the pointer, whether a gizmo shows or not.
        func sceneEntity(at location: NSPoint, in view: NSView) -> (entityId: EntityID, hit: Bool) {
            guard let rayContext = raycastContext(currentLocation: location, view: view) else {
                return (.invalid, false)
            }
            let sceneHit = pickEntity(
                rayOrigin: rayContext.rayOrigin,
                rayDirection: rayContext.rayDirection,
                options: ScenePickOptions(isGizmoActive: false, backend: .octreeGPUPreferred)
            )
            let gaussianHit = InputSystem.gaussianBoundsHit(
                rayOrigin: rayContext.rayOrigin,
                rayDirection: rayContext.rayDirection
            )
            if let gaussianHit, gaussianHit.distance < (sceneHit?.distance ?? .greatestFiniteMagnitude) {
                return (gaussianHit.entityId, true)
            }
            if let sceneHit {
                return (sceneHit.entityId, true)
            }
            return (.invalid, false)
        }

        /// A ⇧ click: the entity under the pointer joins the selection, or
        /// leaves it when it was selected; with ⌘ held too, the asset it
        /// belongs to. On a gizmo handle and on empty space nothing changes.
        func toggleEntity(at location: NSPoint, in view: NSView) {
            let (entityId, hit) = getRaycastedEntity(currentLocation: location, view: view)
            guard hit, entityId != .invalid,
                  hasComponent(entityId: entityId, componentType: GizmoComponent.self) == false
            else {
                return
            }
            let toggled = keyState.commandPressed ? editableAssetRootEntity(for: entityId) : entityId
            guard canEditSceneTransform(entityId: sceneTransformEntity(for: toggled)) else {
                return
            }
            EditorRepresentationHandles.select(nil)
            selectionDelegate?.didToggleEntity(toggled)
            selectionDelegate?.resetActiveAxis()
        }

        // MARK: - The scene on the left button

        /// True while the editor is there, enabled and editing; it only gates
        /// what is the editor's. From Play to Stop the pointer is the game's:
        /// it takes no gizmo handle and moves no entity.
        private var isEditorEnabled: Bool {
            guard ViewportCameras.isPlaying == false else {
                return false
            }
            return editorController?.isEnabled ?? (editorController != nil)
        }

        /// A drag with the left button began at `currentLocation`. It works on the
        /// selection: it takes the gizmo handle under the pointer, to move the
        /// entity along it. The camera is the right button's, so a drag that
        /// starts anywhere else moves nothing.
        func beginObjectDrag(at currentLocation: NSPoint, in view: NSView) {
            // The gizmo is picked and dragged through the scene camera
            guard scene.get(component: CameraComponent.self, for: findSceneCamera()) != nil else {
                handleError(.noActiveCamera)
                return
            }
            let isEditorEnabled = isEditorEnabled

            // Decided once, when the drag starts: ⇧-drag with a selected entity
            // moves that entity from the mouse deltas and takes no handle.
            editorInputTargetViewRef.isEntityDragReserved = keyState.shiftPressed && isEditorEnabled && activeEntity != .invalid
            if editorInputTargetViewRef.isEntityDragReserved {
                return
            }

            // Store initial state
            initialPanLocation = .zero
            currentPanGestureState = .began

            // Editor-only: hit-test gizmo if editor/gizmo mode is active
            activeHitGizmoEntity = .invalid
            if gizmoActive, isEditorEnabled {
                let (hitEntityId, hit) = getRaycastedEntity(currentLocation: currentLocation, view: view)
                if hit, hitGizmoToolAxis(entityId: hitEntityId) {
                    activeHitGizmoEntity = hitEntityId
                    processGizmoAction(entityId: activeHitGizmoEntity)
                    if let rayContext = raycastContext(currentLocation: currentLocation, view: view) {
                        beginGizmoDrag(
                            ray: GizmoDragRay(
                                origin: rayContext.rayOrigin,
                                direction: rayContext.rayDirection
                            )
                        )
                    }
                    if activeEntity != .invalid {
                        EditorUndoManager.shared.beginTransformEdit(entityIds: gizmoTransformTargets())
                    }
                    EditorRepresentationHandles.dragDidBegin()
                } else {
                    activeHitGizmoEntity = .invalid
                    editorController?.activeMode = .none
                    editorController?.activeAxis = .none
                }
            }

            // A drag that took no handle draws the rectangle that selects
            // what is inside it.
            if isEditorEnabled, activeHitGizmoEntity == .invalid, canvasTakesThePointer {
                beginMarquee(at: currentLocation, in: view)
            }
        }

        /// The drag moved to `currentLocation`; `currentPanLocation` is how far it
        /// is from where it began.
        func continueObjectDrag(to currentLocation: NSPoint, translation currentPanLocation: NSPoint, in view: NSView) {
            guard editorInputTargetViewRef.isEntityDragReserved == false else {
                return
            }
            guard scene.get(component: CameraComponent.self, for: findSceneCamera()) != nil else {
                handleError(.noActiveCamera)
                return
            }
            if editorInputTargetViewRef.marqueeStart != nil {
                // While the rectangle is drawn the drag is the rectangle's alone
                continueMarquee(to: currentLocation, in: view)
                return
            }
            let isEditorEnabled = isEditorEnabled

            // Editor-only: process gizmo if we hit one
            if isEditorEnabled {
                if activeHitGizmoEntity != .invalid,
                   let rayContext = raycastContext(currentLocation: currentLocation, view: view)
                {
                    queueGizmoDragUpdate(
                        ray: GizmoDragRay(
                            origin: rayContext.rayOrigin,
                            direction: rayContext.rayDirection
                        )
                    )
                }
                processGizmoAction(entityId: activeHitGizmoEntity)
                if activeHitGizmoEntity != .invalid {
                    // While dragging a gizmo, the drag is the gizmo's alone
                    return
                }
            }

            // The step since the last one, locked to its dominant axis with
            // X inverted, as the input state has always reported a drag to
            // whatever reads it (a game in play mode).
            var deltaX = currentPanLocation.x - (initialPanLocation?.x ?? currentPanLocation.x)
            var deltaY = currentPanLocation.y - (initialPanLocation?.y ?? currentPanLocation.y)

            if abs(deltaX) < abs(deltaY) {
                deltaX = 0.0
            } else {
                deltaY = 0.0
                deltaX = -deltaX
            }

            // Dead zone
            if abs(deltaX) <= 1.0 {
                deltaX = 0.0
            }
            if abs(deltaY) <= 1.0 {
                deltaY = 0.0
            }

            panDelta = simd_float2(Float(deltaX), Float(deltaY))
            currentPanGestureState = .changed
            initialPanLocation = currentPanLocation
        }

        /// The left button was released at the end of a drag.
        func endObjectDrag() {
            guard editorInputTargetViewRef.isEntityDragReserved == false else {
                editorInputTargetViewRef.isEntityDragReserved = false
                return
            }
            let isEditorEnabled = isEditorEnabled
            endMarquee()

            if isEditorEnabled,
               activeHitGizmoEntity != .invalid,
               activeEntity != .invalid
            {
                EditorUndoManager.shared.commitTransformEdit(entityIds: gizmoTransformTargets())
                EditorRepresentationHandles.dragDidEnd()
            }

            // Reset
            panDelta = simd_float2(0, 0)
            initialPanLocation = nil
            currentPanGestureState = .ended
            endGizmoDrag()
        }

        // MARK: - The rectangle on the left button

        /// True while a drag of the left button draws the rectangle.
        internal var isMarqueeActive: Bool {
            editorInputTargetViewRef.marqueeStart != nil
        }

        /// A drag began where no gizmo handle is: it draws a rectangle.
        func beginMarquee(at location: NSPoint, in view: NSView) {
            editorInputTargetViewRef.marqueeStart = location
            editorInputTargetViewRef.marqueeRect = CGRect(origin: location, size: .zero)
            editorInputTargetViewRef.marqueeViewSize = view.bounds.size
            editorInputTargetViewRef.marqueeScale = view.window?.backingScaleFactor ?? 1
        }

        /// The drag went on to `location`: the rectangle follows it, and the
        /// viewport draws it.
        func continueMarquee(to location: NSPoint, in view: NSView) {
            guard let start = editorInputTargetViewRef.marqueeStart else {
                return
            }
            let rect = MarqueeGeometry.rect(from: start, to: location)
            editorInputTargetViewRef.marqueeRect = rect
            editorInputTargetViewRef.marqueeViewSize = view.bounds.size
            ViewportMarqueeStore.shared.show(MarqueeGeometry.flipped(rect, inHeight: view.bounds.height))
        }

        /// The button was released: what stands inside the rectangle is the
        /// selection, with ⌘ held the assets it belongs to, and nothing when
        /// nothing is inside. What reaches out of the rectangle, as the floor
        /// under it does, is left out, and so is what is hidden behind
        /// something else.
        func endMarquee() {
            guard editorInputTargetViewRef.marqueeStart != nil else {
                return
            }
            let rect = editorInputTargetViewRef.marqueeRect
            let size = editorInputTargetViewRef.marqueeViewSize
            let scale = editorInputTargetViewRef.marqueeScale
            cancelMarquee()

            guard editorController?.isEnabled == true, ViewportCameras.isPlaying == false,
                  let cameraComponent = scene.get(component: CameraComponent.self, for: findSceneCamera())
            else {
                return
            }

            let inside = MarqueeSelection.entities(
                inside: rect,
                view: MarqueeGeometry.View(
                    viewSpace: cameraComponent.viewSpace,
                    perspectiveSpace: renderInfo.perspectiveSpace,
                    size: size
                ),
                selectionManager: editorController?.selectionManager,
                seen: { rect, view, drawn in
                    SelectionVisibilityPass.entitiesSeen(in: rect, view: view, scale: scale, drawn: drawn)
                }
            )
            let chosen = keyState.commandPressed ? MarqueeSelection.assetRoots(of: inside) : inside

            gizmoActive = false
            removeGizmo()
            editorController?.activeMode = .none
            editorController?.activeAxis = .none
            activeHitGizmoEntity = .invalid
            EditorRepresentationHandles.select(nil)

            guard chosen.isEmpty == false else {
                clearViewportSelection()
                return
            }
            selectionDelegate?.didSelectEntities(chosen)
            selectionDelegate?.resetActiveAxis()
        }

        /// Takes the rectangle away without selecting anything.
        func cancelMarquee() {
            editorInputTargetViewRef.marqueeStart = nil
            ViewportMarqueeStore.shared.hide()
        }

        // MARK: - The camera on the right button

        /// Radians the view turns per point of a look drag.
        static let lookSpeed: Float = 0.005
        /// How close to straight up or down the view may tilt, so it never flips over.
        static let lookPitchLimit: Float = .pi / 2 - 0.02
        /// Radians the camera orbits per point of an orbit drag.
        static let dragOrbitSpeed: Float = 0.005

        /// The right button went down on the canvas and steers the camera until
        /// it is released: the editor's while editing, and while playing the one
        /// the viewport shows. With nothing held the drag looks around where
        /// the camera stands, as the mouse does in a game; ⇧ pans, ⌘ moves the
        /// camera forward and back, ⌥ orbits the point ahead. The keys keep
        /// flying the camera meanwhile. A navigation control over the viewport
        /// begins the same drag and says itself what it does, as `chosen`.
        func beginCameraDrag(as chosen: CameraDragAction? = nil) {
            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let action = chosen ?? EditorNavigationSettings.dragAction(
                shiftPressed: keyState.shiftPressed,
                commandPressed: keyState.commandPressed,
                optionPressed: keyState.altPressed
            )
            editorInputTargetViewRef.activeDragAction = action
            editorInputTargetViewRef.isCameraDragActive = true

            // Panning, moving and orbiting are measured from the point ahead;
            // looking around only needs where the camera stands.
            if action != .look {
                reanchorSceneCameraTarget()
                let orbitDistance = simd_length(cameraComponent.localPosition - getCameraTarget(entityId: camera))
                setOrbitOffset(
                    entityId: camera,
                    uTargetOffset: orbitDistance > 0.001 ? orbitDistance : length(cameraComponent.localPosition)
                )
            }
            // Only an orbit holds the fly keys back.
            cameraControlMode = action == .orbit ? .orbiting : .moving
        }

        /// The pointer moved by `delta` points, Y up, with the right button held.
        func moveCameraDrag(by delta: simd_float2) {
            guard editorInputTargetViewRef.isCameraDragActive else {
                return
            }
            switch editorInputTargetViewRef.activeDragAction {
            case .look:
                lookAroundSceneCamera(by: delta)
            case .pan:
                panSceneCamera(by: delta)
            case .zoom:
                dragZoomSceneCamera(by: delta)
            case .orbit:
                orbitSceneCamera(byDrag: delta)
            case .none:
                break
            }
        }

        /// The right button was released.
        func endCameraDrag() {
            guard editorInputTargetViewRef.isCameraDragActive else {
                return
            }
            editorInputTargetViewRef.isCameraDragActive = false
            editorInputTargetViewRef.activeDragAction = .none
            cameraControlMode = .idle
        }

        /// The view direction after a look drag. `delta.x` turns it about the
        /// world's up axis, to the right for a drag to the right; `delta.y`
        /// tilts it, up for a drag up, stopping short of straight up and down.
        /// `up` gives the heading when `forward` is vertical and has none.
        static func lookDirection(from forward: simd_float3, up: simd_float3, delta: simd_float2) -> simd_float3 {
            let forwardLength = simd_length(forward)
            guard forwardLength > 0.0001, forwardLength.isFinite, delta.x.isFinite, delta.y.isFinite else {
                return forward
            }
            let direction = forward / forwardLength

            // Looking straight down, the top of the view points where the camera
            // is heading; looking straight up, it points behind.
            var heading = simd_float2(direction.x, -direction.z)
            if simd_length(heading) < 0.0001 {
                heading = simd_float2(up.x, -up.z) * (direction.y < 0 ? 1 : -1)
            }
            let currentYaw = simd_length(heading) > 0.0001 ? atan2(heading.x, heading.y) : 0
            let currentPitch = asin(Swift.min(Swift.max(direction.y, -1), 1))

            let yaw = currentYaw + delta.x * lookSpeed
            let pitch = Swift.min(Swift.max(currentPitch + delta.y * lookSpeed, -lookPitchLimit), lookPitchLimit)
            return simd_float3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        }

        /// Turns the scene camera where it stands: the eye stays and the target
        /// swings around it, as far ahead as it was.
        func lookAroundSceneCamera(by delta: simd_float2) {
            guard delta.x.isFinite, delta.y.isFinite, delta.x != 0 || delta.y != 0 else {
                return
            }

            guard let camera = steeredCamera else {
                return
            }
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let eye = cameraComponent.localPosition
            // The camera looks down its negative Z axis, as the spawn code assumes.
            let forward = -forwardDirectionVector(from: cameraComponent.rotation)
            let direction = InputSystem.lookDirection(
                from: forward,
                up: upDirectionVector(from: cameraComponent.rotation),
                delta: delta
            )

            // Flying leaves the target where the last look-at put it, so only
            // its depth ahead is kept, within the range a pivot may have.
            let depth = simd_dot(getCameraTarget(entityId: camera) - eye, simd_normalize(forward))
            let reach = depth.isFinite
                && depth >= InputSystem.minimumOrbitPivotDistance
                && depth <= InputSystem.maximumOrbitPivotDistance
                ? depth : InputSystem.defaultOrbitPivotDistance
            cameraLookAt(entityId: camera, eye: eye, target: eye + direction * reach, up: cameraUpDefault)
        }

        /// Turns the scene camera around the point ahead of it from a drag,
        /// locked to the drag's dominant axis with X inverted and a one-point
        /// dead zone, as the orbit drag always was.
        func orbitSceneCamera(byDrag delta: simd_float2) {
            guard delta.x.isFinite, delta.y.isFinite else {
                return
            }
            var deltaX = delta.x
            var deltaY = delta.y

            if abs(deltaX) < abs(deltaY) {
                deltaX = 0.0
            } else {
                deltaY = 0.0
                deltaX = -deltaX
            }
            if abs(deltaX) <= 1.0 {
                deltaX = 0.0
            }
            if abs(deltaY) <= 1.0 {
                deltaY = 0.0
            }
            guard deltaX != 0 || deltaY != 0 else {
                return
            }
            orbitSteeredCamera(by: simd_float2(deltaX, deltaY) * InputSystem.dragOrbitSpeed)
        }

        func leftMouseDragged(_ delta: simd_float2) {
            mouseDeltaX = delta.x
            mouseDeltaY = delta.y

            if abs(mouseDeltaX) < abs(mouseDeltaY) {
                mouseDeltaX = 0.0
            } else {
                mouseDeltaY = 0.0
                // mouseDeltaX = -1.0 * mouseDeltaX
            }

            if abs(mouseDeltaX) <= 1.0 {
                mouseDeltaX = 0.0
            }

            if abs(mouseDeltaY) <= 1.0 {
                mouseDeltaY = 0.0
            }

            lastMouseX = mouseX
            lastMouseY = mouseY

            mouseX += mouseDeltaX
            mouseY += mouseDeltaY

            if mouseDeltaX != 0.0 || mouseDeltaY != 0.0 {
                // mouse is active
                mouseActive = true

            } else {
                //
                mouseActive = false
            }
        }

        func leftMouseDown(_ event: NSEvent) {
            switch event.buttonNumber {
            case 0:
                keyState.leftMousePressed = true
            case 1:
                keyState.rightMousePressed = true
            default:
                break
            }
        }

        func leftMouseUp(_ event: NSEvent) {
            mouseActive = false
            switch event.buttonNumber {
            case 0:
                keyState.leftMousePressed = false
            case 1:
                keyState.rightMousePressed = false
            default:
                break
            }
        }

        func keyPressed(_ keyCode: UInt16) {
            switch keyCode {
            case kVK_ANSI_A:
                keyState.aPressed = true
            case kVK_ANSI_W:
                keyState.wPressed = true
            case kVK_ANSI_D:
                keyState.dPressed = true
            case kVK_ANSI_S:
                keyState.sPressed = true
            case kVK_ANSI_Space:
                keyState.spacePressed = true
            case kVK_ANSI_Q:
                keyState.qPressed = true
            case kVK_ANSI_E:
                keyState.ePressed = true
//        case kVK_ANSI_G:
//            print("G pressed")
            case kVK_ANSI_X:
                guard let editorController else {
                    return
                }
                editorController.activeAxis = .x
            case kVK_ANSI_Y:
                guard let editorController else {
                    return
                }
                editorController.activeAxis = .y
            case kVK_ANSI_Z:
                guard let editorController else {
                    return
                }
                editorController.activeAxis = .z
            default:
                break
            }
        }

        /// The H key, which the engine's key table does not list: macOS virtual key code 0x04.
        private var kVK_ANSI_H: UInt16 {
            4
        }

        /// The F key, likewise: macOS virtual key code 0x03.
        private var kVK_ANSI_F: UInt16 {
            3
        }

        func keyReleased(_ keyCode: UInt16) {
            switch keyCode {
            case kVK_ANSI_A:
                keyState.aPressed = false
            case kVK_ANSI_W:
                keyState.wPressed = false
            case kVK_ANSI_D:
                keyState.dPressed = false
            case kVK_ANSI_S:
                keyState.sPressed = false
            case kVK_ANSI_Space:
                keyState.spacePressed = false
            case kVK_ANSI_Q:
                keyState.qPressed = false
            case kVK_ANSI_E:
                keyState.ePressed = false
            case kVK_ANSI_F:
                NotificationCenter.default.post(name: .editorFrameSelection, object: nil)
            case kVK_ANSI_P:
                // Play/Stop through the toolbar's flow, which snapshots and restores the scene.
                NotificationCenter.default.post(name: .editorTogglePlay, object: nil)
            case kVK_ANSI_H:
                // Hide the selection; with ⌥ held, show every hidden entity again.
                if NSEvent.modifierFlags.contains(.option) {
                    NotificationCenter.default.post(name: .editorShowAllEntities, object: nil)
                } else {
                    NotificationCenter.default.post(name: .editorHideSelectedEntity, object: nil)
                }
            case kVK_ANSI_R:
                if keyState.shiftPressed {
                    hotReload = !hotReload
                }
            default:
                break
            }
        }

        /// Takes the modifiers from an event. Every event the canvas receives
        /// carries them, so they are right even when they were pressed while
        /// another view had the keyboard.
        internal func syncModifiers(from event: NSEvent) {
            let flags = event.modifierFlags
            keyState.shiftPressed = flags.contains(.shift)
            keyState.ctrlPressed = flags.contains(.control)
            keyState.commandPressed = flags.contains(.command)
            keyState.altPressed = flags.contains(.option)
        }

        private func raycastContext(currentLocation: NSPoint, view: NSView) -> (rayOrigin: simd_float3, rayDirection: simd_float3)? {
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: findSceneCamera()) else {
                handleError(.noActiveCamera)
                return nil
            }

            let currentCGPoint = simd_float2(Float(currentLocation.x), Float(currentLocation.y))
            let viewportDimensions = simd_float2(Float(view.bounds.width), Float(view.bounds.height))
            guard viewportDimensions.x > 0, viewportDimensions.y > 0 else {
                return nil
            }

            let rayDirection: simd_float3 = rayDirectionInWorldSpace(
                uMouseLocation: currentCGPoint,
                uViewPortDim: viewportDimensions,
                uPerspectiveSpace: renderInfo.perspectiveSpace,
                uViewSpace: cameraComponent.viewSpace
            )

            guard rayDirection.x.isFinite, rayDirection.y.isFinite, rayDirection.z.isFinite else {
                return nil
            }

            return (cameraComponent.localPosition, rayDirection)
        }

        internal func getRaycastedEntity(currentLocation: NSPoint, view: NSView) -> (entityId: EntityID, hit: Bool) {
            guard let rayContext = raycastContext(currentLocation: currentLocation, view: view) else {
                return (.invalid, false)
            }

            let sceneHit = pickEntity(
                rayOrigin: rayContext.rayOrigin,
                rayDirection: rayContext.rayDirection,
                options: ScenePickOptions(isGizmoActive: gizmoActive, backend: .octreeGPUPreferred)
            )
            // Match ScenePickingSystem's gizmo-only rule. Shift temporarily allows scene
            // objects through while a gizmo is active.
            let gaussianHit = (!gizmoActive || keyState.shiftPressed)
                ? InputSystem.gaussianBoundsHit(
                    rayOrigin: rayContext.rayOrigin,
                    rayDirection: rayContext.rayDirection
                )
                : nil

            if let gaussianHit,
               gaussianHit.distance < (sceneHit?.distance ?? .greatestFiniteMagnitude)
            {
                return (gaussianHit.entityId, true)
            }

            if let sceneHit {
                return (sceneHit.entityId, true)
            }
            return (.invalid, false)
        }
    }
#endif
