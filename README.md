# Raves of Mud — a Caves of Qud modpack (Godot 3D / 2.5D viewer)

**Raves of Mud** (formerly *Raves of Qud*) is a **modpack for
[Caves of Qud](https://www.cavesofqud.com/)** — a 2.5D / 3D augmentation layer for it. It does
*not* reimplement the game. A real, paid, modded copy of Qud runs as the authoritative
simulation; an in-game C# mod publishes what the player sees each turn over a localhost
socket, and a Godot 4 client renders it as a lit 3D scene (greedy-meshed walls, billboarded
sprites, oriented fences) with an orbit/pan/zoom camera. Input round-trips back to Qud, which
resolves every turn.

The player-facing 3D/2.5D view is **the Holodeck** — one component; other user interfaces
(menus, character/inventory, and so on) are separate. ("Holodeck" is the product name; Godot's
API terms — `get_viewport()`, `SubViewport`, "the Godot viewport" — stay as-is in code.)

> Requires your own paid copy of Caves of Qud. Ships **no** game assets — tiles are extracted
> at runtime from your own install into a local, git-ignored folder.

```
┌─────────────┐   command frames (TCP 48710)   ┌────────────────────────┐
│   Godot 4   │ ─────────────────────────────▶ │  Caves of Qud (real)   │
│ 2.5D client │                                │  + Raves bridge mod    │
│ = Holodeck  │ ◀───────────────────────────── │  = authoritative sim   │
└─────────────┘   snapshot frames (per turn)   └────────────────────────┘
```

Qud owns worldgen, AI, combat, items, saves, tiles — everything. This repo owns two mappings:
Godot input → Qud command, and Qud zone state → 3D scene.

## Build environment

| | |
|---|---|
| **Caves of Qud** | A paid, installed copy. Raves ships **no** game assets — tiles are extracted at runtime from your own install into a git-ignored folder. You must enable the mod **and** tick *allow local C# scripting mods* in-game. |
| **Godot 4.7** | The tested version, Forward+ renderer. Other 4.x releases may work; 4.7 is the compatibility contract. Running from the editor needs nothing else. |
| **Godot 4.7 export templates** | Only to build a standalone `.app`. Editor → *Editor* → *Manage Export Templates*, matching your Godot version exactly. |
| **macOS or Windows** | Both run. macOS (Apple Silicon) is where the standalone `.app` is built and where most development happens; Windows runs on a dedicated test rig with its own harness backend. Qud compiles the C# mod in-process on either, so the mod itself never needs building. See [Windows](#windows) for what differs. |
| **.NET SDK** *(optional)* | `dotnet build mod/RavesOfQudBridge.csproj` type-checks the mod against Qud's own `Assembly-CSharp.dll` — ~2s, and it catches API drift before a restart instead of at game launch. **Compile-check only: it deploys nothing, and you never ship the DLL it builds.** Add `-p:CoQManaged="/path/to/Managed"` for a non-default install. |
| **Python 3** *(optional)* | The `tools/` dev-loop scripts. Every tool named in this README and in `CLAUDE.md` is standard library only; about a quarter of `tools/` — the image and voxel ones — also want **Pillow**. |

Nothing here is fetched at build time: no package manager, no lockfile, no network.

## Quickstart

```bash
# 1. Deploy the bridge mod. It compiles when QUD starts, so a mod change always needs a full
#    Qud restart — this is the single most common way to be confused by a change that "did nothing".
MODS=~/Library/Application\ Support/com.FreeholdGames.CavesOfQud/Mods
mkdir -p "$MODS/RavesOfQudBridge"
cp mod/*.cs mod/manifest.json "$MODS/RavesOfQudBridge/"

# 2. Launch Qud. Enable the mod, tick "allow local C# scripting mods", load a save.
#    The mod opens its socket on the first turn, so take a step before checking:
nc -z 127.0.0.1 48710 && echo "bridge up"

# 3a. Run the client from the editor — fastest loop, and a .gd change needs only a re-run:
#     open godot/ in Godot 4.7 and press Play.
# 3b. Or build a standalone app — crisp text on Retina, and what you want for actually playing:
tools/build_macos.sh && open build/RavesOfQud.app
```

The client auto-connects to `127.0.0.1:48710` and retries once a second until Qud answers, so the
order you start them in does not matter.

**If `tools/build_macos.sh` cannot find Godot**, point it at yours — it checks `~/Downloads`,
`/Applications`, `~/Applications` and `$PATH`:

```bash
GODOT=/path/to/Godot.app/Contents/MacOS/Godot tools/build_macos.sh
```

**The mods folder** is Qud's Unity save directory plus `Mods/`. Both of these are paths the
project actually resolves — they are what `plat_mac.qud_data_dir()` and `plat_win.qud_data_dir()`
return. If in doubt, Qud's own *Mods* screen prints the folder it is reading.

| | |
|---|---|
| macOS | `~/Library/Application Support/com.FreeholdGames.CavesOfQud/Mods/` |
| Windows | `%USERPROFILE%\AppData\LocalLow\Freehold Games\CavesOfQud\Mods\` |

### Check it works

The test scenes are headless: no window, no Qud, no save. They are the fastest way to tell a
broken checkout from a broken setup.

```bash
GODOT=${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}
for t in godot/tests/*.tscn; do
  echo "— $(basename "$t" .tscn)"
  "$GODOT" --headless --path godot/ --quit-after 400 "res://$(basename "$(dirname "$t")")/$(basename "$t")"
done
```

Every scene ends in `all good (0 checks failed)`, except `journal_carousel`, which prints
`journal_carousel: OK`. **Close any running Raves window first** — it holds an instance lock, and a
test that hits it exits early having printed nothing, which reads exactly like a test that passed.

Environment paths and the dev loop: [Running it](#running-it) and `CLAUDE.md`.

## What you can do today

Render the current zone as a lit 3D/2.5D scene (voxel walls, billboard sprites, oriented fences); orbit/
pan/zoom with **7 camera modes** + a multi-view grid ([docs/cameras.md](docs/cameras.md)); move and act
with input round-tripped through Qud; **inspect any tile** (Ctrl/Cmd-click) to compare wire-vs-rendered;
and use a **1:1 Qud-style menu** with Mods/Options screens (a live options mirror + save/load presets).
Day/night, per-cell lighting, water/bridges, and the message/target/effects panels track Qud each turn.

## Limitations

Single-player viewer of **your own** local game — multiplayer is a [proposal](docs/multiplayer.md), not
implemented. Runs on macOS and Windows; only macOS has an export preset, so on Windows you run the
client from the Godot editor. The bridge is **localhost-only with no authentication** — never expose
port 48710. Dev-run Godot windows look soft on Retina; export a build for crisp text.

---

## Documentation map

This README is the **front door** (above) plus a deep **engineering reference** (below). Detailed
subsystems have canonical homes in `docs/` — prefer those; the reference below is the reverse-engineering
record:

| page | what |
|---|---|
| **[docs/architecture.md](docs/architecture.md)** | Holodeck boot chain, components, panels, the **threading model**, platform constraints, tile extraction, the bridge cadence. |
| **[docs/rendering.md](docs/rendering.md)** | the 3D render pipeline — classification, **voxel walls**, shading, day/night, lights, fill, overrides. *Start here for anything visual.* |
| **[docs/cameras.md](docs/cameras.md)** | camera modes (**canonical**), the multi-view picker, and viewer controls. |
| **[docs/protocol.md](docs/protocol.md)** | the wire format — normative summary, snapshot & command frames, fields, colours + palette, water. |
| **[docs/qud-api.md](docs/qud-api.md)** | verified Qud namespaces + signatures (reflection-confirmed). |
| **[docs/tools.md](docs/tools.md)** | the Python inspection tools, the in-viewer inspector/report/screenshots, `control.py`/`desktop.py`, option presets, and the **Python-first workflow**. |
| **[docs/gotchas.md](docs/gotchas.md)** · **[docs/roadmap.md](docs/roadmap.md)** · **[docs/decisions/](docs/decisions/)** | invariants + checklists · the world-store roadmap · the war-story debugging record. |
| **[docs/legacy-integration-playbook.md](docs/legacy-integration-playbook.md)** | **portable playbook** for any "Godot on top of a legacy game" target. |
| **[docs/client-in-unity.md](docs/client-in-unity.md)** | **ecosystem port** — build a Raves client in **Unity** against the same engine-agnostic bridge (socket, classification, tiles, colour, input in C#). |
| **[docs/client-in-unreal.md](docs/client-in-unreal.md)** | **ecosystem port** — the same client in **Unreal Engine 5** (FSocket, USTRUCT parse, ISM walls, image-wrapper tiles). |
| **[docs/migrating-clients.md](docs/migrating-clients.md)** | **portable-vs-engine-specific** split, a Godot↔Unity↔Unreal concept crosswalk, port order, and the protocol-versioning rules for multiple clients. |

> **Python-first, for anyone (human or AI) picking this up:** geometry/pixel algorithms (voxel heights,
> fill rules) are **prototyped and verified in Python first** (`tools/capture/voxel.py`, `fill.py` — they
> mirror the GDScript exactly), then ported — because that makes them deterministic and testable without
> a running window. Final lighting/appearance is verified from **captured Holodeck screenshots** (the
> apps screenshot themselves; highvisor can also capture the window). The product is
> well-documented GDScript; Python is validation. See [docs/tools.md](docs/tools.md).

---

# Engineering reference

> New readers can stop at the documentation map above — this section is for working on the internals. It
> keeps repo-level orientation (layout, running it) and a **one-screen index of the data model** with links
> to each fact's canonical home; the deep detail lives in the subsystem docs.

## Repo layout

```
mod/                 Caves of Qud C# scripting mod (the bridge / server)
  Protocol.cs, Json.cs, MiniJson.cs, BridgeServer.cs   pure .NET — no Qud types, unit-testable
  Bridge.cs          per-turn tick: apply queued commands, publish snapshot
  BridgePart.cs      IPart on the player; fires on EndTurnEvent
  PlayerBridgeMutator.cs   [PlayerMutator] attaches BridgePart at game start
  ZoneSnapshot.cs    serialize the active zone -> snapshot JSON
  TileExporter.cs    QUEUE side (turn thread): record tile paths to export, no Unity calls
  TileExportPump.cs  MAIN-thread export via GameManager.uiQueue: atlas readback -> PNG
  RavesOfQudBridge.csproj   DEV-TIME compile harness (see toolkit)
  manifest.json
godot/               Godot 4.x client (GDScript)
  BridgeClient.gd    TCP framing, reconnect, snapshot signal, command send
  ZoneRenderer.gd    the renderer — voxel walls / floors / sprites / fences, colour  ← the meat
  Main.gd            scene wiring, camera modes, day/night + sun/moon, input -> CmdMove*
  CellInspector.gd   Ctrl+click inspector: WIRE vs RENDERED report + sprite preview
  TileReport.gd      lower-right report form -> overrides.json / reports/*.md
  fonts/             Atkinson Hyperlegible (+ Mono), OFL — the UI font
docs/                rendering.md · tools.md · protocol.md  (the subsystem references)
tools/capture/       Python inspection & verification (pure stdlib)
  snap.py            read a snapshot: summary/cell/ident/classify/water/time/find
  tile.py            decode an exported tile: pixels, opaque band, transparency
  fill.py            A/B the interior-fill rules (verify before touching Fill.*)
  voxel.py           voxel height algorithm: colour->level table, ASCII map, oblique PNG
tools/tiletool/      AssetsTools.NET inspector, reversed the atlas storage (diagnostic only)
```

Exported tiles + `overrides.json` + `reports/` live **outside** the repo, under
`~/Library/Application Support/RavesOfQud/`.

---

## Running it

### Environment (macOS paths; see [Windows](#windows) for that rig)
- Game install: `~/Library/Application Support/Steam/steamapps/common/Caves of Qud/CoQ.app`
  (native macOS **IL2CPP** build). Runtime C# mods compile in-process via the game's bundled
  Roslyn, so the **mod** never needs building on either platform — deploy the `.cs` files and
  restart Qud.
- Mods folder: `~/Library/Application Support/com.FreeholdGames.CavesOfQud/Mods/`
- Assembly: `CoQ.app/Contents/Resources/Data/Managed/Assembly-CSharp.dll`
  (retains source-file path metadata → clean, navigable ILSpy).
- Moddable XML: `CoQ.app/Contents/Resources/Data/StreamingAssets/Base/`
  (`Commands.xml`, `Colors.xml` are real; **`ObjectBlueprints.xml` on disk is a 67-byte stub** —
  the real blueprint/tile data lives in the packed Unity bundles).
- `.NET SDK` via Homebrew: `dotnet` at `/opt/homebrew/bin` (may need
  `export PATH="/opt/homebrew/bin:$PATH"` in non-login shells).
- Crash log: `~/Library/Logs/Freehold Games/CavesOfQud/Player.log`

### Deploy the mod
```bash
cp mod/*.cs mod/manifest.json \
  ~/Library/Application\ Support/com.FreeholdGames.CavesOfQud/Mods/RavesOfQudBridge/
```
In-game: enable the mod and **allow local C# scripting mods**. Qud auto-applies mod code.
**Changing a mod `.cs` requires a full Qud restart** (mods compile at startup). Changing a
Godot `.gd` only needs re-running the scene.

### Run the client
Open `godot/` in Godot 4.7 and press play. It auto-connects to `127.0.0.1:48710` and retries
once a second until Qud is listening (the mod opens the socket on the first turn).

### Build a standalone app
```bash
tools/build_macos.sh && open build/RavesOfQud.app
```
Two things this does that pressing Play does not, and both are the reason it exists:

- **Crisp text.** Godot's dev-run gives a floating window a non-HiDPI backing on Retina, so macOS
  upscales it 2x and every glyph looks soft. An exported `.app` sets `NSHighResolutionCapable` and
  renders at native resolution.
- **Re-signs ad-hoc.** Godot's own ad-hoc signature gets `SIGKILL`ed at launch on Apple Silicon
  (*Launchd job spawn failed / 163*); re-signing afterwards is what the kernel accepts.

Needs the **4.7 export templates** installed (Editor → *Manage Export Templates*), and a Godot
binary it can find — see the quickstart for `GODOT=`. The exported app **freezes the scripts at
build time**: a `.gd` change needs a rebuild to reach it, where a dev-run only needs a re-run.
Raw `.vox` files have no `.import` sidecar, so `export_presets.cfg` carries an explicit
`include_filter="*.vox"` — a model that works in a dev run would otherwise be missing from the
shipped app.

<a id="windows"></a>
### Windows

The PC is a real second rig, not an aspiration: `tools/capture/plat.py` dispatches by OS to a
complete Windows backend (`plat_win.py`, pure ctypes against user32 — `SendInput` for input,
`EnumWindows`/`GetWindowRect` for window bounds, `tasklist`/`taskkill` for processes, a `steam://`
URL to launch), and the object-checker regression suite runs there.

Everything above works the same. Four things differ:

- **No export preset.** `export_presets.cfg` only defines macOS, so on Windows you run the client
  from the Godot editor. `tools/build_macos.sh` is exactly what its name says.
- **Mods folder** is `%USERPROFILE%\AppData\LocalLow\Freehold Games\CavesOfQud\Mods\`. Same
  files, same full-Qud-restart rule.
- **Exported tiles still land under `%USERPROFILE%\Library\Application Support\RavesOfQud\`** —
  which looks like a mac path on a Windows box, and is. The mod builds it from
  `SpecialFolder.UserProfile`, which resolves on both, so the shared mod file never had to fork.
- **No Accessibility gate** — synthetic input needs no permission, unlike macOS. But UIPI blocks a
  non-elevated process from sending input to an elevated window, so don't run Qud as admin.

The rig's own operating plan, including the golden-save boot and the checker sweep, is
[docs/pc-test-rig.md](docs/pc-test-rig.md). **Last recorded green run: 2026-08-11** on Qud v0.8.2 —
Object Checker wire 2483/2483 PASS across all seven categories, zero new failures. That is what the
repo records; it is not a claim about this week.

### The live loop
Qud runs (backgrounded is fine) as the server. Godot is the only window you need to watch.
Move with arrows/numpad in **either** — commands round-trip through Qud so the sim resolves
combat/doors/AI exactly as a keypress would.

---

## Architecture, threading & the wire

- **Holodeck architecture** — boot chain, `Main.gd` decomposition, the MainFrame chrome, panels, the
  direction picker, the **threading model** (turn thread vs main thread; graphics only via `uiQueue`), the
  macOS platform constraints, and the tile-extraction pipeline → **[docs/architecture.md](docs/architecture.md)**.
- **The wire protocol** — snapshot + command frames, the normative summary, per-cell/per-object fields,
  colours, water → **[docs/protocol.md](docs/protocol.md)**.
- **Verified Qud API reference** — namespaces + signatures, reflection-confirmed → **[docs/qud-api.md](docs/qud-api.md)**.

## Qud data model & mappings

The full reverse-engineered data model (verified against the live 1.0 build by reflection + capture) now
lives in the subsystem docs. The load-bearing facts, and where each is documented in depth:

- **A cell is NOT just its objects.** Qud paints a ground layer (dirt/grass) onto ~1103/2000 cells that hold
  no GameObject; the mod sends it as a RenderLayer-0 floor at the bottom of each cell's stack.
  → [protocol.md](docs/protocol.md), [rendering.md §2](docs/rendering.md).
- **Accessors, not fields.** `Render.getTile()` / `getRenderString()` resolve runtime-chosen art; the
  `.Tile` / `.RenderString` *fields* are static blueprint values (empty for `PickRandomTile` etc.).
  → [protocol.md](docs/protocol.md), [decisions](docs/decisions/debugging-lessons.md).
- **Colour model.** `ColorString` = `&FG^BG`; `_qud_color` takes the **foreground** (the half before the
  `^`). Tiles are 2-colour masks: black→`TileColor`, white→`DetailColor`, transparent→the world
  background. The 16-char palette ships live in every snapshot (`k`=#0f3b3a, the world's dark teal — **not**
  black). → [protocol.md Colours + palette table](docs/protocol.md#colours), [rendering.md §3](docs/rendering.md).
- **Tile geometry (16×24).** A top-down **cap** over a south **front-face**; the split is not at row 16 and
  varies by family (`_wall_split`; measure from the isolated `-00000000` variant, never `-11111111`).
  → [rendering.md §3–4](docs/rendering.md).
- **Autotiling.** Walls/water carry an 8-bit neighbour bitmask (`-XXXXXXXX`); fences/pipes carry a
  `{n,s,e,w}` connection set (`_connector_dirs`). → [rendering.md §1, §4](docs/rendering.md).
- **RenderLayer → classification.** The `layer` field (+ `wall` / `occluding`) decides flat-floor vs prism
  vs billboard. → [protocol.md RenderLayer values](docs/protocol.md), [rendering.md §1](docs/rendering.md).
- **Water & bridges are first-class Qud concepts** — `Cell.HasWadingDepthLiquid()` / `HasBridge()`, not
  tile-name inference. The render rule: keep the water **flat**, recess the actor (`sinks` = `IsCreature &&
  !IsFlying`, cropped at the waterline; a bridge cancels the sink and decks over the water).
  → [protocol.md Water & bridges](docs/protocol.md#water--bridges), [rendering.md §6](docs/rendering.md).

The hard-won *why* behind each — the grass mystery, the trailing-letter colour bug, the `CAMERA_BACKGROUND`
turquoise trap, the wading-depth control — is in
[docs/decisions/debugging-lessons.md](docs/decisions/debugging-lessons.md).

---


## Rendering & tools

The 3D render pipeline — object classification, the painted ground layer, colour/fill, the **voxel walls**,
lighting (the world honours `SHADED_WORLD`, currently on), day/night + sun/moon, water/bridges, and user
overrides — is documented in full in **[docs/rendering.md](docs/rendering.md)**. The Python inspection tools
and the in-viewer feedback loop (Ctrl/Cmd-click → `selection.txt`; F12 screenshots) are in
**[docs/tools.md](docs/tools.md)**.

## Open problems / next steps

Done since the early drafts: deep water/bridges, tents-as-panels, the painted ground layer,
per-family user overrides (shape/fill/position), the real palette + day/night + sun/moon, **voxel
walls**, and the Python-first verification workflow. What's left:

**Voxel walls** — the flush-and-carve model shipped and looks right (see
[docs/rendering.md §4](docs/rendering.md#4-voxel-walls--flush-surface--carved-gaps)). Largely done:
- Faint cell-seam phase can still differ between autotile variants; chase with `snap.py` if it shows.
- `MultiMesh` per (variant, mesh, rotation) if per-cell instance counts hitch at render radius.

**World model / streaming** — see [docs/roadmap.md](docs/roadmap.md) for the current status. The
persistent `WorldStore` pivot has **shipped**: snapshots are ingested into a per-zone store keyed by
`gameId`, explored zones persist to disk, and remembered neighbours render dimmed. Remaining work is an
adjustable render radius, eviction/budgets, ground-plane growth, and later stacked strata — the spine
for fog of war, memory freeze/unfreeze, Z-height, cross-zone distance, and a future block-editing fork.
Hierarchy: world of parasangs; parasang = 3×3 zones; zone = 80×25 cells; plus Z-strata.
- Each snapshot is a full zone rebuild, but the client already **freezes static geometry** and rebuilds
  only the dynamic layer per turn (per-step render ~85ms → a few ms). The remaining cost is the
  full-zone serialize on the mod side; measure with the profiler (F9) before optimizing further.

**Rendering polish**:
- Sprites/floors don't cast or receive shadows (only walls + ground do). Shadows on the ground
  from a sprite would need the sprite shaded.
- `SINK_WADE`/`SINK_SWIM` are eyeballed; no swim animation or waterline ripple; the crop edge is hard.
- Possible double-drawn ground: `DirtPath`/`DirtFloor` dots sit on cells that also carry a painted
  ground tile, both RenderLayer 0. Check for z-fighting / redundancy.
- Sun/moon are tint-drivers + sky discs; no directional shadows from the moon, no visible-body arc
  unless the camera tilts low.

### Working style that paid off
Ground every change in real data (reflect the DLL, capture a live snapshot, decode a tile) rather
than guessing; appearance is verified from captured screenshots, so the loop is **compile-harness →
deploy → user re-runs → capture/screenshot → adjust**. Keep the Qud-coupled surface small and
isolated so a Qud update is a quick re-verify, not a rewrite.

**License:** MIT (see `LICENSE`). Requires a separately-purchased copy of Caves of Qud; Caves of
Qud and its assets are © Freehold Games.
