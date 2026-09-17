//
//  ScenePluginInspectorView.swift
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

/// The component plugins the entity carries, shown in the Inspector the way the engine's
/// components are: one block each, a headline with a remove button, then a field for every
/// `@UntoldAttribute` and a button for every action. They are added from the Inspector's one
/// Add Component menu (`AddComponentMenu`), alongside the engine's.
///
/// Drawn by the Inspector directly rather than registered as component options, because the
/// set of types changes whenever a library loads, and so scene-composition mode keeps them.
struct ScenePluginInspectorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @ObservedObject private var controller = ComponentLibraryController.shared

    /// Whether the Inspector has any component plugin to draw for `entityId`.
    static func isAvailable(for entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return false }
        return ScenePluginSystem.shared.slots(on: entityId).isEmpty == false
    }

    /// The loaded component plugins `entityId` does not carry yet, for the Add Component menu.
    /// Every one of them: a component is something any entity can have. What belongs to one
    /// kind of entity only is a property of its `EntityPlugin`, and is never in this list.
    static func addableTypes(for entityId: EntityID) -> [ComponentPluginRegistry.Entry] {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return [] }
        let present = Set(ScenePluginSystem.shared.slots(on: entityId).map(\.typeName))
        return ComponentPluginRegistry.shared.entries
            .filter { present.contains($0.name) == false }
            .sorted { $0.type.displayName < $1.type.displayName }
    }

    /// Adds a component by type name, as the Add Component menu does.
    static func add(_ typeName: String, to entityId: EntityID) {
        ScenePluginSystem.shared.add(typeName, to: entityId)
        EditorSceneDirtyState.shared.markDirty()
    }

    var body: some View {
        let slots = ScenePluginSystem.shared.slots(on: entityId)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(slots, id: \.typeName) { slot in
                PluginBlock(
                    entityId: entityId,
                    slot: slot,
                    instance: ScenePluginSystem.shared.component(named: slot.typeName, on: entityId),
                    title: nil,
                    badge: "swift",
                    badgeHelp: "\(slot.typeName), a component written in the project's code or one of its plugins",
                    removeHelp: "Remove \(slot.typeName) and its saved values",
                    onRemove: {
                        ScenePluginSystem.shared.remove(slot.typeName, from: entityId)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    },
                    refreshView: refreshView
                )
                Divider()
            }
        }
        // A new library revision swaps every instance: rebuild the fields against the new ones.
        .id(controller.revision)
    }
}

/// The entity's own block, when it is a kind of entity written in code (`EntityPlugin`): its
/// kind as the headline and a field for each of its properties. It comes before the
/// components because it is the entity, not something added to it, so it has no remove
/// button: deleting the entity is how it goes. The one exception is a kind whose type is no
/// longer loaded, which can be cleared so the entity can be kept as a plain one.
struct EntityPluginInspectorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @ObservedObject private var controller = ComponentLibraryController.shared

    static func isAvailable(for entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return false }
        return ScenePluginSystem.shared.entitySlot(on: entityId) != nil
    }

    /// Whether the entity's mesh was built by its own plugin (`setGeneratedMesh`). It is then
    /// part of the entity, and the Inspector does not remove it on its own.
    static func generatedMeshIsOwned(on entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents else { return false }
        return ScenePluginSystem.shared.entityPlugin(on: entityId)?.ownsGeneratedMesh ?? false
    }

    /// The headline and icon for the entity's kind: the loaded type's, or the saved type name
    /// when the library that defined it is not loaded.
    static func kind(of slot: ScenePluginSlotInfo) -> (title: String, systemImage: String) {
        guard let type = EntityPluginRegistry.shared.type(named: slot.typeName) else {
            return (slot.typeName, "questionmark.square.dashed")
        }
        return (type.displayName, type.systemImage)
    }

    var body: some View {
        if let slot = ScenePluginSystem.shared.entitySlot(on: entityId) {
            let kind = Self.kind(of: slot)
            VStack(alignment: .leading, spacing: 8) {
                PluginBlock(
                    entityId: entityId,
                    slot: slot,
                    instance: ScenePluginSystem.shared.entityPlugin(on: entityId),
                    title: kind.title,
                    badge: kind.systemImage,
                    badgeHelp: "This entity is a \(kind.title) (\(slot.typeName)), a kind of entity written in the project's code or one of its plugins. These are its own properties.",
                    removeHelp: "Forget that this entity was a \(slot.typeName), and its saved values. The entity stays.",
                    onRemove: slot.isBound ? nil : {
                        ScenePluginSystem.shared.removeEntityPlugin(from: entityId)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    },
                    refreshView: refreshView
                )
                Divider()
            }
            .id(controller.revision)
        }
    }
}

// MARK: - One plugin

/// One block of fields: the headline, then a field per attribute and a button per action, or
/// a note when the type is not loaded. Shared by the entity's own block and its components.
private struct PluginBlock: View {
    let entityId: EntityID
    let slot: ScenePluginSlotInfo
    let instance: ScenePlugin?
    /// The headline; `nil` takes the plugin's display name.
    let title: String?
    let badge: String
    let badgeHelp: String
    let removeHelp: String
    /// `nil` when the block cannot be removed.
    let onRemove: (() -> Void)?
    let refreshView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title ?? instance.map { type(of: $0).displayName } ?? slot.typeName)
                    .font(.headline)
                Image(systemName: badge)
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextTertiary)
                    .help(badgeHelp)
                Spacer()
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash").foregroundColor(.editorError)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help(removeHelp)
                }
            }

            if let instance {
                ForEach(instance.untoldAttributes(), id: \.name) { entry in
                    AttributeField(entry: entry) { newValue in
                        write(newValue, to: entry)
                    }
                }
                let actions = type(of: instance).actions
                if actions.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(actions, id: \.name) { action in
                            Button(action.name) {
                                ScenePluginSystem.shared.performAction(action.name, of: slot.typeName, on: entityId)
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

    private func write(_ newValue: UntoldAttributeValue, to entry: UntoldAttributeEntry) {
        let oldValue = entry.attribute.attributeValue
        guard oldValue != newValue else { return }
        let entity = entityId
        let typeName = slot.typeName
        let property = entry.name
        guard ScenePluginSystem.shared.setAttribute(property, of: typeName, on: entity, to: newValue) else { return }

        EditorSceneDirtyState.shared.markDirty()
        EditorUndoManager.shared.registerValueChange(
            name: "Change \(entry.displayLabel)",
            oldValue: oldValue,
            newValue: newValue
        ) { restored in
            ScenePluginSystem.shared.setAttribute(property, of: typeName, on: entity, to: restored)
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
