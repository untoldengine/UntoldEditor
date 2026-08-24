//
//  Globals.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import UntoldEngine

var editorController: EditorController?

var visualDebug: Bool = false
var hotReload: Bool = false

var selectionDelegate: SelectionDelegate?

// Gizmo active
var gizmoActive: Bool = false
var activeHitGizmoEntity: EntityID = .invalid
var parentEntityIdGizmo: EntityID = .invalid
var directionHandleEntityId: EntityID = .invalid

let gizmoDesiredScreenSize: Float = 75.0 // pixels

var spawnDistance: Float = 2.0

/// Visual Debugger
enum DebugSelection: Int {
    case normalOutput
    case iblOutput
}

var currentDebugSelection: DebugSelection = .normalOutput

// light debug meshes
var spotLightDebugMesh: [Mesh] = []
var pointLightDebugMesh: [Mesh] = []
var areaLightDebugMesh: [Mesh] = []
var dirLightDebugMesh: [Mesh] = []

class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    @Published var selectedName: String = ""
    @Published var debugEnabled: Bool = true
}

/// Editor
public var enableEditor: Bool = true
