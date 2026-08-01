/* Emerald config for the portable gbarecomp codegen host. */

#include "codegen_setup.h"

#include "gbarecomp_codegen_host.h"

/* Keep digests in sync with README / variants/emerald/symbols/emerald_usa.toml. */
static const GbarecompCodegenHostConfig kEmeraldCodegenConfig = {
    .display_name = "Pokémon Emerald",
    .project_root_env = "EMERALD_PROJECT_ROOT",
    .build_dir_env = "EMERALD_BUILD_DIR",
    .force_setup_env = "EMERALD_FORCE_SETUP",
    .gbarecomp_cli_relpath = "gbarecomp/gbarecomp_cli.py",
    .seed_config_relpath = "variants/emerald/symbols/emerald_usa.toml",
    .config = "variants/emerald/symbols/emerald_usa.toml",
    .out_dir = "variants/emerald/generated",
    .gen_marker_relpath = "variants/emerald/generated/dispatch_table.cpp",
    .bios_relpath = "gbarecomp/bios/gba_bios.bin",
    .build_dir_name = "build",
    .cmake_target = "EmeraldRecomp",
    .exe_basename = "EmeraldRecomp",
    .expected_sha1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7",
    .prepare_note =
        "Uses your verified Pokémon Emerald (USA) ROM with the local "
        "gbarecomp SDK to regenerate variants/emerald/generated, then runs "
        "cmake --build and restarts into the new binary. You must legally "
        "own this ROM (and a GBA BIOS dump for BIOS backends).",
    .prepare_note_windows =
        "Uses your verified Pokémon Emerald (USA) ROM with the local "
        "gbarecomp SDK to regenerate variants/emerald/generated, then quits "
        "and rebuilds via a helper so the running .exe is not locked. You "
        "must legally own this ROM.",
    .prepare_note_no_cmake =
        "Uses your verified Pokémon Emerald (USA) ROM with the local "
        "gbarecomp SDK to regenerate variants/emerald/generated. "
        "CMake/build dir not found — rebuild manually: cmake --build build "
        "&& relaunch.",
};

void emerald_codegen_setup_apply(RecompLauncherCGameInfo* gi) {
    gbarecomp_codegen_host_apply(gi, &kEmeraldCodegenConfig);
}

void emerald_codegen_relaunch_or_exit(const char* rom_path) {
    gbarecomp_codegen_host_relaunch_or_exit(rom_path);
}

void emerald_codegen_setup_apply_void(void* game_info) {
    emerald_codegen_setup_apply((RecompLauncherCGameInfo*)game_info);
}

void emerald_codegen_relaunch_void(const char* rom_path) {
    emerald_codegen_relaunch_or_exit(rom_path);
}
