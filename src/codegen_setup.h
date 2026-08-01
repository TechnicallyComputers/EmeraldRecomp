/* Emerald thin wrapper around gbarecomp portable codegen host. */
#ifndef EMERALD_CODEGEN_SETUP_H
#define EMERALD_CODEGEN_SETUP_H

#include "recomp_launcher.h"

#ifdef __cplusplus
extern "C" {
#endif

void emerald_codegen_setup_apply(RecompLauncherCGameInfo* gi);
void emerald_codegen_relaunch_or_exit(const char* rom_path);

/* RunOptions function-pointer shims (void* / const char*). */
void emerald_codegen_setup_apply_void(void* game_info);
void emerald_codegen_relaunch_void(const char* rom_path);

#ifdef __cplusplus
}
#endif

#endif /* EMERALD_CODEGEN_SETUP_H */
