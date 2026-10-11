//
//  BakePromptSheet.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What the asset browser presents the post-import hint for: the single source file
/// that was just imported into Resources. Only shown after a single-file import (see
/// `importSourcesIntoResources`) -- an import of several files would need its own line
/// per file, which isn't worth a sheet.
struct BakePromptRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
}

/// A one-time-per-import nudge telling a first-time user where their import landed and
/// how to turn it into a runtime asset -- purely informational, it doesn't cook
/// anything itself (that stays right-click-only, same as always; see the context menu
/// in `AssetBrowserView+Contents.swift`). "Don't show this again" is an app-wide
/// preference (not per-project): it's an onboarding nudge, not a project setting.
struct BakePromptSheet: View {
    let sourceURL: URL
    let onDismiss: () -> Void
    @Binding var dontShowAgain: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Imported to Resources")
                .font(.headline)

            Text("\u{201C}\(sourceURL.lastPathComponent)\u{201D} has been imported into Resources. To cook it as a runtime asset (a Model, Animation, or Tiled Stream Model), right-click it and choose a cook option.")
                .font(.system(size: 12))
                .foregroundColor(.editorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Don't show this again", isOn: $dontShowAgain)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("OK") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
