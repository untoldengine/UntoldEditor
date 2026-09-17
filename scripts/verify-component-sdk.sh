#!/bin/bash
#
# verify-component-sdk.sh <path to the .app>
#
# Checks that a packaged editor can load code components: it compiles a fixture against the
# bundle's Component SDK exactly as the editor does (nothing of the engine linked), then makes
# sure every engine and kit symbol the fixture needs is exported by the editor executable.
#
# Why this exists: a subclass compiled into another image copies its base class's dispatch
# table, entries for internal members included. Debug builds export internal symbols, release
# builds hide them, so a member of CodeComponent or EditorExtension that is neither public nor
# final breaks loading in the packaged app only. This catches it at packaging time instead of
# on a user's machine.

set -euo pipefail

APP="${1:?usage: verify-component-sdk.sh <path to the .app>}"
SDK="$APP/Contents/Resources/ComponentSDK"
EXECUTABLE="$APP/Contents/MacOS/UntoldEditor"

for required in "$SDK/sdk.json" "$SDK/Modules" "$SDK/CShaderTypes/module.modulemap" "$EXECUTABLE"; do
    if [ ! -e "$required" ]; then
        echo "❌ Component SDK check: missing $required"
        exit 1
    fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/Fixture.swift" << 'SWIFT'
import simd
import UntoldComponentKit
import UntoldEngine

final class FixtureComponent: CodeComponent {
    enum Mode: String, CaseIterable { case one, two }

    @UntoldAttribute("Speed", range: 0 ... 10, step: 0.5) var speed: Float = 1
    @UntoldAttribute var count: Int = 1
    @UntoldAttribute var flag = false
    @UntoldAttribute var name: String = ""
    @UntoldAttribute(.multiline) var notes: String = ""
    @UntoldAttribute var offset: SIMD3<Float> = .zero
    @UntoldAttribute(.color) var tint: SIMD4<Float> = .one
    @UntoldAttribute var target = EntityRef()
    @UntoldAttribute var asset = AssetRef(category: .models)
    @UntoldAttribute var mode: Mode = .one

    override class var displayName: String { "Fixture" }
    override class var actions: [ComponentAction] {
        [ComponentAction("Poke") { ($0 as? FixtureComponent)?.count += 1 }]
    }

    override func onAttach() { _ = transform; _ = isAttached }
    override func onStart() { _ = target.resolve(); _ = asset.resolveURL() }
    override func onUpdate(deltaTime: Float) { speed += deltaTime; setEntityName(entityId: entity, name: name) }
    override func onFixedUpdate(deltaTime _: Float) {}
    override func onStop() {}
    override func onDetach() {}
    override func onEditorChanged(property _: String) {}

    func neighbours() -> [EntityID] {
        _ = CodeComponentRegistry.component(FixtureComponent.self, on: entity)
        _ = CodeComponentSystem.shared.components(on: entity)
        return CodeComponentRegistry.entities(with: FixtureComponent.self)
    }
}

class FixtureBase: CodeComponent {
    @UntoldAttribute var inherited: Float = 0
}

final class FixtureDerived: FixtureBase {
    @UntoldAttribute var own: Float = 0
}

final class FixtureExtension: EditorExtension {
    enum Level: String, CaseIterable, UntoldMenuTitled {
        case low, high
        var menuTitle: String { rawValue.capitalized }
    }

    @UntoldMenu(.view, "Fixture Toggle", key: "", tooltip: "tip", persist: true, enabled: { true }) var toggle = true
    @UntoldMenu(.debug, "Fixture/Level") var level: Level = .low
    @UntoldMenu(.tools, "Fixture/Run") var run = UntoldMenuAction {}
    @UntoldMenu(.file, "Fixture/Run With Owner") var runWithOwner = UntoldMenuAction { (_: EditorExtension) in }

    override class var displayName: String { "Fixture" }
    override func onLoad() {}
    override func onUnload() {}
    override func onSceneReset() {}
    override func onPlayModeChanged(_: Bool) {}
    override func onEditorUpdate(deltaTime _: Float) {}
    override func menuWillOpen() {}
    override func menuDidChange(_: UntoldMenuDomain, _: String) {}
}
SWIFT

TARGET="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["target"])' "$SDK/sdk.json")"

if ! xcrun swiftc -emit-library -parse-as-library \
    -o "$WORK/Fixture.dylib" -module-name ComponentSDKFixture \
    -swift-version 5 -Onone -D UNTOLD_EDITOR \
    -target "$TARGET" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -I "$SDK/Modules" -Xcc "-fmodule-map-file=$SDK/CShaderTypes/module.modulemap" \
    -Xlinker -undefined -Xlinker dynamic_lookup \
    "$WORK/Fixture.swift" > "$WORK/compile.log" 2>&1
then
    echo "❌ Component SDK check: the fixture does not compile against the bundled SDK"
    cat "$WORK/compile.log"
    exit 1
fi

nm -u "$WORK/Fixture.dylib" | awk '{print $NF}' | grep -E '18UntoldComponentKit|12UntoldEngine' | sort -u > "$WORK/needed.txt"
nm -gU "$EXECUTABLE" | awk '{print $NF}' | sort -u > "$WORK/exported.txt"
MISSING="$(comm -23 "$WORK/needed.txt" "$WORK/exported.txt")"

if [ -n "$MISSING" ]; then
    echo "❌ Component SDK check: a loaded component library would fail to resolve these symbols."
    echo "   Make the members public or final (see CodeComponent.swift in UntoldComponentKit):"
    echo "$MISSING" | xcrun swift-demangle | sed 's/^/     /'
    exit 1
fi

echo "✅ Component SDK verified: the editor exports all $(wc -l < "$WORK/needed.txt" | tr -d ' ') engine and kit symbols a loaded library needs"
