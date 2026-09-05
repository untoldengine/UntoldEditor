#!/usr/bin/env bash
#
# -------------------------------------------------------------
#  next-version.sh
# -------------------------------------------------------------
#  Description:
#    Determines the current version of the Untold Editor by
#    reading the UntoldEngine dependency pin in Package.swift.
#
#    The editor version always mirrors the engine version, so
#    no commit-log scanning or bump calculation is needed.
#
#  Optional Flags:
#    --with-v   : Print version with 'v' prefix (e.g. v0.12.7)
#    --cliff    : Run git-cliff to prepend a changelog section,
#                 then update editorVersion in main.swift
#    --docs     : Run Docusaurus docs:version command to
#                 snapshot documentation for the new release
#
#  Usage Examples:
#    ./scripts/next-version.sh               # prints current engine-pinned version
#    ./scripts/next-version.sh --with-v
#    ./scripts/next-version.sh --cliff
#    ./scripts/next-version.sh --cliff --docs
#
#  Notes:
#    - Must be executed from the repository root.
#    - Requires Package.swift to pin UntoldEngine with exact: "x.y.z".
#    - To change the editor version, update the engine pin in Package.swift first.
#
# -------------------------------------------------------------

set -euo pipefail

WITH_V="false"
DO_CLIFF="false"
DO_DOCS="false"

for arg in "$@"; do
  case "$arg" in
    --with-v) WITH_V="true" ;;
    --cliff)  DO_CLIFF="true" ;;
    --docs)   DO_DOCS="true" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Read version from UntoldEngine dependency pin in Package.swift
NEXT="$(grep -oE 'exact: "[0-9]+\.[0-9]+\.[0-9]+"' Package.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[[ -n "${NEXT}" ]] || {
  echo "Could not read engine version from Package.swift." >&2
  echo "Make sure UntoldEngine is pinned with: exact: \"x.y.z\"" >&2
  exit 1
}

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

  # Update the editor version constant in main.swift. The launch log line and
  # the window title both read from it, so this is the only string to bump.
  MAIN_SWIFT="Sources/UntoldEditor/main.swift"
  VERSION_PATTERN='static let editorVersion = "[^"]*"'
  grep -qE "${VERSION_PATTERN}" "${MAIN_SWIFT}" || {
    echo "Could not find 'static let editorVersion = \"x.y.z\"' in ${MAIN_SWIFT}." >&2
    exit 1
  }
  sed -i '' 's/'"${VERSION_PATTERN}"'/static let editorVersion = "'"${NEXT}"'"/' "${MAIN_SWIFT}"
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
