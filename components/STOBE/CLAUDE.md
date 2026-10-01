# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Stobe is an x64 native Kenshi plugin (`Stobe.dll`) loaded by RE_Kenshi. It captures game context and chat input, sends HTTP requests to the separate PHP backend [StobeServer](https://github.com/Dwemer-Dynamics/StobeServer), and applies streamed dialogue/action replies and optional TTS audio in game. The server owns prompts, model connectors, memories, and speech synthesis. The client owns live game objects, UI, mic capture, action execution, and playback.

Canonical agent docs ship inside the mod package. Edit them there rather than duplicating them elsewhere:
- `mod/docs/Stobe/AGENTS.md`: ground rules
- `mod/docs/Stobe/agent-guide.md`: source map and diagnostics
- `mod/docs/Stobe/building.md`: toolchain and packaging contract

## Build

The game DLL **must** be compiled with the MSVC 2010 x64 `v100` toolset for Kenshi/MyGUI ABI compatibility. VS 2022 can host the build. Dependencies are not in the repo: you need KenshiLib at the exact commit in `KENSHILIB_REVISION` (`RE_Kenshi_mods` branch), matching MyGUI/Ogre libs, and Boost 1.60.0 headers.

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -T v100 `
  "-DKENSHI_LIB_INCLUDE_DIR=$env:STOBE_SDK_ROOT/Include" `
  "-DKENSHI_LIB_LIBRARY=$env:STOBE_SDK_ROOT/KenshiLib.lib" `
  "-DBOOST_INCLUDE_DIR=$env:STOBE_BOOST_ROOT" `
  -DSTOBE_DIAG_PROFILE=normal
cmake --build build --config Release   # -> build/Release/Stobe.dll
```

- `STOBE_DIAG_PROFILE` (`normal|ui_only|no_hook|hook_no_orig|no_context|no_hook_no_context`) sets `STOBE_DIAG_*` defines that compile out hooks or context capture, which helps bisect crashes.
- New `.cpp` files must be added to `add_library(Stobe ...)` in `CMakeLists.txt`. If the file is SDK-free and should be tested, also add it to `tests/cpp/CMakeLists.txt`. Prefer CMake over the legacy `Stobe.vcxproj`, which has monorepo-relative paths.
- `scripts/build-stobe-sdk.ps1`, mentioned in `.github/copilot-instructions.md`, belongs to the separate Dwemer monorepo. It does **not** exist in this repo, so don't invent a replacement.

### Language constraints (v100 compiler)

CMake says C++14, but the real compiler is VS2010. The codebase uses `auto`, lambdas, and `nullptr`. It has no range-based `for`, `constexpr`, `std::thread`, initializer lists, variadic templates, or `= default`/`= delete`. Write code that compiles under VS2010. The portable tests use a modern compiler, so passing them does **not** prove the DLL will build.

## Tests

Portable tests need no game SDK. They cover only SDK-free logic: `StobeText`, `StobeTiming`, `StobeChatMode`, `StobeIdentityRename`, `AutonomyProtocol`, `AutonomyMonitor`, and `AutonomySafetyProbePolicy`.

```powershell
./scripts/test-cpp.ps1                  # configure + build + ctest into build-tests/
./scripts/test-cpp.ps1 -TestFilter <re> # passes -R to ctest
```

Everything is one executable (`tests/cpp/stobe_text_tests.cpp`) with hand-rolled `ExpectEq`/`ExpectBool`/`ExpectUInt32` helpers in `main()`. It registers a single ctest, so to add a case, add assertions there. CI (`.github/workflows/cpp-tests.yml`) runs these on PRs on `windows-latest`. To keep logic testable, move it into one of these SDK-free units rather than into `main.cpp`/`Functions.cpp`.

## Architecture

- **`src/main.cpp` (~14k lines):** plugin entry point, Kenshi hook installation, the main-thread game update hook, and most of the orchestration: dialogue queues, combat interrupt, item-image sync queue, identity rename queue, and CSV import at startup. File-static globals (`g_*`) hold most runtime state.
- **Threading rule:** Kenshi engine reads and writes happen only on the main game thread inside the hook flow. Network and audio work runs elsewhere, and results are queued back for the update hook to apply. Keep capture, network, response application, and audio lifecycle separate. When changing dialogue flow, check cancellation and stale-response handling.
- **Comm/protocol:** `Comm.*` (WinHTTP, server discovery/fallback, `ServerHost`/`ServerPort` overrides) and `PlaythroughSession.*`. Request payloads come from `Context.*` (NPC/world snapshots). A request/response field change needs a matching StobeServer change. NPC and squad identity is serial-based (`StobeIdentityRename.*`) because names aren't reliable.
- **Actions:** `Functions.cpp` (~10k lines) holds the in-game action executors that server responses invoke.
- **Autonomy** (`Autonomy*`): single-NPC supervised loop, following `docs/AUTONOMY_PLAN.md`. The flow is observe → one LLM decision → validate on server and plugin → execute one action → monitor completion without LLM calls. `docs/AUTONOMY_PHASE0_TESTING.md` and `scripts/test-autonomy-phase0.ps1` drive the INI-gated safety probe against a live install.
- **Engine compatibility:** `Kenshi*Compat.*` / `KenshiRvaCompat.cpp` wrap version-specific engine access. Keep KenshiLib headers, import lib, runtime DLL, and RVA data aligned.
- **UI (MyGUI):** `ChatUI*`, `ChatBox.cpp` (~6k lines), and the `*Window.*` files. Keep UI logic in these files, not in hook code.
- **Config:** `Stobe.ini` holds shipped defaults and loads first. `StobeCustom.ini` holds user overrides, loads second, and receives all runtime/UI saves. See `Utils.cpp`.
- **Logs:** `stobe.log` in the mod dir and beside the game exe, plus legacy `Stobe_SDK.log` in the CWD.

## Repo conventions

- PRs target the **`stobe`** branch, which is the default working branch. Maintainers expect new features to be optional/toggleable and discussed with RANGROO or tyler.maister first (see PR template).
- `mod/` is the release package. `mod/Stobe.dll` is tracked, but don't commit rebuilt binaries in source PRs unless you're preparing a release. Release zips must include `mod/docs/Stobe/*`.
- `build/`, `build-tests/`, `build-map/`, `x64/`, and `vendor/stobe-sdk/` are generated.
- Version changes, deployment, merging, and releases each need explicit authorization. When reporting results, keep source checks, DLL builds, and in-game validation separate. A successful build does not prove an in-game fix.
- The repo is GPL-3.0-only.
