# Untold Editor

The **Untold Editor** is the visual development environment for the [Untold Engine](https://github.com/untoldengine/UntoldEngine).  
It provides a complete toolkit for building games with scripting support, asset management, scene editing, and more.

## 🎮 For Game Developers

**Want to make games? Download [Untold Engine Studio](https://github.com/untoldengine/UntoldEditor/releases)** — a standalone app that includes everything you need:

- ✅ Complete visual editor
- ✅ Scripting system for game logic
- ✅ All engine features built-in
- ✅ No setup required — just download the DMG and start creating

👉 **[Download Untold Engine Studio](https://github.com/untoldengine/UntoldEditor/releases)**

## 🛠️ For Contributors

This repository is for developers who want to **contribute to the editor itself**. If you're looking to improve the editor, fix bugs, or add features, you're in the right place!

![UntoldEditorScreenshot](images/editorscreenshot.png)
---

## 📚 Understanding the Ecosystem

The Untold Engine project has three main components:

### For Game Developers:
- **[Untold Engine Studio](https://github.com/untoldengine/UntoldEditor/releases)** (Download)
  - Standalone app with everything included
  - Scripting, visual editor, asset management
  - No GitHub or build tools required
  - **Start here if you want to make games**

### For Engine/Editor Contributors:
- **[Untold Engine](https://github.com/untoldengine/UntoldEngine)** (Clone to contribute)
  - Core engine repository
  - Rendering, physics, ECS, animation systems
  - Clone this if you want to contribute to the engine core

- **[Untold Editor](https://github.com/untoldengine/UntoldEditor)** (This repo)
  - Editor interface and tooling
  - Clone this if you want to contribute to the editor

### Additional Resources:
- **Examples / Starter Projects:** [UntoldEngineExamples](https://github.com/untoldengine/UntoldEngineExamples)

---

## ✨ Features

- **Scene Graph** – Organize and visualize entity hierarchies  
- **Inspector** – View/edit components on selected entities  
- **Asset Browser** – Import, organize, and assign models, textures, materials  
- **Gizmo Tools** – Translate / rotate / scale entities directly in the viewport  
- **Edit / Play Modes** – Tweak, then simulate  
- **External Asset Folder** – Import assets at runtime without rebuilding the app  

---

## ✅ Requirements

- macOS 14+  
- Xcode 15+ (or Swift 5.10+ toolchain)  
- Metal-capable Mac  

---

## 📦 Development Setup

**Note:** If you just want to make games, download [Untold Engine Studio](https://github.com/untoldengine/UntoldEditor/releases) instead.

For editor development, clone this repository:

```bash
git clone https://github.com/untoldengine/UntoldEditor.git
cd UntoldEditor
```

The Editor is a Swift Package with an executable target named UntoldEditor.
It declares a dependency on the Untold Engine package; Xcode/SwiftPM will resolve it automatically.

### Open in Xcode (recommended)

1. Open Xcode → File ▸ Open → select the Package.swift in this repo
2. Xcode will create a workspace view for the package
3. Choose the UntoldEditor scheme → Run

### Build & run via CLI

```bash
swift build
swift run UntoldEditor
```

### Pinning the Engine Dependency

By default, this repo pins Untold Engine to a released version.
If you want the latest engine changes:

#### Option A — Xcode UI
- In the project navigator: Package Dependencies → UntoldEngine
- Set Dependency Rule to Branch and type develop

#### Option B — Edit Package.swift

```swift
.dependencies = [
    .package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "develop")
]
```

Then reload packages:

```bash
xcodebuild -resolvePackageDependencies
# or in Xcode: File ▸ Packages ▸ Resolve Package Versions
```

## 🕹 Using the Editor

1. **Create / Open a Project** – Use the start screen or File menu  
2. **Set Asset Folder** – Choose an **external** directory for your project’s assets  
3. **Import Assets** – Drag files in or use the Asset Browser “+”  
4. **Build Your Scene** – Create entities, add components, use gizmos to position  
5. **Play Mode** – Toggle to simulate and validate behavior  
6. **Save / Load** – Save project and scene files; reopen later to continue  

> 💡 Why an *external* asset folder?  
> It enables **runtime importing** and iteration without copying everything into the app bundle.

---

## 🧪 Troubleshooting

- **Editor scheme not visible**  
  - Make sure you opened the **package** (its `Package.swift`) or the generated workspace, not a single source file  
  - **Product ▸ Scheme ▸ Manage Schemes…** → ensure *Shared* is checked for `UntoldEditor`  
  - **File ▸ Packages ▸ Reset Package Caches** if dependencies look stale  

- **Can’t switch to `develop`**  
  - If the Dependency Rule control is disabled, edit `Package.swift` (see “Pinning the Engine Dependency”) and re-resolve packages  

---

## 🤝 Contributing

We welcome PRs!  

1. Fork the repository  
2. Create a feature branch (`git checkout -b feature/my-feature`)  
3. Commit your changes  
4. Push the branch and open a Pull Request  

See **CONTRIBUTING.md** and **CODE_OF_CONDUCT.md** (coming soon).

---

## 📜 License

Licensed under **GNU LGPL v3.0**.  
See [LICENSE](LICENSE) for details.

