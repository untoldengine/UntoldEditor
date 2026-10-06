//
//  CompositorFrameSource.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
#if canImport(CompositorServices) && canImport(ARKit)
    @_weakLinked import ARKit
    @_weakLinked import CompositorServices
    import Foundation
    import Metal
    import QuartzCore
    import simd
    import SwiftUI
    import UntoldEngine

    /// The headset's frames through CompositorServices and its pose through
    /// ARKit, for a Mac on macOS 26 drawing for an Apple Vision Pro nearby.
    @available(macOS 26.0, *)
    final class CompositorFrameSource: VisionProFrameSource, @unchecked Sendable {
        private let layerRenderer: LayerRenderer
        private let session: ARKitSession
        private let worldTracking = WorldTrackingProvider()
        private let lock = NSLock()
        private var stopped = false
        private var lastAnchor: DeviceAnchor?

        init(layerRenderer: LayerRenderer, device: RemoteDeviceIdentifier) {
            self.layerRenderer = layerRenderer
            session = ARKitSession(device: device)
            let session = session
            let worldTracking = worldTracking
            Task {
                do {
                    try await session.run([worldTracking])
                } catch {
                    Logger.log(message: "Vision Pro preview: the headset's tracking could not start (\(error.localizedDescription)).")
                }
            }
        }

        private var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func nextFrame() -> VisionProFrame? {
            while isStopped == false {
                switch layerRenderer.state {
                case .paused:
                    // Not `waitUntilRunning()`: a stop has to be seen meanwhile.
                    Thread.sleep(forTimeInterval: 0.01)
                case .running:
                    if let frame = layerRenderer.queryNextFrame() {
                        return CompositorFrame(frame: frame, layerRenderer: layerRenderer, source: self)
                    }
                case .invalidated:
                    return nil
                @unknown default:
                    return nil
                }
            }
            return nil
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
            session.stop()
        }

        /// The headset's pose for a moment, else the last one known.
        func deviceAnchor(for time: TimeInterval) -> DeviceAnchor? {
            if worldTracking.state == .running,
               let anchor = worldTracking.queryDeviceAnchor(atTimestamp: time) ?? worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
            {
                lock.lock()
                lastAnchor = anchor
                lock.unlock()
                return anchor
            }
            lock.lock()
            defer { lock.unlock() }
            return lastAnchor
        }
    }

    /// One of the compositor's frames.
    @available(macOS 26.0, *)
    final class CompositorFrame: VisionProFrame {
        private let frame: LayerRenderer.Frame
        private let layerRenderer: LayerRenderer
        private let source: CompositorFrameSource
        private var timing: LayerRenderer.Frame.Timing?
        private var drawables: [LayerRenderer.Drawable] = []

        init(frame: LayerRenderer.Frame, layerRenderer: LayerRenderer, source: CompositorFrameSource) {
            self.frame = frame
            self.layerRenderer = layerRenderer
            self.source = source
        }

        func beginUpdate() {
            timing = frame.predictTiming()
            frame.startUpdate()
        }

        func endUpdate() {
            frame.endUpdate()
        }

        func waitForDrawingTime() {
            guard let timing else { return }
            LayerRenderer.Clock().wait(until: timing.optimalInputTime, tolerance: .zero)
        }

        func beginDrawing() -> Bool {
            guard layerRenderer.state == .running else { return false }
            frame.startSubmission()
            return true
        }

        func acquireEyes() -> VisionProFrameEyes? {
            // The headset is the first drawable; another target the compositor
            // hands over is presented and left blank.
            drawables = frame.queryDrawables()
            guard let drawable = drawables.first else {
                return nil
            }
            let presentationTime = timing.map { Self.time(of: $0.presentationTime) } ?? CACurrentMediaTime()
            guard let anchor = source.deviceAnchor(for: presentationTime) else {
                return VisionProFrameEyes(originFromDevice: nil, eyes: [])
            }
            drawable.deviceAnchor = anchor
            let originFromDevice = anchor.originFromAnchorTransform
            let eyes = drawable.views.indices.map { index in
                VisionProEye(
                    colorTexture: drawable.colorTextures[index],
                    depthTexture: drawable.depthTextures[index],
                    viewFromOrigin: simd_inverse(simd_mul(originFromDevice, drawable.views[index].transform)),
                    projection: drawable.computeProjection(convention: .rightUpBack, viewIndex: index)
                )
            }
            return VisionProFrameEyes(originFromDevice: originFromDevice, eyes: eyes)
        }

        func present(commandBuffer: MTLCommandBuffer) {
            for drawable in drawables {
                drawable.encodePresent(commandBuffer: commandBuffer)
            }
        }

        func endDrawing() {
            guard layerRenderer.state == .running else { return }
            frame.endSubmission()
        }

        /// A moment of the compositor's clock as `CACurrentMediaTime` measures it.
        private static func time(of instant: LayerRenderer.Clock.Instant) -> TimeInterval {
            let ahead = LayerRenderer.Clock().now.duration(to: instant)
            return CACurrentMediaTime() + Double(ahead.components.seconds) + Double(ahead.components.attoseconds) / 1e18
        }
    }
#endif
