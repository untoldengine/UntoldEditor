//
//  SunOrientation.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

func editorSetSunElevation(entityId: EntityID, elevation: Float) {
    let angles = getSunElevationAzimuth(entityId: entityId)
    setSunElevationAzimuth(
        entityId: entityId,
        elevation: elevation,
        azimuth: angles.azimuth
    )
    syncLightDirectionHandleToActiveLight(entityId: entityId)
}

func editorSetSunAzimuth(entityId: EntityID, azimuth: Float) {
    let angles = getSunElevationAzimuth(entityId: entityId)
    setSunElevationAzimuth(
        entityId: entityId,
        elevation: angles.elevation,
        azimuth: azimuth
    )
    syncLightDirectionHandleToActiveLight(entityId: entityId)
}
