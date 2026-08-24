//
//  EditorRenderPipeLines.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UntoldEngine

// MARK: Gizmo Pipeline

public func InitGizmoPipeline() -> RenderPipeline? {
    CreatePipeline(
        vertexShader: "vertexGizmoShader",
        fragmentShader: "fragmentGizmoShader",
        vertexDescriptor: createGizmoVertexDescriptor(),
        colorFormats: [renderInfo.colorPixelFormat],
        depthFormat: renderInfo.depthPixelFormat,
        name: "Gizmo Pipeline"
    )
}

// MARK: Debug Pipeline

public func InitDebugPipeline() -> RenderPipeline? {
    CreatePipeline(
        vertexShader: "vertexDebugShader",
        fragmentShader: "fragmentDebugShader",
        vertexDescriptor: createDebugVertexDescriptor(),
        colorFormats: [.bgra8Unorm_srgb],
        depthFormat: renderInfo.depthPixelFormat,
        depthCompareFunction: .less,
        depthEnabled: false,
        name: "Debug Pipeline"
    )
}

public extension RenderPipelineType {
    static let gizmo: RenderPipelineType = "gizmo"
    static let editorGizmo: RenderPipelineType = "untold.editor.gizmoPipeline"
}

public func EditorDefaultPipeLines() -> [(RenderPipelineType, RenderPipelineInitBlock)] {
    DefaultPipeLines() + [
        (.gizmo, InitGizmoPipeline),
    ]
}
