# EmeraldRecomp

Static recompilation of *Pokémon Emerald Version* (GBA), built on top of
[`gbarecomp`](../gbarecomp).

This is a **recomp**, not a port and not a decomp. The original ROM's
ARM/THUMB machine code is lifted to native C/C++ that runs against the
gbarecomp GBA hardware/runtime model. The decomp at
[`pret/pokeemerald`](https://github.com/pret/pokeemerald) is used **only**
for symbol metadata (names, addresses, sizes); none of its C source,
build output, or toolchain enters this repo.

## Layout

```
EmeraldRecomp/
  CMakeLists.txt              multi-variant scaffold (one game here)
  src/main.cpp                variant-agnostic entry (builtins via compile-defs)
  variants/emerald/
    game.toml                 ROM/BIOS/save/port facts (paths relative to here)
    config/emerald_usa.toml   region overrides (sha1 gate)
    symbols/                  importer output: *.tsv + emerald_usa.toml
    generated/                gba_recompile output (gitignored; regenerate)
    roms/emerald_usa.gba      user-provided (gitignored)
  tools/
    import_decomp_symbols/    readelf dump → symbols/ (shared with FRLG/RSE)
    verify_rom_hash/
```

Debug port: **19892** (distinct from FireRed 19852 / LeafGreen 19862 /
Ruby 19872 / Sapphire 19882 so every runner can be up at once).

## Build & run

Builds against the live `../gbarecomp` checkout on `main`.

```sh
# 1. (one-time) regenerate symbols from a byte-matching pokeemerald WSL
#    build — see ../_gen3_build_symbols.sh; then:
python tools/import_decomp_symbols/import_decomp_symbols.py \
    --name "Pokemon Emerald Version (USA)" --id emerald_usa \
    --syms <readelf.txt> --sections <sections.txt> \
    --rom variants/emerald/roms/emerald_usa.gba \
    --out variants/emerald/symbols

# 2. recompile  →  variants/emerald/generated/
../gbarecomp/build/gba_recompile.exe \
    --rom variants/emerald/roms/emerald_usa.gba \
    --config variants/emerald/symbols/emerald_usa.toml \
    --out variants/emerald/generated

# 3. configure + build (MSYS2 mingw64 + Ninja; build via PowerShell so
#    TEMP is writable — see ../gbarecomp memory notes)
cmake -G Ninja -S . -B build
cmake --build build --target EmeraldRecomp -j

# 4. run (BIOS + ROM both hash-verify or the runtime refuses to start)
./build/EmeraldRecomp.exe
```

## Status

Scaffolded with the gbarecomp engine as of `main` @ `a4e22d7`. ROM
hash-verified (`f3ae0881…`, pokeemerald `emerald.sha1`), symbols imported
(15,856 functions), recompiled. Bring-up tracks the same milestone ladder
as FireRed (see `../FireRedRecomp/CLAUDE.md`).
