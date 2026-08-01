cmake_minimum_required(VERSION 3.20)
project(EmeraldRecomp C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ─────────────────────────────────────────────────────────────────────
# EmeraldRecomp — static recompilation of Pokémon Emerald (GBA).
#
# Single-game repo, but built with the same per-variant scaffold as the
# FRLG / Ruby-Sapphire repos (Sonic3AndKnucklesRecomp pattern) so the
# layout is uniform across the Gen3 line. Per-variant data lives under
# variants/<name>/ (game.toml + config/ + symbols/ + generated/ + roms/).
#
#   Target          Game               ROM       Debug port
#   EmeraldRecomp   Pokémon Emerald    f3ae0881  19892
# ─────────────────────────────────────────────────────────────────────

set(GBARECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/gbarecomp"
    CACHE PATH "Path to the gbarecomp platform-core checkout")
set(RECOMP_UI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/recomp-ui"
    CACHE PATH "Path to the shared recomp-ui checkout")
set(GBARECOMP_RUNTIME_UI_ROOT "${RECOMP_UI_ROOT}"
    CACHE PATH "recomp-ui root used by the live GBA runtime adapter")
set(GBARECOMP_ENABLE_MODS ON CACHE BOOL
    "Build Emerald's built-in mod catalog and trusted-plugin runtime" FORCE)

if(NOT EXISTS "${GBARECOMP_ROOT}/CMakeLists.txt")
    message(FATAL_ERROR
        "GBARECOMP_ROOT does not point to a gbarecomp checkout:\n"
        "  ${GBARECOMP_ROOT}\n"
        "Point it at the engine checkout (default ../gbarecomp) or pass\n"
        "-DGBARECOMP_ROOT=<path> at configure time.")
endif()

# Setup host: launcher + runtime without cart shards (first-run generate).
option(EMERALD_FORCE_SETUP_HOST
    "Build without linking cart generated C even if present" OFF)
option(EMERALD_REQUIRE_GENERATED
    "Fail configure if variants/emerald/generated is missing" OFF)

set(EMERALD_GEN_MARKER
    "${CMAKE_CURRENT_SOURCE_DIR}/variants/emerald/generated/dispatch_table.cpp")
set(EMERALD_HAS_GENERATED FALSE)
if(EXISTS "${EMERALD_GEN_MARKER}" AND NOT EMERALD_FORCE_SETUP_HOST)
    set(EMERALD_HAS_GENERATED TRUE)
endif()

if(EMERALD_REQUIRE_GENERATED AND NOT EMERALD_HAS_GENERATED)
    message(FATAL_ERROR
        "EMERALD_REQUIRE_GENERATED=ON but ${EMERALD_GEN_MARKER} is missing. "
        "Run gbarecomp_cli.py generate, or leave EMERALD_REQUIRE_GENERATED off "
        "to build the setup host.")
endif()

if(NOT EMERALD_HAS_GENERATED)
    message(STATUS
        "Emerald: setup host (no cart generated C) — first-run Generate & rebuild")
    set(GBARECOMP_ALLOW_NO_GENERATED ON CACHE BOOL
        "Allow runtime helper without cart shards (setup host)" FORCE)
endif()

add_subdirectory("${GBARECOMP_ROOT}" gbarecomp_build EXCLUDE_FROM_ALL)

add_executable(verify_rom_hash tools/verify_rom_hash/main.cpp)

# add_gba_variant(<target> <name> <port> <win_title> <game_name> <sha1>
#                  <crc32>)
function(add_gba_variant TARGET NAME PORT WIN_TITLE GAME_NAME ROM_SHA1 ROM_CRC32)
    set(VARIANT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/variants/${NAME}")
    if(EXISTS "${VARIANT_DIR}/generated/recompiled.cpp")
        message(FATAL_ERROR
            "${NAME}: stale monolithic generated/recompiled.cpp found. "
            "Regenerate with the current gba_recompile before building.")
    endif()

    set(VARIANT_GAME_SOURCES src/main.cpp)
    if(GBARECOMP_ENABLE_MODS)
        list(APPEND VARIANT_GAME_SOURCES
            src/mods/emerald_absolute_rtc_plugin.cpp)
    endif()

    set(VARIANT_GENERATED)
    if(EMERALD_HAS_GENERATED)
        file(GLOB VARIANT_GENERATED CONFIGURE_DEPENDS
            "${VARIANT_DIR}/generated/*.c"
            "${VARIANT_DIR}/generated/*.cpp")
        message(STATUS "${NAME}: linking generated cart C (full runtime)")
    else()
        list(APPEND VARIANT_GENERATED
            "${CMAKE_CURRENT_SOURCE_DIR}/src/setup_stubs/cart_dispatch_stub.cpp")
    endif()

    add_executable(${TARGET}
        ${VARIANT_GAME_SOURCES}
        ${VARIANT_GENERATED})

    # Keep generated guest translation units at a bounded optimization and
    # debug-info cost. gba_recompile emits stable recompiled_NNN.cpp shards.
    set(VARIANT_RECOMPILED_SOURCES ${VARIANT_GENERATED})
    list(FILTER VARIANT_RECOMPILED_SOURCES INCLUDE REGEX
        "/recompiled_[0-9]+\\.cpp$")
    if(VARIANT_RECOMPILED_SOURCES)
        set_source_files_properties(${VARIANT_RECOMPILED_SOURCES} PROPERTIES
            COMPILE_OPTIONS "-O1;-g0")
    endif()

    target_include_directories(${TARGET} PRIVATE
        "${GBARECOMP_ROOT}/src/armv4t"
        "${GBARECOMP_ROOT}/src/gba"
        "${GBARECOMP_ROOT}/src/runtime"
        "${GBARECOMP_ROOT}/src/debug"
        src)

    # GNU ld needs --start-group for the circular runtime stack; Apple ld
    # rejects those flags.
    if(APPLE)
        target_link_libraries(${TARGET} PRIVATE
            gbarecomp_runtime
            gbarecomp_debug
            gbarecomp_gba
            gbarecomp_armv4t)
    else()
        target_link_libraries(${TARGET} PRIVATE
            "-Wl,--start-group"
            gbarecomp_runtime
            gbarecomp_debug
            gbarecomp_gba
            gbarecomp_armv4t
            "-Wl,--end-group")
    endif()

    target_compile_definitions(${TARGET} PRIVATE
        GBARECOMP_DEFAULT_DEBUG_PORT=${PORT}
        GBARECOMP_WINDOW_TITLE="${WIN_TITLE}"
        GBARECOMP_DEFAULT_GAME_CONFIG="variants/${NAME}/game.toml"
        GBARECOMP_BUILTIN_NAME="${GAME_NAME}"
        GBARECOMP_BUILTIN_SHA1="${ROM_SHA1}"
        GBARECOMP_BUILTIN_CRC32=${ROM_CRC32}
        GBARECOMP_BUILTIN_REGION="USA")

    if(NOT EMERALD_HAS_GENERATED)
        target_compile_definitions(${TARGET} PRIVATE EMERALD_SETUP_HOST=1)
    endif()

    if(GBAGAME_RECOMP_UI)
        target_link_libraries(${TARGET} PRIVATE game_launcher_ui)
        # Per-variant box art: variants share one build dir, so each stages
        # its own file and points its exe at it (RunOptions.launcher_boxart).
        set(VARIANT_BOXART "${VARIANT_DIR}/launcher/boxart.tga")
        if(EXISTS "${VARIANT_BOXART}")
            add_custom_command(TARGET ${TARGET} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory
                    $<TARGET_FILE_DIR:${TARGET}>/assets/img
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${VARIANT_BOXART}"
                    $<TARGET_FILE_DIR:${TARGET}>/assets/img/boxart_${NAME}.tga
                VERBATIM)
            target_compile_definitions(${TARGET} PRIVATE
                GBARECOMP_BOXART="assets/img/boxart_${NAME}.tga")
        endif()
    endif()

    # 256 MB stack reserve — see FireRedRecomp/CMakeLists.txt rationale
    # (Win64 SEH unwind table scales with ~90k recompiled functions).
    if(MSVC)
        target_link_options(${TARGET} PRIVATE /STACK:268435456)
    elseif(MINGW OR WIN32)
        target_link_options(${TARGET} PRIVATE -Wl,--stack,268435456)
    endif()
endfunction()

# ─────────────────────────────────────────────────────────────────────
# recomp-ui pre-boot launcher (Dear ImGui), consumed as a git submodule
# (junctioned locally to the shared checkout). Isolated in its own
# static lib so recomp-ui's sources + RECOMP_LAUNCHER define never
# touch the giant generated/*.c TU flags — only main.cpp (gated on
# GBAGAME_RECOMP_UI) and launcher_boot.cpp know the launcher exists.
# ─────────────────────────────────────────────────────────────────────
option(GBAGAME_RECOMP_UI "Build the recomp-ui pre-boot launcher" ON)
if(GBAGAME_RECOMP_UI)
    include(${RECOMP_UI_ROOT}/recomp_ui.cmake)
    add_library(game_launcher_ui STATIC
        src/game_launcher_boot.cpp
        src/codegen_setup.c
        "${GBARECOMP_ROOT}/host/gbarecomp_codegen_host.c")
    target_include_directories(game_launcher_ui PRIVATE
        "${GBARECOMP_ROOT}/src/runtime"   # launcher_seam.h + runtime.h
        "${GBARECOMP_ROOT}/src/gba"
        "${GBARECOMP_ROOT}/host"
        "${RECOMP_UI_ROOT}/src"
        src
    )
    if(GBARECOMP_ENABLE_MODS)
        target_compile_definitions(game_launcher_ui PRIVATE
            GBARECOMP_ENABLE_MODS=1)
    endif()
    recomp_target_launcher_ui(game_launcher_ui CONSOLE gba)
    find_package(SDL2 REQUIRED)
    target_link_libraries(game_launcher_ui PUBLIC SDL2::SDL2)
    if(WIN32)
        target_link_libraries(game_launcher_ui PUBLIC opengl32)
    endif()
    set_property(SOURCE src/main.cpp APPEND PROPERTY COMPILE_DEFINITIONS GBAGAME_RECOMP_UI)
endif()

# Emerald — USA, sha1 f3ae0881…
add_gba_variant(EmeraldRecomp emerald 19892 "EmeraldRecomp"
    "Pokemon Emerald (USA)" "f3ae088181bf583e55daf962a92bb46f4f1d07b7" 0x1F1C08FB)

# Ship the game-owned, disabled-by-default mod catalog beside the executable.
# VERBATIM is required: without it, Ninja's shell line escapes spaces but not
# parentheses, so paths like ".../emerald-0.1 (1).0-..." fail at parse time
# (`syntax error near unexpected token '('`) and the link never runs.
set(EMERALD_PRELOADED_MODS "${CMAKE_CURRENT_SOURCE_DIR}/mods/preloaded")
if(EXISTS "${EMERALD_PRELOADED_MODS}/packages")
    add_custom_command(TARGET EmeraldRecomp POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${EMERALD_PRELOADED_MODS}"
            "$<TARGET_FILE_DIR:EmeraldRecomp>/mods"
        COMMENT "Preloading the Emerald mod catalog"
        VERBATIM)
endif()
