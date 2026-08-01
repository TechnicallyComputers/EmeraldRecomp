// Empty cart dispatch for Emerald setup-host builds (no generated shards yet).
// Replaced after `gbarecomp_cli.py generate` produces variants/emerald/generated/.

#include <cstdint>

struct DispatchEntry {
    std::uint32_t addr;
    std::uint8_t thumb;
    std::uint8_t resume;
    void (*fn)(void);
};

extern "C" const DispatchEntry kDispatchTable[] = {
    {0u, 0u, 0u, nullptr},
};
extern "C" const unsigned kDispatchTableLen = 0;

// main.cpp's Emerald RAM flash hooks call these; generated cart C provides
// the real bodies after Generate. Unreachable in the setup host (no cart).
extern "C" void gf_ReadFlash1(void) {}
extern "C" void gf_ReadFlash_Core(void) {}
