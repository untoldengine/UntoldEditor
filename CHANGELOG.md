# Changelog
## v0.20.0 - 2026-09-20
### 🐞 Fixes
- [Patch] Open a project folder that has a project.yml but no generated Xcode project (3de9f54…)
- [Patch] Cover entity templates in the Component SDK packaging check (2ff8b46…)
- [Patch] Pick handles by projecting them to the screen, with either mouse button (ea5aab0…)
- [Patch] Name a plugin package's editor-side library after its folder (eb601d9…)
- [Patch] Label the cook sheet's binary sizes GiB and MiB (7e4743f…)
### 🚀 Features
- [Feature] Code Components: compile, load and reload project code in the editor (ea127f4…)
- [Feature] Wire Code Components into the editor, and open a project at launch (3b37da7…)
- [Feature] Package the Component SDK in the app bundle, and verify it (cb92463…)
- [Feature] New projects get code components, pinned to the editor's engine (980bb28…)
- [Feature] One Add Component menu, and entity kinds from loaded code (2b824ff…)
- [Feature] Keep a kind's own components out of Add Component, and locked to their entity (4e080fe…)
- [Feature] Entity plugins in the editor: own properties, geometry and editor representation (1f926ea…)
- [Feature] Name the plugins folder and plugin packages apart in the editor (dfe6add…)
- [Feature] Move a kind of entity's control points with the gizmo (cdfe8ce…)
- [Feature] Gaussian capture testing and render-fidelity switches in the editor (1e85e08…)
## v0.19.1 - 2026-09-16
### 🐞 Fixes
- [Patch] Only route canvas input to the 3D view when it is frontmost (53af52e…)
- [Patch] Show the project name in the window title (cc6e1b9…)
- [Patch] Point next-version.sh at the editorVersion constant (efa706c…)
- [Patch] Drop redundant explicit self in the left-mouse-down monitor (5bbb2f3…)
- [Patch] Use an @main entry point so Xcode 26 builds the editor package (36d0667…)
- [Patch] Import copies report progress, can be cancelled, and never cook by themselves (6691b3a…)
- [Patch] Stop reading @State isPlaying inside EditorView.init (6edaa1c…)
- [Patch] Point next-version.sh at UntoldEditorApp.swift (1935ee9…)
- [Patch] Pin editor to engine develop branch (83bda0e…)
- [Patch] Added Explorer view (07d9fd0…)
- [Patch] Load Gaussians through the editor (691fc65…)
- [Patch] Carry the asset drag payload as public.json, not a custom UTType (980d391…)
- [Patch] Place dropped Gaussians through the editor loader and accept package folders (d97e1e6…)
- [Patch] Move lights and primitives to asset browser (e9917f1…)
- [Patch] Serialized gaussians (7197810…)
- [Patch] Gaussian cook sheet needs .ply sources (9effde6…)
- [Patch] Gaussian cook sheet: the budget test reads the engine caps (b5d8b76…)
- [Patch] Update SSAO parameters (161b111…)
- [Patch] Updated gaussian api name change (64ac020…)
- [Patch] Enable engine stats in release app bundle build (3cedd8f…)
- [Patch] Bundle UntoldEngine's SPM resource bundle into the app (6ff8dd9…)
- [Patch] Add --editor-patch to next-version.sh for editor-only releases (03b9912…)
- [Patch] updating release 0.19.0 changelogs (209068d…)
- [Patch] Fix resource lookup and bundle flattening for signed app builds (5180394…)
- [Patch] Warn upfront when XcodeGen is missing in Create Project (d14501d…)
- [Patch] Fixed changelog and version number (bd9baa2…)
### 🚀 Features
- [Feature] Cook Gaussian .ply to .untoldgs and load baked splats (2b99b3d…)
- [Feature] Add Tasks panel to the bottom dock (dde2b13…)
- [Feature] Import on double-click and cook imported Gaussian .ply as a task (63e3608…)
- [Feature] Import copies the source into the project as a task before converting it (33711a6…)
- [Feature] Render the frozen viewport frame at screen size during resizes (d397f02…)
- [Feature] Cook .blend/USD imports to .untold(pack) on demand (4d8e1dd…)
- [Feature] Route canvas input by hit test and add Blender-style camera navigation (91983c7…)
- [Feature] Clear the selection with a left click on empty viewport space (ee36784…)
- [Feature] Navigate with the scroll wheel in the Blender style: orbit, ⇧ pan, ⌘ zoom (8ea2ef9…)
- [Feature] Recenter toggle on the Gaussian cook sheet (77d358c…)
- [Feature] Choose the capture's up axis in the Gaussian cook sheet (a4e6dac…)
- [Feature] Splat budget and source count in the Gaussian cook sheet (c997c83…)
- [Feature] Drag models and Gaussian splats from the asset browser into the scene (2f2811b…)
- [Feature] Add View > Splat Debug switches for the Gaussian pipeline (6e6022f…)
- [Feature] Cook .spz Gaussian captures to .untoldgs (8d91ff9…)
- [Feature] Support safe scene switching: dirty tracking, save prompts, and scene management (54c54a5…)

## v0.19.0.1 - 2026-09-13
### 🐞 Fixes
- [Patch] Only route canvas input to the 3D view when it is frontmost (53af52e…)
- [Patch] Show the project name in the window title (cc6e1b9…)
- [Patch] Point next-version.sh at the editorVersion constant (efa706c…)
- [Patch] Drop redundant explicit self in the left-mouse-down monitor (5bbb2f3…)
- [Patch] Use an @main entry point so Xcode 26 builds the editor package (36d0667…)
- [Patch] Import copies report progress, can be cancelled, and never cook by themselves (6691b3a…)
- [Patch] Stop reading @State isPlaying inside EditorView.init (6edaa1c…)
- [Patch] Point next-version.sh at UntoldEditorApp.swift (1935ee9…)
- [Patch] Pin editor to engine develop branch (83bda0e…)
- [Patch] Added Explorer view (07d9fd0…)
- [Patch] Load Gaussians through the editor (691fc65…)
- [Patch] Carry the asset drag payload as public.json, not a custom UTType (980d391…)
- [Patch] Place dropped Gaussians through the editor loader and accept package folders (d97e1e6…)
- [Patch] Move lights and primitives to asset browser (e9917f1…)
- [Patch] Serialized gaussians (7197810…)
- [Patch] Gaussian cook sheet needs .ply sources (9effde6…)
- [Patch] Gaussian cook sheet: the budget test reads the engine caps (b5d8b76…)
- [Patch] Update SSAO parameters (161b111…)
- [Patch] Updated gaussian api name change (64ac020…)
- [Patch] Enable engine stats in release app bundle build (3cedd8f…)
- [Patch] Bundle UntoldEngine's SPM resource bundle into the app (6ff8dd9…)
- [Patch] Add --editor-patch to next-version.sh for editor-only releases (03b9912…)
- [Patch] updating release 0.19.0 changelogs (209068d…)
### 🚀 Features
- [Feature] Cook Gaussian .ply to .untoldgs and load baked splats (2b99b3d…)
- [Feature] Add Tasks panel to the bottom dock (dde2b13…)
- [Feature] Import on double-click and cook imported Gaussian .ply as a task (63e3608…)
- [Feature] Import copies the source into the project as a task before converting it (33711a6…)
- [Feature] Render the frozen viewport frame at screen size during resizes (d397f02…)
- [Feature] Cook .blend/USD imports to .untold(pack) on demand (4d8e1dd…)
- [Feature] Route canvas input by hit test and add Blender-style camera navigation (91983c7…)
- [Feature] Clear the selection with a left click on empty viewport space (ee36784…)
- [Feature] Navigate with the scroll wheel in the Blender style: orbit, ⇧ pan, ⌘ zoom (8ea2ef9…)
- [Feature] Recenter toggle on the Gaussian cook sheet (77d358c…)
- [Feature] Choose the capture's up axis in the Gaussian cook sheet (a4e6dac…)
- [Feature] Splat budget and source count in the Gaussian cook sheet (c997c83…)
- [Feature] Drag models and Gaussian splats from the asset browser into the scene (2f2811b…)
- [Feature] Add View > Splat Debug switches for the Gaussian pipeline (6e6022f…)
- [Feature] Cook .spz Gaussian captures to .untoldgs (8d91ff9…)
- [Feature] Support safe scene switching: dirty tracking, save prompts, and scene management (54c54a5…)
## v0.19.0 - 2026-09-13
## v0.18.1 - 2026-09-05
### 🐞 Fixes
- [Patch] Added import tooltip (040429b…)
- [Patch] fixed light direction - Gizmo tool (77419dc…)
- [Patch] Added Tonemap selection in Effects View (51cff57…)
- [Patch] Added LUT selection (7a14edc…)
- [Patch] serialized fx and lut data (dd22201…)
- [Patch] Fix gizmo system (34f9385…)
- [Patch] Enable sky rendering (3b117f6…)
## v0.18.0 - 2026-08-30
### 🐞 Fixes
- [Patch]Restore scene-authored loading in Environment panel (bac0530…)
- [Patch] Fixed directional light rotation - gizmo (81b1a0d…)
- [Patch] Fixed parent-child selection in viewport (41df956…)
- [Patch] Fixed the active directional light (1c17fdd…)
- [Patch] Re-added Import textures features (ea5ed67…)
- [Patch] Allow exporting blender files (bd0308e…)
- [Patch] Show material texture details on inspector hover (37c4b13…)
- [Patch] Coalesce gizmo drag updates during viewport transforms (6ea624c…)
- [Patch] Removed TaskBar View test (75afd7e…)
### 🚀 Features
- [Feature] Add Height/POM material channel to Inspector (d460c63…)
## v0.16.0 - 2026-08-12
### 🐞 Fixes
- [Patch] fix area light mesh culling (9122f78…)
- [Patch] Added shadow cast to point lights (390e1f4…)
- [Patch] Align light inspector controls and debug meshes with Blender lighting (b439816…)
- [Patch] Allow .exr import alongside .hdr in Asset Browser's HDR category (7ac9415…)
- [Patch] Enable the color lut in the editor (d519be9…)
## v0.14.2 - 2026-07-16
## v0.14.0 - 2026-07-09
### 🐞 Fixes
- [Patch] added option to load authored scene data (4558dec…)
- [Patch] Fixed area light direction (e05a8d4…)
- [Patch] Added an Explore Window (86e53f7…)
- [Patch] Added Try your scene steps (03ee7d5…)
- [Patch] updated editor render graph (f47e3b7…)
- [Patch] Migrate editor rendering to the engine's RenderExtension system (31ee159…)
## v0.13.0 - 2026-06-03
### 🐞 Fixes
- [Patch] Made user experience improvements (adf6d2b…)
- [Patch] Implemented collapsible children in the Scene Graph (555b101…)
- [Patch] Updated editor to TBDR pass (7fb8547…)
- [Patch] Added SSAO parameters to Effects View (d8bb848…)
## v0.12.14 - 2026-05-22
### 🐞 Fixes
- [Patch] Migrate editor ray picking to ScenePickingSystem (c059ced…)
- [Patch] Added FPS Stats (4e80c55…)
- [Patch] Implemented undo redo feature (9ddf6e3…)
- [Patch] Fix ci build failure (9c7b8e4…)
- [Patch] add support to assetbrowser to import remote asset (5438b79…)
- [Patch] Fix anti-aliasing failure (8ac8c8b…)
- [Patch] Fix anti-aliasing failure (b3eb245…)
- [Patch] Fixed the quick load preview (36825d8…)
- [Patch] fixed rotation gizmo (9d23a4a…)
- [Patch] Modify quick preview (59f1ae2…)
- [Patch] Fixed gizmo parent-child selection (77432da…)
- [Patch] Fixed the direction handler (a19d897…)
- [Patch] Remove debug view from editor (5a592ef…)
- [Patch] Removed export tools (4e279db…)
## v0.12.10 - 2026-04-29
### 🐞 Fixes
- [Patch] Fixed bundle script to include required helper scripts (8bec369…)
## v0.12.8 - 2026-04-28
### 🐞 Fixes
- [Patch] Updated script to follow engine dependency tag version (761dc47…)
- [Patch] make app bundle script copy 'usdz-untold' script (0df0207…)
- [Patch] added support to export tile scenes (943c3e8…)
- [Patch] Added support for astc and lz4 optimization. (8a403a3…)
- [Patch] Added post fx preset to Effects View (7beb4ff…)
## v0.12.8 - 2026-04-28
### 🐞 Fixes
- [Patch] Updated script to follow engine dependency tag version (761dc47…)
- [Patch] make app bundle script copy 'usdz-untold' script (0df0207…)
- [Patch] added support to export tile scenes (943c3e8…)
- [Patch] Added support for astc and lz4 optimization. (8a403a3…)
- [Patch] Added post fx preset to Effects View (7beb4ff…)
## v0.12.7 - 2026-04-25
### 🐞 Fixes
- [Patch] AssetBrowserView now accepts untold files (f972fa2…)
- [Patch] Organized asset browser view to show folders (330ffe9…)
- [Patch] Added exporter to editor (14e06b9…)
- [Patch] added stream assets to Asset Browser view (caf4b68…)
- [Patch] editor creates a scene as a untoldscene format (c5b75ba…)
- [Patch] Clean up the editor (f88f97b…)
- [Patch] Fix text field with focus during startup (3cc9eec…)
- [Patch] Added the cube, plane and sphere to scenegraph (981c6f5…)
- [Patch] updated buffers to reflect engine changes (490285d…)
- [Patch] Fixed the selection manager (381f1b1…)
- [Patch] Made render components editable (3b47600…)
- [Patch] Updated package dependency (0f99577…)
## v0.10.8 - 2026-02-23
### 🐞 Fixes
- [Patch] fixed transform for gizmo (d708c98…)
- [Patch] Fixed edit mode graph (06251e0…)
- [Patch] Replaced usdz gizmo with procedural generated gizmo (b258e58…)
- [Patch] Fixed gizmo placement (5fbbbc2…)
- [Patch] Fixed raycasting with cpu version (7fc5ecc…)
- [Patch] Added transparency support (3db516c…)
## v0.10.0 - 2026-02-10
### 🐞 Fixes
- [Feature] Added geometry streaming support (d78a58a…)
- [Patch] Fixed flickering issue (16469ab…)
- [Patch] Fixed input fields to go un-focus (6e533e1…)
## v0.9.0 - 2026-02-04
### 🚀 Features
- [Feature] Adde LOD support (319502a…)
- [Feature] Added Static Batching support (f70016f…)
## v0.8.2 - 2026-02-01
### 🐞 Fixes
- [Patch] added a dropdown menu to import button (645a6e7…)
- [Patch] Added parenting to scenegraph (7dd0179…)
- [Patch] Added option to select child entity by using shift,right mouse (c5210ee…)
- [Patch] Added quick preview (c6c7f40…)
- [Patch] Fixed issue of new project copying data over from previous one (452fa93…)
## v0.8.1 - 2026-01-26
## v0.8.0 - 2026-01-19
### 🐞 Fixes
- [Patch] Added editor version label (a07b4b2…)
- [Patch] added button for multi-platform option (259f3ee…)
