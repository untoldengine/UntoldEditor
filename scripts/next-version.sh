#!/usr/bin/env bash
#
# -------------------------------------------------------------
#  next-version.sh
# -------------------------------------------------------------
#  Description:
#    Determines the next version of the Untold Editor.
#
#    The editor version normally mirrors the UntoldEngine
#    dependency pin in Package.swift (e.g. engine 0.19.0 ->
#    editor 0.19.0). When you need to ship an editor-only
#    change without bumping the engine, pass --editor-patch to
#    append/increment a 4th "editor build" segment instead
#    (0.19.0 -> 0.19.0.1 -> 0.19.0.2, ...). The moment the
#    engine pin moves again, the editor version snaps back to
#    mirroring it (the 4th segment is dropped).
#
#  Optional Flags:
#    --with-v       : Print version with 'v' prefix (e.g. v0.12.7)
#    --editor-patch : Cut an editor-only release: bump the 4th
#                     "editor build" segment instead of mirroring
#                     the engine pin. Requires the engine pin to be
#                     unchanged since the last editor release.
#    --cliff        : Run git-cliff to prepend a changelog section,
#                     then update editorVersion in UntoldEditorApp.swift
#    --docs         : Run Docusaurus docs:version command to
#                     snapshot documentation for the new release
#
#  Usage Examples:
#    ./scripts/next-version.sh               # prints next version
#    ./scripts/next-version.sh --with-v
#    ./scripts/next-version.sh --cliff
#    ./scripts/next-version.sh --cliff --docs
#    ./scripts/next-version.sh --cliff --editor-patch   # editor-only release
#
#  Notes:
#    - Must be executed from the repository root.
#    - Requires Package.swift to pin UntoldEngine with exact: "x.y.z".
#    - Requires UntoldEditorApp.swift to have: static let editorVersion = "x.y.z[.w]"
#    - To bump the engine-mirrored version, update the engine pin in
#      Package.swift first, then run this script without --editor-patch.
#
# -------------------------------------------------------------

set -euo pipefail

WITH_V="false"
DO_CLIFF="false"
DO_DOCS="false"
EDITOR_PATCH="false"

for arg in "$@"; do
  case "$arg" in
    --with-v)       WITH_V="true" ;;
    --cliff)        DO_CLIFF="true" ;;
    --docs)         DO_DOCS="true" ;;
    --editor-patch) EDITOR_PATCH="true" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

MAIN_SWIFT="Sources/UntoldEditor/UntoldEditorApp.swift"

# Read the engine version from the UntoldEngine dependency pin in Package.swift
ENGINE_VER="$(grep -oE 'exact: "[0-9]+\.[0-9]+\.[0-9]+"' Package.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[[ -n "${ENGINE_VER}" ]] || {
  echo "Could not read engine version from Package.swift." >&2
  echo "Make sure UntoldEngine is pinned with: exact: \"x.y.z\"" >&2
  exit 1
}

# Read the currently released editor version (may carry a 4th "editor build" segment)
CURRENT_VERSION_PATTERN='static let editorVersion = "([0-9]+\.[0-9]+\.[0-9]+)(\.[0-9]+)?"'
CURRENT_LINE="$(grep -E "${CURRENT_VERSION_PATTERN}" "${MAIN_SWIFT}" || true)"
[[ -n "${CURRENT_LINE}" ]] || {
  echo "Could not find 'static let editorVersion = \"x.y.z\"' in ${MAIN_SWIFT}." >&2
  exit 1
}
if [[ "${CURRENT_LINE}" =~ ${CURRENT_VERSION_PATTERN} ]]; then
  CURRENT_BASE="${BASH_REMATCH[1]}"
  CURRENT_REV="${BASH_REMATCH[2]#.}"
  CURRENT_REV="${CURRENT_REV:-0}"
fi

# Decide the next version
if [[ "${EDITOR_PATCH}" == "true" ]]; then
  if [[ "${ENGINE_VER}" != "${CURRENT_BASE}" ]]; then
    echo "Engine pin (${ENGINE_VER}) differs from the last editor release's base (${CURRENT_BASE})." >&2
    echo "--editor-patch is for editor-only releases on top of an unchanged engine version." >&2
    echo "Run without --editor-patch to cut a normal engine-mirrored release instead." >&2
    exit 1
  fi
  NEXT="${ENGINE_VER}.$(( CURRENT_REV + 1 ))"
else
  if [[ "${ENGINE_VER}" == "${CURRENT_BASE}" ]]; then
    echo "Engine pin (${ENGINE_VER}) is unchanged since the last editor release (${CURRENT_BASE}.${CURRENT_REV})." >&2
    echo "Bump the engine pin in Package.swift first, or pass --editor-patch to cut an editor-only release." >&2
    exit 1
  fi
  NEXT="${ENGINE_VER}"
fi

# Print version (default behavior)
if [[ "${WITH_V}" == "true" ]]; then
  echo "v${NEXT}"
else
  echo "${NEXT}"
fi

# Optionally run git-cliff to prepend changelog for <last-tag>..HEAD
if [[ "${DO_CLIFF}" == "true" ]]; then
  command -v git-cliff >/dev/null 2>&1 || { echo "git-cliff not found. Install it first." >&2; exit 1; }
  TAG="v${NEXT}"
  BASE_REF="$(git describe --tags --match 'v[0-9]*' --abbrev=0 HEAD 2>/dev/null || true)"
  if [[ -n "${BASE_REF}" ]]; then
    RANGE="${BASE_REF}..HEAD"
  else
    RANGE="HEAD"
  fi
  git cliff "${RANGE}" --tag "${TAG}" --prepend CHANGELOG.md

  # Update the editor version constant in UntoldEditorApp.swift. The launch log line and
  # the window title both read from it, so this is the only string to bump.
  sed -i '' -E 's/'"${CURRENT_VERSION_PATTERN}"'/static let editorVersion = "'"${NEXT}"'"/' "${MAIN_SWIFT}"
  echo "Updated editorVersion to ${NEXT} in ${MAIN_SWIFT}."

fi

# Optionally run Docusaurus docs:version
if [[ "${DO_DOCS}" == "true" ]]; then
  command -v npm >/dev/null 2>&1 || { echo "npm not found. Please install Node.js." >&2; exit 1; }

  DOCS_DIR="website"
  if [[ -d "${DOCS_DIR}" && -f "${DOCS_DIR}/package.json" ]]; then
    echo "Running Docusaurus versioning for ${NEXT} (in ${DOCS_DIR})..."
    (
      cd "${DOCS_DIR}"
      npm run docusaurus docs:version "${NEXT}"
    )
  else
    echo "Running Docusaurus versioning for ${NEXT} (current directory)..."
    npm run docusaurus docs:version "${NEXT}"
  fi

  echo "Docusaurus version ${NEXT} created."
fi
