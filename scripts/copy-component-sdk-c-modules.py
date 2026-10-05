#!/usr/bin/env python3
#
# copy-component-sdk-c-modules.py <build products folder> <ComponentSDK folder>
#
# Copies into the Component SDK every C module the editor was built with, and prints their
# names, CShaderTypes first. Each becomes `<ComponentSDK>/<Module>/`: the module's public
# headers and a module.modulemap that names them by relative path, so the folder can move with
# the app. create_app_bundle.sh writes the names into sdk.json, and the editor passes one
# -fmodule-map-file per name.
#
# Why this exists: the engine is built without library evolution, so a component that imports
# UntoldEngine makes the compiler load every module the engine imports. For a Swift module that
# is a file in Modules/. A C module needs its headers and a module map, and neither is in the
# build folder: the module map the build system generates points at the package with an
# absolute path, and a C target that brings its own module map keeps it in its package.
#
# Which modules: the same rule as ComponentSDKBuildLayout.swift, which does this for an editor
# run from source. A C target counts when it left objects in the build, because SwiftPM's native
# build system also writes a module map for a target the package declares and the editor does
# not use.

import json
import os
import re
import shutil
import sys

C_SHADER_TYPES = "CShaderTypes"

# A public headers folder can be the target's own folder (CShaderTypes), sources included.
SOURCE_SUFFIXES = (".c", ".cc", ".cpp", ".cxx", ".m", ".mm", ".s", ".S", ".swift", ".o", ".d")

# A comment, a string, a word or a brace. Comments and strings are matched so that what is
# inside them is not read as a word or a brace.
TOKEN = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z0-9_]*|[{}]')


def warn(message):
    print(f"⚠️  Warning: {message}", file=sys.stderr)


class BuildLayout:
    """SwiftPM has two layouts, and Xcode's matches the newer one."""

    def __init__(self, products):
        self.products = products
        generated = os.path.normpath(os.path.join(products, "../../Intermediates.noindex/GeneratedModuleMaps"))
        # Swift Build: `<Target>.o` beside the products, generated module maps together.
        self.swift_build = os.path.isfile(os.path.join(generated, f"{C_SHADER_TYPES}.modulemap"))
        self.generated = generated

    def generated_module_map(self, target):
        if self.swift_build:
            return os.path.join(self.generated, f"{target}.modulemap")
        # SwiftPM's native build system: a `<Target>.build` folder per target.
        return os.path.join(self.products, f"{target}.build", "module.modulemap")

    def swift_modules(self):
        modules = os.path.join(self.products, "Modules")
        folder = modules if os.path.isdir(modules) else self.products
        return {name[: -len(".swiftmodule")] for name in os.listdir(folder) if name.endswith(".swiftmodule")}

    def built_targets(self, excluded):
        """The targets that left objects in this build, without the ones in `excluded`."""
        suffix = ".o" if self.swift_build else ".build"
        targets = [name[: -len(suffix)] for name in sorted(os.listdir(self.products)) if name.endswith(suffix)]
        targets = [target for target in targets if target not in excluded]
        if self.swift_build:
            return targets
        return [
            target
            for target in targets
            if any(file.endswith(".o") for _, _, files in os.walk(os.path.join(self.products, f"{target}.build")) for file in files)
        ]

    def package_directories(self):
        """The folders of the packages the build was made from: SwiftPM clones them into
        `checkouts` of its scratch folder, Xcode into `SourcePackages/checkouts` of its derived
        data folder, and a package used by path stays where it is. The `workspace-state.json`
        beside `checkouts` is SwiftPM's record of both, and leaves out a clone the build no
        longer uses; without it, every clone counts."""
        two_up = os.path.normpath(os.path.join(self.products, "../.."))
        if self.swift_build:
            root = os.path.dirname(two_up)
            workspaces = [root, os.path.join(root, "SourcePackages")]
        else:
            workspaces = [two_up]
        packages = []
        for workspace in workspaces:
            checkouts = os.path.join(workspace, "checkouts")
            try:
                with open(os.path.join(workspace, "workspace-state.json")) as handle:
                    dependencies = json.load(handle)["object"]["dependencies"]
                packages += [
                    d["packageRef"]["location"] if d["packageRef"]["kind"] == "fileSystem" else os.path.join(checkouts, d["subpath"])
                    for d in dependencies
                ]
            except (OSError, KeyError, TypeError, ValueError):
                if os.path.isdir(checkouts):
                    packages += [os.path.join(checkouts, name) for name in sorted(os.listdir(checkouts)) if not name.startswith(".")]
        return packages


def top_level_modules(text):
    """The modules a module map declares itself: `framework module A { module B {} }` declares
    A, and B only as a part of it."""
    modules, depth, name_follows = [], 0, False
    for token in TOKEN.findall(text):
        if token.startswith("/"):
            continue
        if token == "{":
            depth += 1
            name_follows = False
        elif token == "}":
            depth -= 1
        elif name_follows:
            name_follows = False
            if depth == 0:
                modules.append(token.strip('"'))
        elif token == "module":
            name_follows = True
    return modules


def declares(module_map, module):
    try:
        with open(module_map, encoding="utf-8") as handle:
            return module in top_level_modules(handle.read())
    except (OSError, UnicodeDecodeError):
        return False


def own_module_map(module, packages):
    """The module.modulemap a C target brings itself: in its `include` folder by default,
    somewhere else in its package when the target says so."""
    for package in packages:
        conventional = os.path.join(package, "Sources", module, "include", "module.modulemap")
        if declares(conventional, module):
            return conventional
    for package in packages:
        declaring = []
        for folder, subfolders, files in os.walk(package):
            subfolders[:] = [name for name in subfolders if not name.startswith(".")]
            if "module.modulemap" in files and declares(os.path.join(folder, "module.modulemap"), module):
                declaring.append(os.path.relpath(os.path.join(folder, "module.modulemap"), package))
        if declaring:
            # A copy kept deeper in the package (a benchmark, a fixture) is not the target's.
            return os.path.join(package, min(declaring, key=lambda path: (path.count(os.sep), path)))
    return None


def copy_public_headers(source, destination):
    for folder, subfolders, files in os.walk(source):
        subfolders[:] = [name for name in subfolders if not name.startswith(".")]
        for name in files:
            if name.startswith(".") or name.endswith(SOURCE_SUFFIXES):
                continue
            target = os.path.join(destination, os.path.relpath(os.path.join(folder, name), source))
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copyfile(os.path.join(folder, name), target)


def copy_generated(module, module_map, destination):
    """SwiftPM generates one of two module maps, and both name the package by absolute path:
    an umbrella folder, or an umbrella header. Returns why the module cannot be shipped, if so."""
    with open(module_map, encoding="utf-8") as handle:
        text = handle.read()
    header = re.search(r'umbrella\s+header\s+"([^"]+)"', text)
    folder = re.search(r'umbrella\s+"([^"]+)"', text)
    if header:
        headers, umbrella = os.path.dirname(header.group(1)), f'umbrella header "{os.path.basename(header.group(1))}"'
    elif folder:
        headers, umbrella = folder.group(1), 'umbrella "."'
    else:
        return f"its generated module map is not one this script can move: {module_map}"
    if not os.path.exists(header.group(1) if header else headers):
        # A build folder keeps the objects and the module map of a target that is gone.
        return f"its headers are no longer at {headers}"
    copy_public_headers(headers, destination)
    os.makedirs(destination, exist_ok=True)
    with open(os.path.join(destination, "module.modulemap"), "w", encoding="utf-8") as handle:
        handle.write(f"module {module} {{\n    {umbrella}\n    export *\n}}\n")
    return None


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: copy-component-sdk-c-modules.py <build products folder> <ComponentSDK folder>")
    # `../..` is taken from the real folder: `.build/release` is a symlink.
    products, sdk = os.path.realpath(sys.argv[1]), os.path.abspath(sys.argv[2])
    layout = BuildLayout(products)

    packages = None
    copied = []
    for module in [C_SHADER_TYPES] + layout.built_targets(excluded=layout.swift_modules() | {C_SHADER_TYPES}):
        destination = os.path.join(sdk, module)
        generated = layout.generated_module_map(module)
        if os.path.isfile(generated):
            problem = copy_generated(module, generated, destination)
            if problem:
                warn(f"{module} is not shipped: {problem}")
                continue
        elif module == C_SHADER_TYPES:
            warn(f"CShaderTypes module map not found at {generated} — code components will not compile in this build")
            continue
        else:
            if packages is None:
                packages = layout.package_directories()
            own = own_module_map(module, packages)
            if own is None:
                warn(f"no module map found for the C target {module}; the packaging check fails if the engine imports it")
                continue
            copy_public_headers(os.path.dirname(own), destination)
        copied.append(module)

    print("\n".join(copied))


if __name__ == "__main__":
    main()
