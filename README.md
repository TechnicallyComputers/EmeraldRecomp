# EmeraldRecomp — Pokémon Emerald, Recompiled

> _This recompilation is a **byproduct of developing
> [gbarecomp](https://github.com/mstan/gbarecomp)** — the games are the proving ground, the framework is the goal.
> **These are in-development previews, not finished ports — expect rough
> edges**, and depth will keep landing over months, not days. My time for any
> one title is limited, so I ask for your patience. Contributions are welcome —
> testing, issues, and PRs to the game or framework all help and will
> accelerate this game's polish. More on the why at:
> [Recomp + AI: 5 Months Later »](https://1379.tech/recomp-ai-5-months-later/)_

Static recompilation of **Pokémon Emerald** (Game Boy Advance) to native PC, built
on the [`gbarecomp`](https://github.com/mstan/gbarecomp) framework.

Its Gen3 siblings live in
[`FireRedLeafGreenRecomp`](https://github.com/mstan/FireRedLeafGreenRecomp) (FireRed + LeafGreen) and
[`RubySapphireRecomp`](https://github.com/mstan/RubySapphireRecomp) (Ruby + Sapphire).

> ### Status — playable bring-up (v0.0.1), and self-improving
>
> This is a **static-recompilation base + runner**, not a finished port. Emerald
> **boots through the BIOS intro to the title screen and into gameplay**. It is
> **early** — not every code path is statically recompiled yet, and content has
> not been exhaustively tested. (Emerald's RTC and its larger battle/contest engine
> are the notable deltas from the other Gen3 games.)
>
> **It gets better the more you play.** Any code path the static recompiler hasn't
> covered runs through a built-in **interpreter the first time it's hit**, then is
> **JIT-compiled to native** (in-process, no toolchain needed) and **remembered on
> disk** — so the next launch runs it natively from the start. Interpreted once,
> native ever after; coverage grows toward fully-native as the game is played. See
> [How it self-improves](#how-it-self-improves).

---

## Screenshots

| Pokémon Emerald — title screen | Pokémon Emerald — a wild encounter |
|---|---|
| ![Pokémon Emerald — title screen, native recompiled build](docs/screenshots/emerald-title.png) | ![Pokémon Emerald — a wild encounter, running natively](docs/screenshots/emerald-gameplay.png) |

*Native recompiled builds (no emulator), captured running the original ROM.*

---

## What "static recompilation" means here

The ROM's **ARM7TDMI machine code is statically translated to native C** — every
function the game runs becomes a real generated C function. Unlike most recomp
projects, **the GBA BIOS is recompiled and executed too** (not HLE'd or stubbed),
so the boot sequence and interrupt/SWI handlers run as real recompiled code. The
rest of the console — the PPU (graphics), APU + M4A sound engine, DMA, timers, the
cartridge flash save chip + RTC, and hardware I/O — is modeled by the `gbarecomp`
runtime.

Only **symbol metadata** (function names, addresses, sizes) from the
[`pret/pokeemerald`](https://github.com/pret/pokeemerald) decompilation enters this
repo — never its C source, build output, or toolchain. **The ROM is never
redistributed**; you supply your own legally-dumped copy.

## ROM

| Target          | Game            | ROM (USA) | SHA-1                                      | Debug port |
|-----------------|-----------------|-----------|-------------------------------------------|------------|
| `EmeraldRecomp` | Pokémon Emerald | USA       | `f3ae088181bf583e55daf962a92bb46f4f1d07b7` | 19892      |

The runtime **refuses to launch on an unrecognized ROM** — the SHA-1 must match.

## Quick start

1. Download the latest `EmeraldRecomp-windows-x64` zip from
   [Releases](../../releases) and extract it (or build from source — see below).
2. Run `EmeraldRecomp`.
3. Supply your own **legally-obtained** Pokémon Emerald (USA) ROM when prompted.
   The path is cached next to the exe for future launches.
4. Play. Early on you may briefly see the interpreter warm up new code paths; once
   warmed (and cached), they run native.

## Controls

| GBA button | Keyboard      |
|------------|---------------|
| D-Pad      | Arrow keys    |
| A          | Z             |
| B          | X             |
| Start      | Enter         |
| Select     | Backspace     |

Save states: **Shift+F1–F9** save to a slot, **F1–F9** load it.

## How it self-improves

`gbarecomp`'s coverage is honest: a path that wasn't statically recompiled is
**bridged through the interpreter** the first time, *loudly*, then healed:

- **First hit:** the interpreter runs the missed function (correct, just not
  native) and the runtime records it.
- **Heal:** the function is **JIT-compiled to native in-process** via a
  toolchain-less backend (sljit) — no compiler required on your machine.
- **Persist:** the healed path is written to a per-ROM cache
  (`recomp_cache/<rom-sha1>/`), so **the next launch re-JITs it up front** and it
  runs native from the start.

The result is a game that converges toward fully-native execution the more it's
played, and **stays** improved across launches. A handful of instruction patterns
the JIT can't lower yet stay on the interpreter (precision over recall); those are
emitter gaps that close over time. Self-improvement is on by default; set
`GBARECOMP_SELFHEAL_RECOMPILE=0` for a pure-interpreter run.

## Building from source

**Prerequisites (Windows):** [MSYS2](https://www.msys2.org/) with the mingw64
toolchain (`gcc`/`g++`), CMake 3.20+, Ninja, and SDL2 (mingw64 package). Builds
are invoked from PowerShell with the mingw64 toolchain on `PATH`.

**Linux:** CMake 3.20+, Ninja, a C++20 compiler, and SDL2 devel packages.

**1. Clone with submodules.** This repo vendors `gbarecomp` and `recomp-ui`.
Netplay also needs `gbarecomp`'s nested `lib/recomp-net` submodule (branch
`main`):

```bash
git clone --recurse-submodules https://github.com/mstan/EmeraldRecomp.git
cd EmeraldRecomp

# If you already cloned without submodules:
git submodule update --init --recursive
# Ensure recomp-net is present (nested under gbarecomp):
git -C gbarecomp submodule update --init lib/recomp-net
```

Override the engine path only if your layout differs:
`-DGBARECOMP_ROOT=/path/to/gbarecomp`.

**2. Supply your ROM** at `variants/emerald/roms/emerald_usa.gba` (SHA-1 above).
ROMs are gitignored and never committed. Place a retail GBA BIOS dump at
`gbarecomp/bios/gba_bios.bin` when regenerating or running (not redistributed).

**3. Recompile + build (with netplay).** Link-cable delay-sync is **on by
default** (`GBARECOMP_ENABLE_NET=ON`). Opt out with
`-DGBARECOMP_ENABLE_NET=OFF` if you do not want `recomp-net` linked.

```bash
# Generate cart C (skip if variants/emerald/generated/ already has shards)
python gbarecomp/gbarecomp_cli.py generate \
  --rom variants/emerald/roms/emerald_usa.gba \
  --config variants/emerald/symbols/emerald_usa.toml \
  --out-dir variants/emerald/generated \
  --project-root . \
  --bios gbarecomp/bios/gba_bios.bin

# Configure + build (Windows: run from PowerShell with mingw64 on PATH)
cmake -S . -B build -G Ninja
cmake --build build --target EmeraldRecomp
```

**Rebuild after pulling** (submodules + engine netplay changes):

```bash
git pull
git submodule update --init --recursive
git -C gbarecomp submodule update --init lib/recomp-net
cmake -S . -B build -G Ninja -DGBARECOMP_ENABLE_NET=ON
cmake --build build --target EmeraldRecomp
```

Binary: `build/EmeraldRecomp` (or `build/EmeraldRecomp.exe` on Windows).

(`gba_recompile` comes from the `gbarecomp` checkout; see
[`docs/LOCAL_CODEGEN_SDK.md`](gbarecomp/docs/LOCAL_CODEGEN_SDK.md).)

Without generated cart C, configure builds a **setup host** (empty dispatch
stub + recomp-ui Generate & rebuild wizard). Force that path with
`-DEMERALD_FORCE_SETUP_HOST=ON`. The recompiled translation units are large —
expect a multi-minute compile after generate.

### Netplay (LAN delay-sync, experimental)

recomp-ui **Netplay** supports LAN / Direct IP lobbies (no online MotK yet).
Both peers wait in the room, host presses Play, then the runtime delay-syncs
over UDP (`recomp-net`) with opaque SIO/pad samples. Build with
`GBARECOMP_ENABLE_NET=ON` (Emerald default).

**From the launcher (preferred)**

1. Start two `EmeraldRecomp` processes (same machine or LAN).
2. Open **Netplay** → Host Lobby with **LAN/Direct IP Only** (or Join the
   listed `LAN - …` row / Direct IP).
3. When both seats are filled, host **Play**. Look for
   `[gbarecomp:netplay] LAN delay-sync ON …` on stderr.
4. Closing either window (or a peer drop) soft-returns **both** clients to the
   Netplay waiting room for a rematch. The dashboard stays single-player (link
   cable is not a second pad card).

Cable Club / Multi-Player SIO is in progress: samples carry up to **14** Multi
words per frame (v2 packing), the child seat auto-starts when the parent's
word is visible, Multi SI/SD cable-sense bits are live while LAN netplay is
plugged, and each seat latches the last-seen Multi word so Emerald's
`DoHandshake` keeps a stable 2-player `SIOMULTI` snapshot under delay-sync.
Host (slot 0) confirms with **A** when prompted; watch for `send=8FFF` /
`latch=8FFF/B9A0`. While netplay is active, stderr prints a **1 Hz**
`[gbarecomp:link]` line (`GBA_LINK_DEBUG=1` for ~4 Hz).

**Env fallback** (headless / no UI):

| Variable | Meaning |
|----------|---------|
| `GBA_NETPLAY=1` | Turn on LAN delay-sync |
| `GBA_NETPLAY_SLOT` | `0` (host) or `1` (guest) |
| `GBA_NETPLAY_BIND` | Local bind, e.g. `0.0.0.0:41000` |
| `GBA_NETPLAY_PEER` | Peer `host:port` (guest); host may leave empty to learn peer |
| `GBA_NETPLAY_DELAY` | Input delay frames (default `2`, range 2–20) |

```bash
# Terminal A — host
GBA_NETPLAY=1 GBA_NETPLAY_SLOT=0 \
  GBA_NETPLAY_BIND=0.0.0.0:41000 \
  ./build/EmeraldRecomp

# Terminal B — guest
GBA_NETPLAY=1 GBA_NETPLAY_SLOT=1 \
  GBA_NETPLAY_BIND=0.0.0.0:41001 \
  GBA_NETPLAY_PEER=127.0.0.1:41000 \
  ./build/EmeraldRecomp
```

Core unit tests (without the full game):

```bash
cmake -S gbarecomp -B gbarecomp/build-link -G Ninja -DGBARECOMP_ENABLE_NET=ON
cmake --build gbarecomp/build-link --target link_tests netplay_smoke_tests
ctest --test-dir gbarecomp/build-link -R 'link_tests|netplay_smoke' --output-on-failure
```

## Legal

This project contains **no copyrighted ROM data, no Nintendo BIOS, and no decomp
source** — only original recompiler/runtime code and symbol metadata. **You must
supply your own legally-dumped ROM** (and BIOS, where the runtime requires one).
Pokémon and Emerald are trademarks of Nintendo / Game Freak / The Pokémon Company;
this project is an unaffiliated, non-commercial preservation and research effort.

---

<p align="center">
  <sub><b>R.A.I.D. — Retro AI Development</b> · a Discord for AI-assisted retro reverse-engineering, decomp &amp; recomp</sub>
</p>

<p align="center">
  <a href="https://discord.gg/Ad9BwSzctP"><img src=".github/raid-discord.png" alt="Join the Retro AI Development (R.A.I.D.) Discord" width="200"></a>
</p>
