//
//  CodeComponentInspectorView.swift
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

/// The components written in code that the entity carries, shown in the Inspector the way
/// the engine's components are: one block each, a headline with a remove button, then a
/// field for every `@UntoldAttribute` and a button for every action. They are added from
/// the Inspector's one Add Component menu (`AddComponentMenu`), alongside the engine's.
///
/// Drawn by the Inspector directly rather than registered as component options, because the
/// set of types changes whenever a library loads, and so scene-composition mode keeps them.
struct CodeComponentInspectorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @ObservedObject private var controller = ComponentLibraryController.shared

    /// Whether the Inspector has anything to draw for `entityId`.
    static func isAvailable(for entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return false }
        return CodeComponentSystem.shared.slots(on: entityId).isEmpty == false
    }

    /// The loaded component types `entityId` does not carry yet, for the Add Component menu.
    /// A component that is part of a kind of entity (`.entityKindOnly`) is never offered: a
    /// torus's shape means nothing on a cube, and only the kind's template adds it.
    static func addableTypes(for entityId: EntityID) -> [CodeComponentRegistry.Entry] {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return [] }
        let present = Set(CodeComponentSystem.shared.slots(on: entityId).map(\.typeName))
        return CodeComponentRegistry.shared.attachableEntries
            .filter { present.contains($0.name) == false }
            .sorted { $0.type.displayName < $1.type.displayName }
    }

    /// Whether the Inspector may remove the component. One that is part of its kind of entity
    /// stays until the entity is deleted. A slot whose type is not loaded can always go, so
    /// leftovers can be cleaned up.
    static func canRemove(_ typeName: String, from entityId: EntityID) -> Bool {
        guard let instance = CodeComponentSystem.shared.component(named: typeName, on: entityId) else { return true }
        return type(of: instance).attachment == .anyEntity
    }

    /// Whether a component on the entity built its mesh in code (`setGeneratedMesh`). The mesh
    /// is then the component's doing, and the Inspector does not remove it on its own.
    static func generatedMeshIsOwned(on entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents else { return false }
        return CodeComponentSystem.shared.components(on: entityId).contains { $0.ownsGeneratedMesh }
    }

    /// Adds a component by type name, as the Add Component menu does.
    static func add(_ typeName: String, to entityId: EntityID) {
        CodeComponentSystem.shared.add(typeName, to: entityId)
        EditorSceneDirtyState.shared.markDirty()
    }

    var body: some View {
        let slots = CodeComponentSystem.shared.slots(on: entityId)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(slots, id: \.typeName) { slot in
                slotView(slot)
                Divider()
            }
        }
        // A new library revision swaps every instance: rebuild the fields against the new ones.
        .id(controller.revision)
    }

    // MARK: One component

    @ViewBuilder
    private func slotView(_ slot: CodeComponentSlotInfo) -> some View {
        let instance = CodeComponentSystem.shared.component(named: slot.typeName, on: entityId)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(instance.map { type(of: $0).displayName } ?? slot.typeName)
                    .font(.headline)
                Image(systemName: "swift")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextTertiary)
                    .help("\(slot.typeName), written in the project's code or one of its plugins")
                Spacer()
                if Self.canRemove(slot.typeName, from: entityId) {
                    Button(action: { remove(slot.typeName) }) {
                        Image(systemName: "trash").foregroundColor(.editorError)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Remove \(slot.typeName) and its saved values")
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.editorTextTertiary)
                        .help("Part of this kind of entity. It cannot be added to other entities or removed from this one; delete the entity instead.")
                }
            }

            if let instance {
                ForEach(instance.untoldAttributes(), id: \.name) { entry in
                    AttributeField(entry: entry) { newValue in
                        write(newValue, to: entry, of: slot.typeName)
                    }
                }
                let actions = type(of: instance).actions
                if actions.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(actions, id: \.name) { action in
                            Button(action.name) {
                                CodeComponentSystem.shared.performAction(action.name, of: slot.typeName, on: entityId)
                                refreshView()
                            }
                            .font(.caption)
                        }
                    }
                }
            } else {
                Text("Not available in the loaded library. Its \(slot.payload.count) saved value\(slot.payload.count == 1 ? " is" : "s are") kept.")
                    .font(.caption)
                    .foregroundColor(.editorWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Edits

    private func remove(_ typeName: String) {
        guard Self.canRemove(typeName, from: entityId) else { return }
        CodeComponentSystem.shared.remove(typeName, from: entityId)
        EditorSceneDirtyState.shared.markDirty()
        refreshView()
    }

    private func write(_ newValue: UntoldAttributeValue, to entry: UntoldAttributeEntry, of typeName: String) {
        let oldValue = entry.attribute.attributeValue
        guard oldValue != newValue else { return }
        let entity = entityId
        let property = entry.name
        guard CodeComponentSystem.shared.setAttribute(property, of: typeName, on: entity, to: newValue) else { return }

        EditorSceneDirtyState.shared.markDirty()
        EditorUndoManager.shared.registerValueChange(
            name: "Change \(entry.displayLabel)",
            oldValue: oldValue,
            newValue: newValue
        ) { restored in
            CodeComponentSystem.shared.setAttribute(property, of: typeName, on: entity, to: restored)
            EditorSceneDirtyState.shared.markDirty()
            editorController?.refreshInspector()
        }
        refreshView()
    }
}

// MARK: - One attribute

/// The control for one attribute, chosen by its kind. Reads through the wrapper every time it
/// renders, and hands changes to `commit` as the JSON-shaped value the kit stores.
private struct AttributeField: View {
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

/// A slider that reports only when the drag ends, so one drag is one undo step.
private struct RangeSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float?
    @State private var dragValue: Float?

    var body: some View {
        let shown = Binding<Float>(
            get: { min(max(dragValue ?? value, range.lowerBound), range.upperBound) },
            set: { dragValue = $0 }
        )
        let editingChanged: (Bool) -> Void = { isEditing in
            if isEditing == false, let final = dragValue {
                value = final
                dragValue = nil
            }
        }
        Group {
            if let step, step > 0 {
                Slider(value: shown, in: range, step: step, onEditingChanged: editingChanged)
            } else {
                Slider(value: shown, in: range, onEditingChanged: editingChanged)
            }
        }
        .controlSize(.mini)
    }
}

/// A text field that reports on Return or when it loses focus, not on every keystroke.
private struct CommitTextField: View {
    let text: String
    let multiline: Bool
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if multiline {
                TextField("", text: $draft, axis: .vertical).lineLimit(2 ... 6)
            } else {
                TextField("", text: $draft)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .focused($isFocused)
        .onAppear { draft = text }
        .onChange(of: text) { _, newValue in
            if isFocused == false {
                draft = newValue
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused == false {
                onCommit(draft)
            }
        }
        .onSubmit { onCommit(draft) }
    }
}
