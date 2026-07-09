//
//  EditorRenderingSystem.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import UntoldEngine

/// Adds editor-only overlays to the engine-owned render graph.
///
/// The engine compiles and executes the graph. Keeping the editor passes in a
/// rendering extension means they participate in graph validation and continue
/// to work as the engine adds or reorders its internal passes.
final class EditorRenderExtension: RenderExtension, @unchecked Sendable {
    static let shared = EditorRenderExtension()

    let id = "untold.editor.rendering"

    private init() {}

    func registerPipelines(_ registry: RenderPipelineRegistry) {
        registry.registerRenderPipeline(.editorGizmo, initBlock: InitGizmoPipeline)
    }

    func buildGraph(
        _ builder: inout RenderGraphBuilder,
        context _: RenderGraphBuildContext
    ) {
        // Play mode uses the unmodified runtime graph.
        guard !gameMode else { return }

        builder.addPass(
            id: "untold.editor.highlight",
            stage: .beforeComposite
        ) { context in
            RenderPasses.highlightExecution(context.commandBuffer)
        }

        builder.addPass(
            id: "untold.editor.lightVisuals",
            stage: .beforeComposite
        ) { context in
            RenderPasses.lightVisualPass(context.commandBuffer)
        }

        builder.addPass(
            id: "untold.editor.gizmo",
            stage: .beforeComposite
        ) { context in
            RenderPasses.gizmoExecution(context.commandBuffer)
        }
    }
}

@discardableResult
func registerEditorRenderExtension() -> RenderExtensionRegistrationResult {
    RenderExtensionRegistry.shared.register(EditorRenderExtension.shared)
}
