//
//  ComponentsPanelView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import SwiftUI
import UntoldComponentKit

/// The bottom panel's Components tab: what was built, what it defines, and what went wrong.
struct ComponentsPanelView: View {
    @Binding var searchQuery: String
    @ObservedObject private var controller = ComponentLibraryController.shared
    @State private var showsCompilerOutput = false
    @State private var creationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let message = failureMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.editorError)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.editorBackground)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            statusBadge
            Spacer()
            Toggle("Rebuild on save", isOn: $controller.rebuildOnSave)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .disabled(controller.layout == nil)
                .help("Recompile and reload when a Swift file in the components folder or a plugin's editor sources changes.")
            panelButton("Build", icon: "hammer") { controller.buildAndLoad() }
                .disabled(controller.layout == nil || controller.phase == .building)
            panelButton("Open in Xcode", icon: "chevron.left.forwardslash.chevron.right") { openProjectInXcode() }
                .disabled(controller.layout == nil)
            panelButton("Reveal", icon: "folder") { revealComponentsFolder() }
                .disabled(controller.layout?.componentsDirectoryExists != true)
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch controller.phase {
            case .noProject: return ("No project open", .editorTextTertiary)
            case .noSources: return ("No component sources", .editorTextSecondary)
            case .building: return ("Building…", .editorInfo)
            case .waitingForPlayToStop: return ("Built. Stopping play to load…", .editorWarning)
            case .loaded: return ("Revision r\(controller.revision) loaded", .editorSuccess)
            case .failed: return ("Build failed", .editorError)
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(.editorTextPrimary)
            if let seconds = controller.lastBuildSeconds, controller.phase != .building {
                Text(String(format: "%.2fs", seconds)).font(.system(size: 11)).foregroundColor(.editorTextTertiary)
            }
        }
    }

    private var failureMessage: String? {
        if let creationError {
            return creationError
        }
        if case let .failed(message) = controller.phase, controller.diagnostics.contains(where: { $0.severity == .error }) == false {
            return message
        }
        return nil
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let layout = controller.layout {
            if layout.componentsDirectoryExists == false, layout.units.isEmpty {
                emptyProject(layout)
            }
            ForEach(layout.problems, id: \.self) { problem in
                row(icon: "exclamationmark.triangle", color: .editorWarning, text: problem)
            }
            ForEach(controller.extensionIssues, id: \.self) { issue in
                row(icon: "exclamationmark.triangle", color: .editorWarning, text: issue)
            }
            diagnosticsList
            librariesList
            environment
        } else {
            Text("Open a project to compile and load its components.")
                .font(.system(size: 11))
                .foregroundColor(.editorTextSecondary)
        }
    }

    private func emptyProject(_ layout: ComponentProjectLayout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This project has no components folder yet.")
                .font(.system(size: 12))
                .foregroundColor(.editorTextPrimary)
            Text("Components are Swift classes in \(layout.componentsDirectory.lastPathComponent). The editor compiles them, shows their @UntoldAttribute properties in the Inspector, and reloads them when you save.")
                .font(.system(size: 11))
                .foregroundColor(.editorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            panelButton("Create component package", icon: "plus.circle") {
                do {
                    creationError = nil
                    try controller.createComponentPackage()
                } catch {
                    creationError = "The components folder could not be created: \(error.localizedDescription)"
                }
            }
        }
        .padding(10)
        .background(Color.editorFillSubtle)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var diagnosticsList: some View {
        let visible = controller.diagnostics.filter { $0.severity != .note && matches($0.message + $0.fileName) }
        if visible.isEmpty == false {
            sectionTitle("Compiler")
            ForEach(visible) { diagnostic in
                Button(action: { openInXcode(diagnostic) }) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(diagnostic.severity == .error ? .editorError : .editorWarning)
                            .font(.system(size: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(diagnostic.message)
                                .font(.system(size: 11))
                                .foregroundColor(.editorTextPrimary)
                                .multilineTextAlignment(.leading)
                            Text("\(diagnostic.fileName):\(diagnostic.line)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.editorTextTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Open in Xcode at line \(diagnostic.line)")
            }
        }
        if controller.rawOutput.isEmpty == false {
            DisclosureGroup("Compiler output", isExpanded: $showsCompilerOutput) {
                Text(controller.rawOutput)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.editorTextSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundColor(.editorTextSecondary)
        }
    }

    @ViewBuilder
    private var librariesList: some View {
        if controller.libraries.isEmpty == false {
            sectionTitle("Loaded")
            ForEach(controller.libraries) { library in
                VStack(alignment: .leading, spacing: 3) {
                    Text(library.moduleName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.editorTextPrimary)
                    ForEach(library.componentNames.filter(matches), id: \.self) { name in
                        row(icon: "cube", color: .editorAccent, text: "\(name)  ·  \(instanceCount(of: name)) in scene\(attachmentNote(of: name))")
                    }
                    ForEach(library.extensionNames.filter(matches), id: \.self) { name in
                        row(icon: "menubar.rectangle", color: .editorSecondaryAccent, text: "\(name)  ·  \(menuSummary(of: name))")
                    }
                    ForEach(library.templateNames.filter(matches), id: \.self) { name in
                        row(icon: "plus.square.dashed", color: .editorAccent, text: "\(name)  ·  \(templateSummary(of: name))")
                    }
                    if library.componentNames.isEmpty, library.extensionNames.isEmpty, library.templateNames.isEmpty {
                        row(icon: "shippingbox", color: .editorTextTertiary, text: "Runtime library; defines no components or extensions.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var environment: some View {
        if controller.layout != nil {
            sectionTitle("Environment")
            if let toolchain = controller.toolchain {
                row(icon: "swift", color: .editorTextTertiary, text: toolchain.compilerVersion)
            }
            if let sdk = controller.sdk {
                row(icon: "square.stack.3d.up", color: .editorTextTertiary, text: "\(sdk.isBundled ? "Bundled" : "Source build") SDK: \(sdk.providedModules.joined(separator: ", "))")
            } else {
                row(icon: "exclamationmark.triangle", color: .editorWarning, text: "No Component SDK found next to the editor.")
            }
            if controller.retiredBytes > 0 {
                let megabytes = Double(controller.retiredBytes) / 1_048_576
                row(icon: "memorychip", color: .editorTextTertiary, text: String(format: "%.1f MB held by earlier revisions until the editor quits.", megabytes))
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.editorTextTertiary)
            .padding(.top, 4)
    }

    private func row(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 11)).frame(width: 14)
            Text(text).font(.system(size: 11)).foregroundColor(.editorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func panelButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.editorFill)
            .foregroundColor(.editorTextPrimary)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func matches(_ text: String) -> Bool {
        searchQuery.isEmpty || text.localizedCaseInsensitiveContains(searchQuery)
    }

    private func instanceCount(of typeName: String) -> Int {
        CodeComponentSystem.shared.entities(withComponentNamed: typeName).count
    }

    /// Says why a component is missing from Add Component, for the ones that are.
    private func attachmentNote(of componentName: String) -> String {
        guard CodeComponentRegistry.shared.type(named: componentName)?.attachment == .entityKindOnly else { return "" }
        return "  ·  part of an entity kind, not in Add Component"
    }

    private func templateSummary(of templateName: String) -> String {
        guard let type = EntityTemplateRegistry.shared.type(named: templateName) else { return "not registered" }
        return "\"\(type.displayName)\" on the \(type.shelf.title) shelf"
    }

    private func menuSummary(of extensionName: String) -> String {
        let identifiers = EditorExtensionHost.shared.live.first { $0.name == extensionName }?.menuIdentifiers ?? []
        return identifiers.isEmpty ? "no menu items" : identifiers.joined(separator: ", ")
    }

    // MARK: Actions

    private func openInXcode(_ diagnostic: ComponentDiagnostic) {
        _ = ComponentCompiler.run("/usr/bin/xed", ["--line", String(diagnostic.line), diagnostic.file])
    }

    private func openProjectInXcode() {
        guard let layout = controller.layout else { return }
        let candidates = [
            layout.projectRoot.appendingPathComponent("\(layout.projectName).xcodeproj"),
            layout.projectRoot.appendingPathComponent("Package.swift"),
            layout.componentsDirectory,
        ]
        if let target = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(target)
        }
    }

    private func revealComponentsFolder() {
        guard let layout = controller.layout else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: layout.componentsDirectory.path)
    }
}
