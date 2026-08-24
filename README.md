# Untold Editor

The **Untold Editor** is a **Scene Composition tool** for the [Untold Engine](https://github.com/untoldengine/UntoldEngine).  
It is designed to help you **prepare assets, compose scenes, and generate scene files** that are later used inside your game.

> ⚠️ The Editor is **not a full game development environment**.  
> It is a **visual companion tool** to the Untold Engine.

---

## 🎮 For Game Developers

If you want to build a game with the Untold Engine, you will use **both**:

1. **Untold Engine (required)** → for actual game development  
2. **Untold Editor Studio (optional but recommended)** → for scene composition. [Download Untold Engine Studio](https://github.com/untoldengine/UntoldEditor/releases)**

### What the Editor is for:
- Converting `.usdz` → `.untold` runtime assets  
- Visually composing scenes  
- Saving scenes as `.untoldscene` files  
- Previewing assets before using them in code  

### What the Editor is NOT for:
- Writing gameplay logic  
- Binding animations or scripts  
- Configuring physics or runtime systems  
- Replacing the engine  

👉 **You still need to clone the engine to build your game:**
- https://github.com/untoldengine/UntoldEngine

---

## 🚀 Quick Preview (No Setup Required)

If you just want to explore or preview assets, you can download the standalone app:

👉 **[Download Untold Engine Studio](https://github.com/untoldengine/UntoldEditor/releases)**

This lets you:
- Import assets
- Compose scenes
- Preview rendering

But:
> ⚠️ You cannot build a full game using only the Editor.

---

## 🛠️ For Contributors

This repository is for developers who want to **contribute to the editor itself**.

![UntoldEditorScreenshot](images/editorscreenshot.png)

---

## ✨ Features

- **Scene Composition Workflow** – Place and organize entities  
- **Asset Conversion Pipeline** – Convert `.usdz` → `.untold`  
- **Scene Files** – Save/load `.untoldscene`  
- **Asset Browser** – Browse runtime assets  
- **Stream Models** – Work with tiled streaming scenes  
- **Gizmo Tools** – Transform entities in viewport  
- **Quick Preview** – Inspect assets visually  
- **Read-Only Rendering Inspection** – Debug rendering state  

---

## 🧠 Editor Scope (Important)

The Untold Editor is intentionally limited to:

### ✅ Supported
- Scene layout  
- Asset placement  
- Transform editing  
- Lighting & environment setup  
- Scene serialization  

### ❌ Not Supported
- Animation binding  
- Script attachment  
- Physics configuration  
- Gameplay logic  
- Material authoring  

> These systems are handled in **engine code**, not the editor.

---

## ✅ Requirements

- macOS 14+  
- Xcode 15+ (or Swift 5.10+)  
- Metal-capable Mac  

---

## 📦 Development Setup

> If your goal is game development, clone the engine first.

Clone the editor:

```bash
git clone https://github.com/untoldengine/UntoldEditor.git
cd UntoldEditor
```

The Editor is a Swift Package with an executable target named UntoldEditor.
It declares a dependency on the Untold Engine package; Xcode/SwiftPM will resolve it automatically.

### Build & run via CLI

```bash
swift build
swift run UntoldEditor
```

### Open in Xcode (recommended)

1. Open Xcode → File ▸ Open → select the Package.swift in this repo
2. Xcode will create a workspace view for the package
3. Choose the UntoldEditor scheme → Run

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
3. **Import Assets** – Use the Asset Browser to import `.untold`, stream-model manifests, HDRs, materials, animations, and Gaussian assets  
4. **Convert USD Assets When Needed** – If you pick a USD asset, export it to `.untold` first through the importer flow  
5. **Compose the Scene** – Select root entities, place them with gizmos, and adjust scene-visible properties in the Inspector  
6. **Save / Load Scenes** – Save scenes as `.untoldscene`; reopen later to continue  

> 💡 Why an *external* asset folder?  
> It enables **runtime importing** and iteration without copying everything into the app bundle.

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

Licensed under **Mozilla Public License 2.0**.  
See [LICENSE](LICENSE) for details.
