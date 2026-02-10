//
//  RenderingSystem.swift
//  UntoldEngine
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import MetalKit
import UntoldEngine

func EditorUpdateRenderingSystem(in view: MTKView) {
    // Limit in-flight command buffers so triple-buffered culling data isn't overwritten
    commandBufferSemaphore.wait()

    if let commandBuffer = renderInfo.commandQueue.makeCommandBuffer() {
        renderInfo.lastCommandBuffer = commandBuffer
        performFrustumCulling(commandBuffer: commandBuffer)

        executeGaussianDepth(commandBuffer)
        executeBitonicSort(commandBuffer)
        if let renderPassDescriptor = view.currentRenderPassDescriptor {
            renderInfo.renderPassDescriptor = renderPassDescriptor

            commandBuffer.label = "Rendering Command Buffer"

            // build a render graph
            var (graph, _) = gameMode ? buildGameModeGraph() : buildEditModeGraph()

//            if visualDebug == false {
//                let compositePass = RenderPass(
//                    id: "composite", dependencies: [preCompID], execute: RenderPasses.compositeExecution
//                )
//
//                graph[compositePass.id] = compositePass
//            } else {
//                let debugPass = RenderPass(
//                    id: "debug", dependencies: [preCompID], execute: RenderPasses.debuggerExecution
//                )
//
//                graph[debugPass.id] = debugPass
//            }

            // sorted it
            let sortedPasses = try! topologicalSortGraph(graph: graph)

            // execute it
            executeGraph(graph, sortedPasses, commandBuffer)
        }

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.addCompletedHandler { _ in
            // Release the in-flight slot
            commandBufferSemaphore.signal()
            DispatchQueue.main.async {
                needsFinalizeDestroys = true
                visibleEntityIds = tripleVisibleEntities.snapshotForRead(frame: cullFrameIndex)
            }
        }

        commandBuffer.commit()
    } else {
        // Failed to create command buffer - release slot
        commandBufferSemaphore.signal()
    }
}

func buildEditModeGraph() -> RenderGraphResult {
    var graph = [String: RenderPass]()

    let basePassID: String
    if renderEnvironment {
        let environmentPass = RenderPass(
            id: "environment", dependencies: [], execute: RenderPasses.executeEnvironmentPass
        )
        graph[environmentPass.id] = environmentPass
        basePassID = environmentPass.id
    } else {
        let gridPass = RenderPass(
            id: "grid", dependencies: [], execute: RenderPasses.gridExecution
        )
        graph[gridPass.id] = gridPass
        basePassID = gridPass.id
    }

    let shadowPass = RenderPass(
        id: "shadow", dependencies: [basePassID], execute: RenderPasses.shadowExecution
    )
    graph[shadowPass.id] = shadowPass

    // Add batched shadow pass (runs after regular shadow pass)
    let batchedShadowPass = RenderPass(
        id: "batchedShadow", dependencies: [shadowPass.id], execute: RenderPasses.batchedShadowExecution
    )
    graph[batchedShadowPass.id] = batchedShadowPass

    let modelPass = RenderPass(
        id: "model", dependencies: [batchedShadowPass.id], execute: RenderPasses.modelExecution
    )
    graph[modelPass.id] = modelPass

    // Add batched model pass (runs after regular model pass)
    let batchedModelPass = RenderPass(
        id: "batchedModel", dependencies: [modelPass.id], execute: RenderPasses.batchedModelExecution
    )
    graph[batchedModelPass.id] = batchedModelPass

    let lightPass = RenderPass(id: "lightPass", dependencies: [batchedModelPass.id, modelPass.id, shadowPass.id], execute: RenderPasses.lightExecution)
    graph[lightPass.id] = lightPass

    let highlightPass = RenderPass(
        id: "outline", dependencies: [batchedModelPass.id], execute: RenderPasses.highlightExecution
    )
    graph[highlightPass.id] = highlightPass

    let lightVisualsPass = RenderPass(id: "lightVisualPass", dependencies: [highlightPass.id], execute: RenderPasses.lightVisualPass)

    graph[lightVisualsPass.id] = lightVisualsPass

    let gizmoPass = RenderPass(id: "gizmo", dependencies: [lightVisualsPass.id], execute: RenderPasses.gizmoExecution)

    graph[gizmoPass.id] = gizmoPass

    // Gaussian pass depends on model pass - needs depth buffer from 3D models
    let gaussianPass = RenderPass(id: "gaussian", dependencies: [modelPass.id], execute: RenderPasses.gaussianExecution)
    graph[gaussianPass.id] = gaussianPass

    let preCompPass = RenderPass(
        id: "precomp", dependencies: [modelPass.id, gizmoPass.id, lightPass.id, gaussianPass.id], execute: RenderPasses.preCompositeExecution
    )
    graph[preCompPass.id] = preCompPass

    return (graph, preCompPass.id)
}
