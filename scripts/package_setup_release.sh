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
# Lean by default (BPE / recomp-ui modular toolchain flow):
#   no embedded toolchain/ — RetComM / the setup wizard download cmake-clang-v1
#   from TechnicallyComputers/retcomm-toolchains (or accept an offline zip).
# Opt-in offline pack: EMERALD_EMBED_TOOLCHAIN=1 or --embed-toolchain via env
#   GBARECOMP_TOOLCHAIN_DIR / EMERALD_TOOLCHAIN_DIR.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-}"
ARTIFACT_TAG="${2:-}"
RECOMPILER_BUILD="${3:-}"
RUNTIME_BIN_DIR="${EMERALD_RUNTIME_BIN_DIR:-${BPE_RUNTIME_BIN_DIR:-/mingw64/bin}}"
EMBED_TOOLCHAIN=0
if [[ "${EMERALD_EMBED_TOOLCHAIN:-${GBARECOMP_EMBED_TOOLCHAIN:-0}}" == "1" ]]; then
  EMBED_TOOLCHAIN=1
fi

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

copy_tree_filtered "${ROOT}/recomp-ui" "${STAGE}/recomp-ui" \
  --exclude '.git' \
  --exclude 'build' \
  --exclude '__pycache__'

rm -rf "${STAGE}/variants/emerald/generated/"*.cpp \
       "${STAGE}/variants/emerald/generated/"*.c \
       "${STAGE}/variants/emerald/roms" 2>/dev/null || true

STAGE_SDK=""
for cand in \
    "${ROOT}/gbarecomp/tools/stage_setup_sdk.sh" \
    "${STAGE}/gbarecomp/tools/stage_setup_sdk.sh"
do
  if [[ -f "${cand}" ]]; then
    STAGE_SDK="${cand}"
    break
  fi
done
if [[ -z "${STAGE_SDK}" ]]; then
  echo "error: gbarecomp/tools/stage_setup_sdk.sh not found" >&2
  exit 1
fi
chmod +x "${STAGE_SDK}" 2>/dev/null || true

stage_args=(
  --stage "${STAGE}"
  --framework "${ROOT}/gbarecomp"
  --search-dir "${EXE_DIR}"
  --search-dir "${BUILD_DIR}"
  --runtime-bin "${RUNTIME_BIN_DIR}"
  --host-exe "${STAGE}/${EXE_BASENAME}"
)
if [[ -n "${RECOMPILER_BUILD}" ]]; then
  stage_args+=(--recompiler-build "${RECOMPILER_BUILD}")
fi
if [[ "${EMBED_TOOLCHAIN}" -eq 1 ]]; then
  TC="${GBARECOMP_TOOLCHAIN_DIR:-${EMERALD_TOOLCHAIN_DIR:-${BPE_TOOLCHAIN_DIR:-}}}"
  if [[ -z "${TC}" || ! -d "${TC}/bin" ]]; then
    echo "error: EMERALD_EMBED_TOOLCHAIN=1 requires GBARECOMP_TOOLCHAIN_DIR (bin/ present)" >&2
    exit 1
  fi
  stage_args+=(--toolchain-dir "${TC}")
else
  stage_args+=(--allow-no-toolchain)
fi

bash "${STAGE_SDK}" "${stage_args[@]}"

cat >"${STAGE}/README-SETUP.txt" <<EOF
Pokémon Emerald Recompiled ${VERSION} — setup package
Platform: ${ARTIFACT_TAG}

One zip for first install and updates. Does NOT include ROM dumps, retail GBA
BIOS dumps, pre-generated cart C, or an embedded portable toolchain/.

The emitter (gba_recompile) and CLI live under gbarecomp/. cmake/clang come
from TechnicallyComputers/retcomm-toolchains (downloaded by RetComM or the
first-run wizard), an offline cmake-clang-v1-*.zip, GBARECOMP_TOOLCHAIN_DIR /
RETCOMM_TOOLCHAIN_DIR, or a system cmake on PATH.

Standalone:
1. Install Python 3.
2. Extract to a simple path (avoid parentheses in the folder name — e.g.
   prefer emerald-0.1.0-linux-x64 over a browser " (1)" rename).
3. Run ${EXE_BASENAME}.
4. On first run, download or pick the portable toolchain, then provide your
   legally owned Emerald (USA) ROM (and a GBA BIOS dump for BIOS backends).
5. Follow the Generate & rebuild wizard.

RetComM uses this same zip: it downloads the toolchain into a shared cache,
promotes tools, and preserves saves/user config.
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
