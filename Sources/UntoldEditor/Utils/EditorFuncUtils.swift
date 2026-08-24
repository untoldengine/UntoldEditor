//
//  EditorFuncUtils.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import ModelIO
import SwiftUI
import UntoldEngine

func bindingForWrapMode(
    entityId: EntityID,
    textureType: TextureType,
    meshIndex: Int = 0,
    submeshIndex: Int = 0,
    onChange: @escaping () -> Void
) -> Binding<WrapMode> {
    Binding<WrapMode>(
        get: {
            guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId),
                  renderComponent.mesh.indices.contains(meshIndex),
                  renderComponent.mesh[meshIndex].submeshes.indices.contains(submeshIndex),
                  let material = renderComponent.mesh[meshIndex].submeshes[submeshIndex].material
            else {
                return .clampToEdge // fallback
            }

            switch textureType {
            case .baseColor:
                return material.baseColor.wrapMode
            case .normal:
                return material.normal.wrapMode
            case .roughness:
                return material.roughness.wrapMode
            case .metallic:
                return material.metallic.wrapMode
            }
        },
        set: { newValue in
            updateTextureSampler(entityId: entityId, textureType: textureType, wrapMode: newValue)
            onChange()
        }
    )
}

func bindingForSTScale(entityId: EntityID, onChange: @escaping () -> Void) -> Binding<Float> {
    Binding<Float>(
        get: {
            guard let rc = scene.get(component: RenderComponent.self, for: entityId),
                  let material = rc.mesh[0].submeshes[0].material
            else {
                return 1.0
            }
            return material.stScale
        },
        set: { newValue in
            updateMaterialSTScale(entityId: entityId, stScale: newValue)
            onChange()
        }
    )
}

func bindingForMaterialRoughness(entityId: EntityID, onChange: @escaping () -> Void) -> Binding<Float> {
    Binding<Float>(
        get: {
            getMaterialRoughness(entityId: entityId)
        },
        set: { newValue in
            updateMaterialRoughness(entityId: entityId, roughness: newValue)
            onChange()
        }
    )
}

/// Helper function to get NSImage from material texture, handling both file-based and embedded USDZ textures
func getMaterialTextureImage(
    entityId: EntityID,
    type: TextureType,
    meshIndex: Int = 0,
    submeshIndex: Int = 0
) -> NSImage? {
    // First, check if we have a URL
    guard let url = getMaterialTextureURL(entityId: entityId, type: type, meshIndex: meshIndex, submeshIndex: submeshIndex) else {
        return nil
    }

    // Check if this is an embedded USDZ texture
    if isEmbeddedUSDZTexture(url) {
        // For embedded textures, we need to extract the image from MDLTexture
        guard let mdlTexture = getMaterialMDLTexture(entityId: entityId, type: type, meshIndex: meshIndex, submeshIndex: submeshIndex) else {
            print("Warning: Could not get MDLTexture for embedded texture: \(url)")
            return nil
        }

        // Convert MDLTexture to NSImage via CGImage
        if let image = nsImageFromMDLTexture(mdlTexture) {
            return image
        } else {
            print("Warning: Failed to convert MDLTexture to NSImage for: \(url)")
            return nil
        }
    } else {
        // For file-based textures, load directly from URL
        return NSImage(contentsOf: url)
    }
}

/// Convert MDLTexture to NSImage
func nsImageFromMDLTexture(_ mdlTexture: MDLTexture) -> NSImage? {
    // Get the texture data from MDLTexture
    guard let texelData = mdlTexture.texelDataWithTopLeftOrigin() else {
        print("Error: texelDataWithTopLeftOrigin() returned nil")
        return nil
    }

    let width = Int(mdlTexture.dimensions.x)
    let height = Int(mdlTexture.dimensions.y)
    let channelCount = Int(mdlTexture.channelCount)

    // Validate dimensions
    guard width > 0, height > 0, channelCount > 0 else {
        print("Error: Invalid texture dimensions - width: \(width), height: \(height), channels: \(channelCount)")
        return nil
    }

    let bytesPerRow = width * channelCount

    // Create a CGImage from the texture data
    guard let dataProvider = CGDataProvider(data: texelData as CFData) else {
        return nil
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = mdlTexture.channelCount == 4
        ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        : CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

    guard let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: channelCount * 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: dataProvider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    ) else {
        print("Error: Failed to create CGImage with dimensions \(width)x\(height), channels: \(channelCount)")
        return nil
    }

    let size = NSSize(width: CGFloat(width), height: CGFloat(height))
    return NSImage(cgImage: cgImage, size: size)
}
