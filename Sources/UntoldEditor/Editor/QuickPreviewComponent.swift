//
//  QuickPreviewComponent.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import Foundation
import UntoldEngine

/// Marks an entity as being loaded via Quick Preview with an absolute path.
/// These entities cannot be serialized and must be removed before saving the scene.
public class QuickPreviewComponent: Component {
    /// The absolute file path to the original asset
    public var absoluteFilePath: String

    /// The file extension (usdz, ply, etc.)
    public var fileExtension: String

    /// The original filename without extension
    public var originalFileName: String

    public required init() {
        absoluteFilePath = ""
        fileExtension = ""
        originalFileName = ""
    }

    public init(absoluteFilePath: String, fileExtension: String, originalFileName: String) {
        self.absoluteFilePath = absoluteFilePath
        self.fileExtension = fileExtension
        self.originalFileName = originalFileName
    }
}
