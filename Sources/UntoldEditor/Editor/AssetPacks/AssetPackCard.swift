//
//  AssetPackCard.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import Foundation
import SwiftUI
import UntoldEngine

struct AssetPackCard: View {
    private let thumbnailHeight: CGFloat = 124

    let item: AssetPackCatalogItem
    let thumbnail: NSImage?
    let isInstalled: Bool
    let isInstalling: Bool
    let installAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.editorFillSubtle)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    Image(systemName: thumbnailIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.editorTextTertiary)
                }
            }
            .frame(height: thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture(perform: installAction)

            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)

            Text(item.description)
                .font(.system(size: 11))
                .foregroundColor(.editorTextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                ForEach(item.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.editorTextSecondary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(Color.editorFill)
                        .cornerRadius(4)
                }

                Spacer(minLength: 0)
            }
            .frame(height: 18, alignment: .leading)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.size)
                        .font(.system(size: 11))
                        .foregroundColor(.editorTextTertiary)
                    Text("v\(item.version)")
                        .font(.system(size: 10))
                        .foregroundColor(.editorTextTertiary)
                }

                Spacer()

                Button(action: installAction) {
                    Label(buttonTitle, systemImage: buttonIcon)
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.editorAccent)
                .disabled(isInstalling)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(Color.editorSurface.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private var thumbnailIcon: String {
        switch item.category {
        case "Architecture":
            return "building.2.fill"
        case "Streaming":
            return "square.3.layers.3d.down.right"
        case "Digital Twin":
            return "viewfinder"
        default:
            return "shippingbox.fill"
        }
    }

    private var buttonTitle: String {
        if isInstalling { return "Installing" }
        return isInstalled ? "Reinstall" : "Download"
    }

    private var buttonIcon: String {
        if isInstalling { return "arrow.down.circle" }
        return isInstalled ? "arrow.clockwise" : "arrow.down.circle"
    }
}
