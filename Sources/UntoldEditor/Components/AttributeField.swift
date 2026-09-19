//
//  AttributeField.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import simd
import SwiftUI
import UntoldComponentKit
import UntoldEngine

// MARK: - One attribute

/// The control for one attribute, chosen by its kind. Reads through the wrapper every time it
/// renders, and hands changes to `commit` as the JSON-shaped value the kit stores.
struct AttributeField: View {
    let entry: UntoldAttributeEntry
    let commit: (UntoldAttributeValue) -> Void

    private var label: String {
        entry.displayLabel
    }

    private var current: UntoldAttributeValue {
        entry.attribute.attributeValue
    }

    var body: some View {
        switch entry.attribute.kind {
        case .float:
            numberField(fractionDigits: nil) { .number(Double($0)) }
        case .int:
            numberField(fractionDigits: 0) { .number(Double($0.rounded())) }
        case .bool:
            Toggle(label, isOn: Binding(
                get: { current == .bool(true) },
                set: { commit(.bool($0)) }
            ))
            .font(.caption)
        case .string:
            labeled { CommitTextField(text: stringValue, multiline: false) { commit(.string($0)) } }
        case .text:
            labeled { CommitTextField(text: stringValue, multiline: true) { commit(.string($0)) } }
        case .vector3:
            TextInputVectorView(label: label, value: Binding(
                get: { vector(3).map { SIMD3<Float>($0[0], $0[1], $0[2]) } ?? .zero },
                set: { commit(.array([$0.x, $0.y, $0.z].map(Double.init))) }
            ))
        case .vector4:
            vector4Field
        case .color:
            labeled {
                ColorPicker("", selection: Binding(
                    get: { Self.color(from: vector(4) ?? [1, 1, 1, 1]) },
                    set: { commit(.array(Self.components(of: $0).map(Double.init))) }
                ))
                .labelsHidden()
            }
        case .entity:
            picker(options: [""] + Self.entityNames(), title: { $0.isEmpty ? "None" : $0 }, selected: objectField("entity")) {
                commit(.object(["entity": $0]))
            }
        case let .asset(category):
            picker(options: [""] + Self.assetPaths(in: category), title: { $0.isEmpty ? "None" : $0 }, selected: objectField("asset")) {
                commit(.object(["asset": $0]))
            }
        case let .enumeration(cases):
            picker(options: cases, title: { humanizedIdentifier($0) }, selected: stringValue) {
                commit(.string($0))
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func numberField(fractionDigits: Int?, encode: @escaping (Float) -> UntoldAttributeValue) -> some View {
        let binding = Binding<Float>(
            get: {
                if case let .number(value) = current {
                    return Float(value)
                } else {
                    return 0
                }
            },
            set: { commit(encode($0)) }
        )
        VStack(alignment: .leading, spacing: 2) {
            TextInputNumberView(label: label, value: binding, fractionDigits: fractionDigits)
            if let range = entry.attribute.range {
                RangeSlider(value: binding, range: Float(range.lowerBound) ... Float(range.upperBound), step: entry.attribute.step.map(Float.init))
            }
        }
    }

    private var vector4Field: some View {
        let components = vector(4) ?? [0, 0, 0, 0]
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.editorTextSecondary)
            ForEach(0 ..< 4, id: \.self) { index in
                TextInputNumberView(label: ["X", "Y", "Z", "W"][index], value: Binding(
                    get: { components[index] },
                    set: { newValue in
                        var updated = components
                        updated[index] = newValue
                        commit(.array(updated.map(Double.init)))
                    }
                ))
            }
        }
    }

    private func labeled(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption).foregroundColor(.editorTextSecondary)
            content()
        }
    }

    private func picker(
        options: [String],
        title: @escaping (String) -> String,
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        labeled {
            Picker("", selection: Binding(get: { selected }, set: onSelect)) {
                // A saved value that is no longer offered (a renamed entity, a moved asset)
                // still has to show, or the picker would silently display something else.
                ForEach(options.contains(selected) ? options : options + [selected], id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .labelsHidden()
        }
    }

    // MARK: Reading the current value

    private var stringValue: String {
        if case let .string(text) = current {
            return text
        }
        return ""
    }

    private func vector(_ count: Int) -> [Float]? {
        guard case let .array(numbers) = current, numbers.count == count else { return nil }
        return numbers.map(Float.init)
    }

    private func objectField(_ key: String) -> String {
        if case let .object(fields) = current {
            return fields[key] ?? ""
        }
        return ""
    }

    // MARK: Option sources

    private static func entityNames() -> [String] {
        Set(getAllGameEntities().map { getEntityName(entityId: $0) }.filter { $0.isEmpty == false }).sorted()
    }

    /// Project-relative paths of the files in one asset category, or in all of them.
    private static func assetPaths(in category: String?) -> [String] {
        guard let base = assetBasePath else { return [] }
        let root = category.map { base.appendingPathComponent($0, isDirectory: true) } ?? base
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        let prefix = base.standardizedFileURL.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) {
                paths.append(String(path.dropFirst(prefix.count)))
            }
            if paths.count >= 300 {
                break
            }
        }
        return paths.sorted()
    }

    // MARK: Color

    /// Attributes hold linear RGBA, which is what the engine's shading expects.
    private static let linearSpace = CGColorSpace(name: CGColorSpace.linearSRGB)

    private static func color(from components: [Float]) -> Color {
        Color(.sRGBLinear, red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]), opacity: Double(components[3]))
    }

    private static func components(of color: Color) -> [Float] {
        guard let space = linearSpace,
              let converted = NSColor(color).cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let values = converted.components, values.count >= 4
        else { return [1, 1, 1, 1] }
        return values.prefix(4).map { Float($0) }
    }
}
