//
//  EditorSceneSwitchGate.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import SwiftUI

/// Cross-view scratch storage for "the action to run once a triggered save
/// completes." Plain class, not ObservableObject — nothing observes it for
/// rendering, matches the existing EditorGaussianAssetState singleton pattern.
final class EditorPendingSwitchAction {
    static let shared = EditorPendingSwitchAction()
    private init() {}
    var pending: (() -> Void)?

    func consume() {
        let action = pending
        pending = nil
        action?()
    }

    func cancel() {
        pending = nil
    }
}

/// Runs `action` immediately if the scene is clean; if dirty, stashes it and
/// shows the caller's "Unsaved Changes" alert instead.
func requestDestructiveSceneAction(
    _ action: @escaping () -> Void,
    describing description: String,
    showAlert: Binding<Bool>,
    alertMessage: Binding<String>
) {
    if EditorSceneDirtyState.shared.isDirty {
        EditorPendingSwitchAction.shared.pending = action
        alertMessage.wrappedValue = "Save changes before \(description)?"
        showAlert.wrappedValue = true
    } else {
        action()
    }
}
