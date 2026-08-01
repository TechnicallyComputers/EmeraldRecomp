#!/usr/bin/env bash
# Stage an Emerald *setup host* zip: GUI generate & rebuild without shipping cart C.
#
# Usage:
#   scripts/package_setup_release.sh <build-dir> <artifact-tag> [gba-recompile-build-dir]
# Example:
#   scripts/package_setup_release.sh build-ci linux-x64 build-gba-tools
#
# Writes: dist/emerald-<VERSION>-<artifact-tag>.zip
#
# Contents (no ROM / retail BIOS / generated cart C):
#   EmeraldRecomp[.exe]  — setup host
#   assets/, variants/emerald/{game.toml,symbols,config,launcher}/
#   gbarecomp/           — CLI + host + gba_recompile + sdk helpers
#   recomp-ui/           — launcher UI sources (needed to rebuild)
#   toolchain/           — optional; set EMERALD_TOOLCHAIN_DIR to embed

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-}"
ARTIFACT_TAG="${2:-}"
RECOMPILER_BUILD="${3:-}"
RUNTIME_BIN_DIR="${EMERALD_RUNTIME_BIN_DIR:-${BPE_RUNTIME_BIN_DIR:-/mingw64/bin}}"

if [[ -z "${BUILD_DIR}" || -z "${ARTIFACT_TAG}" ]]; then
  echo "usage: $0 <build-dir> <artifact-tag> [gba-recompile-build-dir]" >&2
  exit 2
fi

VERSION="${EMERALD_RELEASE_VERSION:-}"
if [[ -z "${VERSION}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${ROOT}/VERSION")"
fi
VERSION="$(printf '%s' "${VERSION}" | tr -d '[:space:]')"
VERSION="${VERSION#v}"
if [[ -z "${VERSION}" ]]; then
  echo "VERSION empty (set EMERALD_RELEASE_VERSION or write VERSION file)" >&2
  exit 1
fi
printf '%s\n' "${VERSION}" >"${ROOT}/VERSION"

BUILD_DIR="$(cd "${BUILD_DIR}" && pwd)"
DIST="${ROOT}/dist"
STAGE="${DIST}/stage-setup-${ARTIFACT_TAG}"
ZIP_NAME="emerald-${VERSION}-${ARTIFACT_TAG}.zip"

rm -rf "${STAGE}"
mkdir -p "${STAGE}" "${DIST}"
rm -f "${DIST}/${ZIP_NAME}"

EXE=""
for cand in \
  "${BUILD_DIR}/EmeraldRecomp" \
  "${BUILD_DIR}/EmeraldRecomp.exe" \
  "${BUILD_DIR}/Release/EmeraldRecomp.exe"
do
  if [[ -f "${cand}" ]]; then
    EXE="${cand}"
    break
  fi
done
if [[ -z "${EXE}" ]]; then
  echo "error: setup host executable not found under ${BUILD_DIR}" >&2
  ls -la "${BUILD_DIR}" >&2 || true
  exit 1
fi

cp -a "${EXE}" "${STAGE}/"
EXE_BASENAME="$(basename "${EXE}")"
EXE_DIR="$(dirname "${EXE}")"

if [[ ! -d "${EXE_DIR}/assets/fonts" || ! -d "${EXE_DIR}/assets/img" ]]; then
  echo "error: ${EXE_DIR}/assets/{fonts,img} missing — rebuild EmeraldRecomp with recomp-ui" >&2
  exit 1
fi
mkdir -p "${STAGE}/assets"
cp -a "${EXE_DIR}/assets/fonts" "${STAGE}/assets/"
cp -a "${EXE_DIR}/assets/img" "${STAGE}/assets/"

copy_proj() {
  local rel="$1"
  if [[ -e "${ROOT}/${rel}" ]]; then
    mkdir -p "$(dirname "${STAGE}/${rel}")"
    cp -a "${ROOT}/${rel}" "${STAGE}/${rel}"
  else
    echo "error: missing ${rel}" >&2
    exit 1
  fi
}

copy_proj "CMakeLists.txt"
copy_proj "VERSION"
copy_proj "README.md"
mkdir -p "${STAGE}/src" "${STAGE}/src/setup_stubs" "${STAGE}/variants/emerald"
cp -a "${ROOT}/src/codegen_setup.c" "${STAGE}/src/"
cp -a "${ROOT}/src/codegen_setup.h" "${STAGE}/src/"
cp -a "${ROOT}/src/game_launcher_boot.cpp" "${STAGE}/src/"
cp -a "${ROOT}/src/game_launcher_boot.h" "${STAGE}/src/"
cp -a "${ROOT}/src/main.cpp" "${STAGE}/src/"
cp -a "${ROOT}/src/setup_stubs/cart_dispatch_stub.cpp" "${STAGE}/src/setup_stubs/"
if [[ -d "${ROOT}/src/mods" ]]; then
  cp -a "${ROOT}/src/mods" "${STAGE}/src/"
fi
if [[ -d "${ROOT}/tools/verify_rom_hash" ]]; then
  mkdir -p "${STAGE}/tools"
  cp -a "${ROOT}/tools/verify_rom_hash" "${STAGE}/tools/"
fi
if [[ -d "${ROOT}/mods" ]]; then
  cp -a "${ROOT}/mods" "${STAGE}/"
fi

cp -a "${ROOT}/variants/emerald/game.toml" "${STAGE}/variants/emerald/"
cp -a "${ROOT}/variants/emerald/symbols" "${STAGE}/variants/emerald/"
cp -a "${ROOT}/variants/emerald/config" "${STAGE}/variants/emerald/"
if [[ -d "${ROOT}/variants/emerald/launcher" ]]; then
  cp -a "${ROOT}/variants/emerald/launcher" "${STAGE}/variants/emerald/"
fi
# Empty generated/ placeholder (wizard fills it).
mkdir -p "${STAGE}/variants/emerald/generated"
echo "generated/" >"${STAGE}/variants/emerald/generated/.gitkeep"

copy_tree_filtered() {
  local src="$1" dest="$2"
  shift 2
  mkdir -p "${dest}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$@" "${src}/" "${dest}/"
  else
    cp -a "${src}/." "${dest}/"
    rm -rf "${dest}/.git" 2>/dev/null || true
    find "${dest}" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
    find "${dest}" -type d \( -name 'build' -o -name 'build-*' \) -prune -exec rm -rf {} + 2>/dev/null || true
  fi
}

copy_tree_filtered "${ROOT}/gbarecomp" "${STAGE}/gbarecomp" \
  --exclude '.git' \
  --exclude 'build' \
  --exclude 'build-*' \
  --exclude '__pycache__' \
  --exclude 'oracle' \
  --exclude 'tests'

# Drop regenerated BIOS bodies if present; keep stub + toml.
rm -f "${STAGE}/gbarecomp/src/runtime/generated_bios/bios_recompiled.cpp" \
      "${STAGE}/gbarecomp/bios/gba_bios.bin" \
      "${STAGE}/gbarecomp/bios/"*.bin 2>/dev/null || true

copy_tree_filtered "${ROOT}/recomp-ui" "${STAGE}/recomp-ui" \
  --exclude '.git' \
  --exclude 'build' \
  --exclude '__pycache__'

find_tool_bin() {
  local name="$1"
  local dir cand
  for dir in "${SEARCH_ROOTS[@]}"; do
    for cand in \
      "${dir}/${name}" \
      "${dir}/${name}.exe" \
      "${dir}/Release/${name}.exe"
    do
      if [[ -f "${cand}" ]]; then
        echo "${cand}"
        return 0
      fi
    done
  done
  return 1
}

SEARCH_ROOTS=()
if [[ -n "${RECOMPILER_BUILD}" ]]; then
  SEARCH_ROOTS+=("$(cd "${RECOMPILER_BUILD}" && pwd)")
fi
SEARCH_ROOTS+=(
  "${ROOT}/gbarecomp/build"
  "${ROOT}/build-gba-tools"
  "${ROOT}/build-ci/gbarecomp_build"
)

GBA_BIN="$(find_tool_bin gba_recompile || true)"
if [[ -z "${GBA_BIN}" ]]; then
  echo "error: gba_recompile not found (pass gba-recompile-build-dir)" >&2
  exit 1
fi
mkdir -p "${STAGE}/gbarecomp/build"
cp -a "${GBA_BIN}" "${STAGE}/gbarecomp/build/$(basename "${GBA_BIN}")"
cp -a "${GBA_BIN}" "${STAGE}/gbarecomp/$(basename "${GBA_BIN}")"
chmod +x "${STAGE}/gbarecomp/build/$(basename "${GBA_BIN}")" 2>/dev/null || true
chmod +x "${STAGE}/gbarecomp/$(basename "${GBA_BIN}")" 2>/dev/null || true

if [[ ! -f "${STAGE}/gbarecomp/gbarecomp_cli.py" ]]; then
  echo "error: missing gbarecomp/gbarecomp_cli.py" >&2
  exit 1
fi

cat >"${STAGE}/gbarecomp/retcomm-sdk.json" <<'EOF'
{
  "cli": "gbarecomp_cli.py",
  "id": "gbarecomp-tools",
  "game_bin": "gba_recompile"
}
EOF

TOOLCHAIN_DIR="${EMERALD_TOOLCHAIN_DIR:-${BPE_TOOLCHAIN_DIR:-}}"
if [[ -n "${TOOLCHAIN_DIR}" && -d "${TOOLCHAIN_DIR}" ]]; then
  if [[ ! -d "${TOOLCHAIN_DIR}/bin" ]]; then
    echo "error: toolchain dir missing bin/: ${TOOLCHAIN_DIR}" >&2
    exit 1
  fi
  mkdir -p "${STAGE}/toolchain"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${TOOLCHAIN_DIR}/" "${STAGE}/toolchain/"
  else
    cp -a "${TOOLCHAIN_DIR}/." "${STAGE}/toolchain/"
  fi
  echo "bundled toolchain from ${TOOLCHAIN_DIR}"
else
  echo "warning: EMERALD_TOOLCHAIN_DIR unset — zip will need system cmake/ninja" >&2
fi

# Never ship cart generated C or ROM dumps.
rm -rf "${STAGE}/variants/emerald/generated/"*.cpp \
       "${STAGE}/variants/emerald/generated/"*.c \
       "${STAGE}/variants/emerald/roms" 2>/dev/null || true

if [[ "${EXE_BASENAME}" == *.exe ]]; then
  BUNDLE_DLLS=""
  for cand in \
      "${ROOT}/gbarecomp/tools/bundle_mingw_dlls.sh" \
      "${ROOT}/scripts/bundle_mingw_dlls.sh"
  do
    if [[ -f "${cand}" ]]; then
      BUNDLE_DLLS="${cand}"
      break
    fi
  done
  if [[ -z "${BUNDLE_DLLS}" ]]; then
    echo "error: bundle_mingw_dlls.sh not found" >&2
    exit 1
  fi
  chmod +x "${BUNDLE_DLLS}" 2>/dev/null || true
  GBA_EXE_NAME="$(basename "${GBA_BIN}")"
  if [[ "${GBA_EXE_NAME}" != *.exe ]]; then
    GBA_EXE_NAME="${GBA_EXE_NAME}.exe"
  fi
  bash "${BUNDLE_DLLS}" \
    --runtime-bin "${RUNTIME_BIN_DIR}" \
    --search-dir "${EXE_DIR}" \
    --search-dir "${BUILD_DIR}" \
    --exe "${STAGE}/${EXE_BASENAME}" --dest "${STAGE}" --label "${EXE_BASENAME}" \
    --exe "${STAGE}/gbarecomp/build/${GBA_EXE_NAME}" \
    --dest "${STAGE}/gbarecomp/build" \
    --label "${GBA_EXE_NAME}" \
    --require libgcc_s_seh-1.dll \
    --require libstdc++-6.dll
fi

cat >"${STAGE}/README-SETUP.txt" <<EOF
Pokémon Emerald Recompiled ${VERSION} — setup package
Platform: ${ARTIFACT_TAG}

One zip for first install and updates. Does NOT include ROM dumps, retail GBA
BIOS dumps, or pre-generated cart C. The emitter (gba_recompile) and CLI live
under gbarecomp/. A portable cmake/clang pack is under toolchain/ (removed
automatically after a successful Generate & rebuild).

Standalone:
1. Install Python 3.
2. Run ${EXE_BASENAME} (uses ./toolchain when present; else system cmake).
3. Provide your legally owned Emerald (USA) ROM and a retail GBA BIOS dump.
4. Follow the Generate & rebuild wizard.

RetComM uses this same zip: it promotes tools + toolchain into shared caches
and preserves saves/user config.
EOF

find "${STAGE}" -exec touch -c {} + 2>/dev/null || find "${STAGE}" -exec touch {} +

(
  cd "${STAGE}"
  if command -v zip >/dev/null 2>&1; then
    zip -r -q "${DIST}/${ZIP_NAME}" .
  else
    echo "error: zip not found" >&2
    exit 1
  fi
)

echo "Wrote ${DIST}/${ZIP_NAME}"
du -h "${DIST}/${ZIP_NAME}"
