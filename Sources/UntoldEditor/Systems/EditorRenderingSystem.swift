//
//  RenderingSystem.swift
//  UntoldEngine
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import MetalKit
import QuartzCore
import UntoldEngine

@MainActor
func EditorUpdateRenderingSystem(in view: MTKView) {
    // While assets are loading, keep rendering from the last-known-good visible
    // list and avoid ECS traversal in culling / gaussian prep.
    let loading = AssetLoadingGate.shared.isLoadingAny

    if !loading {
        visibleEntityIds = tripleVisibleEntities.snapshotForRead(frame: cullFrameIndex)
    }

    // Limit in-flight command buffers so triple-buffered culling data isn't overwritten
    commandBufferSemaphore.wait()

    if let commandBuffer = renderInfo.commandQueue.makeCommandBuffer() {
        #if ENGINE_STATS_ENABLED
            let renderTotalStart = CACurrentMediaTime()
        #endif
        renderInfo.lastCommandBuffer = commandBuffer
        renderInfo.currentInFlightFrameSlot = acquireUniformFrameSlot()

        // Keep scene-root-derived camera/light matrices current before culling
        // and render passes read them.
        SceneRootTransform.shared.updateIfNeeded()

        if !loading {
            #if ENGINE_STATS_ENABLED
                let renderPrepStart = CACurrentMediaTime()
                let cullingStart = CACurrentMediaTime()
            #endif
            EngineProfiler.shared.beginScope(.renderPrep)
            EngineProfiler.shared.beginScope(.culling)
            performFrustumCulling(commandBuffer: commandBuffer)
            EngineProfiler.shared.endScope(.culling)
            #if ENGINE_STATS_ENABLED
                let cullingMs = (CACurrentMediaTime() - cullingStart) * 1000.0
                EngineStatsMonitor.shared.update { snapshot in
                    snapshot.timing.cullingMs += cullingMs
                }
            #endif

            executeGaussianDepth(commandBuffer)
            executeRadixSort(commandBuffer)
            EngineProfiler.shared.endScope(.renderPrep)
            #if ENGINE_STATS_ENABLED
                let renderPrepMs = (CACurrentMediaTime() - renderPrepStart) * 1000.0
                EngineStatsMonitor.shared.update { snapshot in
                    snapshot.timing.renderPrepMs += renderPrepMs
                }
            #endif
        }
        if let renderPassDescriptor = view.currentRenderPassDescriptor {
            renderInfo.renderPassDescriptor = renderPassDescriptor

            commandBuffer.label = "Rendering Command Buffer"

            // build a render graph
            let (graph, _) = gameMode ? buildGameModeGraph() : buildEditModeGraph()

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
            #if ENGINE_STATS_ENABLED
                let encodeStart = CACurrentMediaTime()
            #endif
            EngineProfiler.shared.beginScope(.encode)
            executeGraph(graph, sortedPasses, commandBuffer)
            // Keep editor in sync with runtime temporal HZB:
            // render depth this frame -> build HZB -> consume next frame during culling
            buildHZBDepthPyramid(commandBuffer)
            EngineProfiler.shared.endScope(.encode)
            #if ENGINE_STATS_ENABLED
                let encodeMs = (CACurrentMediaTime() - encodeStart) * 1000.0
                EngineStatsMonitor.shared.update { snapshot in
                    snapshot.timing.encodeMs += encodeMs
                }
            #endif
        }

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        EngineProfiler.shared.attach(to: commandBuffer, label: "EditorFrame")
        let visibleEntityIdsAtSubmission = visibleEntityIds
        commandBuffer.addCompletedHandler { cb in
            #if ENGINE_STATS_ENABLED
                let gpuExecutionMs = (cb.gpuEndTime - cb.gpuStartTime) * 1000.0
                EngineStatsMonitor.shared.recordGPUCompletion(executionMs: gpuExecutionMs)
            #endif
            // Release the in-flight slot
            commandBufferSemaphore.signal()
            needsFinalizeDestroys = true
            MemoryBudgetManager.shared.markUsed(entityIds: visibleEntityIdsAtSubmission)
        }

        #if ENGINE_STATS_ENABLED
            let submitStart = CACurrentMediaTime()
        #endif
        commandBuffer.commit()
        #if ENGINE_STATS_ENABLED
            let submitMs = (CACurrentMediaTime() - submitStart) * 1000.0
            let renderTotalMs = (CACurrentMediaTime() - renderTotalStart) * 1000.0
            EngineStatsMonitor.shared.update { snapshot in
                snapshot.timing.submitMs += submitMs
                snapshot.timing.renderTotalMs += renderTotalMs
            }
        #endif
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
        id: "model", dependencies: [batchedShadowPass.id], execute: RenderPasses.combinedModelLightExecution
    )
    graph[modelPass.id] = modelPass

    // Geometry and lighting now execute inside the TBDR model pass. Keep the
    // legacy graph nodes as dependency anchors for editor overlays.
    let batchedModelPass = RenderPass(id: "batchedModel", dependencies: [modelPass.id], execute: nil)
    graph[batchedModelPass.id] = batchedModelPass

    let lightPass = RenderPass(id: "lightPass", dependencies: [batchedModelPass.id, modelPass.id, shadowPass.id], execute: nil)
    graph[lightPass.id] = lightPass

    let transparencyPass = RenderPass(
        id: "transparency", dependencies: [lightPass.id], execute: RenderPasses.transparencyExecution
    )
    graph[transparencyPass.id] = transparencyPass

    // Spatial debug overlays are rendered on top of lit scene color.
    let spatialDebugPass = RenderPass(
        id: "spatialDebug",
        dependencies: [transparencyPass.id],
        execute: RenderPasses.spatialDebugBoundsExecution
    )
    graph[spatialDebugPass.id] = spatialDebugPass

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
        id: "precomp", dependencies: [modelPass.id, gizmoPass.id, spatialDebugPass.id, gaussianPass.id], execute: RenderPasses.editorPreCompositeExecution
    )
    graph[preCompPass.id] = preCompPass

    let lookPass = RenderPass(
        id: "look",
        dependencies: [preCompPass.id],
        execute: lookRenderPass
    )
    graph[lookPass.id] = lookPass

    let outputDependency: String
    if renderDebugViewMode == .fxaaEdgeDebug {
        let fxaaEdgeDebugPass = RenderPass(id: "fxaaEdgeDebug", dependencies: [lookPass.id], execute: fxaaEdgeDebugRenderPass)
        graph[fxaaEdgeDebugPass.id] = fxaaEdgeDebugPass
        outputDependency = fxaaEdgeDebugPass.id
    } else if renderDebugViewMode == .smaaEdges {
        let smaaEdgesPass = RenderPass(id: "smaaEdges", dependencies: [lookPass.id], execute: smaaEdgesRenderPass)
        graph[smaaEdgesPass.id] = smaaEdgesPass
        outputDependency = smaaEdgesPass.id
    } else if renderDebugViewMode == .smaaBlend {
        let smaaEdgesPass = RenderPass(id: "smaaEdges", dependencies: [lookPass.id], execute: smaaEdgesRenderPass)
        graph[smaaEdgesPass.id] = smaaEdgesPass

        let smaaBlendWeightsPass = RenderPass(
            id: "smaaBlendWeights",
            dependencies: [smaaEdgesPass.id],
            execute: smaaBlendWeightsRenderPass
        )
        graph[smaaBlendWeightsPass.id] = smaaBlendWeightsPass
        outputDependency = smaaBlendWeightsPass.id
    } else if renderDebugViewMode == .smaaDifference {
        let smaaEdgesPass = RenderPass(id: "smaaEdges", dependencies: [lookPass.id], execute: smaaEdgesRenderPass)
        graph[smaaEdgesPass.id] = smaaEdgesPass

        let smaaBlendWeightsPass = RenderPass(
            id: "smaaBlendWeights",
            dependencies: [smaaEdgesPass.id],
            execute: smaaBlendWeightsRenderPass
        )
        graph[smaaBlendWeightsPass.id] = smaaBlendWeightsPass

        let smaaNeighborhoodPass = RenderPass(
            id: "smaaNeighborhood",
            dependencies: [smaaBlendWeightsPass.id],
            execute: smaaNeighborhoodRenderPass
        )
        graph[smaaNeighborhoodPass.id] = smaaNeighborhoodPass

        let smaaDifferencePass = RenderPass(
            id: "smaaDifference",
            dependencies: [smaaNeighborhoodPass.id],
            execute: smaaDifferenceRenderPass
        )
        graph[smaaDifferencePass.id] = smaaDifferencePass
        outputDependency = smaaDifferencePass.id
    } else {
        switch antiAliasingMode {
        case .fxaa:
            let fxaaPass = RenderPass(
                id: "fxaa",
                dependencies: [lookPass.id],
                execute: fxaaRenderPass
            )
            graph[fxaaPass.id] = fxaaPass
            outputDependency = fxaaPass.id
        case .smaa:
            let smaaEdgesPass = RenderPass(id: "smaaEdges", dependencies: [lookPass.id], execute: smaaEdgesRenderPass)
            graph[smaaEdgesPass.id] = smaaEdgesPass

            let smaaBlendWeightsPass = RenderPass(
                id: "smaaBlendWeights",
                dependencies: [smaaEdgesPass.id],
                execute: smaaBlendWeightsRenderPass
            )
            graph[smaaBlendWeightsPass.id] = smaaBlendWeightsPass

            let smaaNeighborhoodPass = RenderPass(
                id: "smaaNeighborhood",
                dependencies: [smaaBlendWeightsPass.id],
                execute: smaaNeighborhoodRenderPass
            )
            graph[smaaNeighborhoodPass.id] = smaaNeighborhoodPass
            outputDependency = smaaNeighborhoodPass.id
        case .none:
            outputDependency = lookPass.id
        }
    }

    let outputPass = RenderPass(
        id: "outputTransform",
        dependencies: [outputDependency],
        execute: outputTransformRenderPass
    )
    graph[outputPass.id] = outputPass

    return (graph, outputPass.id)
}
