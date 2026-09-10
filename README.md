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
It declares a dependency on the Untold Engine package (and on UntoldGaussianTwins, for the splat twin preview); Xcode/SwiftPM will resolve them automatically.

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

### Splat twins

A mesh placed from a `.untold` asset can stand in for a captured Gaussian splat up close. Select the mesh (the asset root of a single-node asset, or a mesh node of a multi-node one) and use the Inspector's **Splat Twin** section:

- **Assign Selected** links the `.untoldgs` selected in the Asset Browser's Gaussians folder; **Choose…** picks one from disk; **Remove** unlinks it. Sources must be cooked first (`Cook to .untoldgs…`).
- **Swap Distance** (m, 0 = swap at any distance), **Occluder Shrink** (m) and **Exposure Offset** (EV) apply live and are saved shortly after the last edit; every change is undoable (⌘Z).

#### Aligning a twin

A capture rarely shares its mesh's frame (scanner origin, a turned or slightly mis-scaled scan), so the section's **Alignment** group places the splat inside the mesh without re-cooking: **Offset X/Y/Z** (m, in the entity's local space), **Yaw** (°, about the entity's +Y) and **Scale** (uniform, 0.01–100). The values apply live to the previewed twin, are saved shortly after the last edit and undo as one step each; **Reset** puts the splat back where the payload has it (the record then stores no alignment, like a link never aligned). The status line under the fields shows the current alignment. Turn on **Align Mode** while tuning: the twin swaps in at any distance with the mesh still drawing and the occluder shells off, so mesh and splat are both visible at once — the splat simply fades in over the untouched mesh, and fades out again when the mode ends, without the mesh ever dithering. It is session state — never saved — and ends when it is turned off, the section leaves the screen (another selection, the inspector hidden), the scene changes, View ▸ Preview Splat Twins is turned off or the link is removed (an undo included), restoring the shells and the link's own swap distance. Every placement of the record is aligned together, including one whose mesh finishes loading while the mode is on (it joins at the next edit). Assigning a different capture keeps the stored alignment — a re-cook of the same scan shares its frame — and the status line says so; press Reset if the new capture has its own.

The alignment is stored in the link's `gaussianAsset` record (the `alignment` flag plus the offset, yaw and scale fields; `untoldengine gaussian-link --align-translate x,y,z --align-yaw-degrees d --align-scale s` sets the same thing from the command line, `--clear-alignment` removes it; a record edited that way while the editor is open is picked up, viewport twin included, the next time the entity is selected). The engine applies it at runtime as `GaussianComponent.splatToEntity` — the splat is drawn with the entity's transform times the alignment — so every app that loads the asset gets the aligned twin; the cook transform baked into the `.untoldgs` header is untouched.

The link is stored in the `.untold` file itself — its `gaussianAsset` record, written through the engine's `UntoldAssetPatcher` — not in the scene. Any app that loads the asset and runs `GaussianTwinSystem` (package [UntoldGaussianTwins](https://github.com/miolabs/UntoldGaussianTwins)) gets the swap; the payload path is stored relative to the `.untold` file (`../../Gaussians/chair.untoldgs` from `Models/Chair/`), so the `.untoldgs` can live in the project's Gaussians folder as long as the two folders move together; only a payload on another volume is stored by file name and must then sit next to the `.untold` at runtime (the status line warns). **View ▸ Preview Splat Twins** (on by default) runs the same system in the editor viewport so the swap can be checked as the scene camera approaches.

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
