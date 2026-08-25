# New-game flow: the plan (2026-08-24)

## STATUS: slices 1-9 all shipped (2026-08-25)

Every screen in Daniel's flow tree exists and is wired.

PARITY PASS — DONE 2026-08-25, with `tools/capture/parity_rows.py` (row-profile
Qud's capture against Raves', pair bands by proximity, read the delta). Every
screen's key landmarks now measure within ~1px of Qud's:
  * Customize (title 0.0px), Build summary (whole attribute column within 1px),
    Attributes (card row +0.3px), Cybernetics (panel +0.4px), Location
    (card row +0.4px), Creating World (emblem +0.1px, dot strip -0.1px).
  * Mutations: within 2px at the top; its rows drift ~0.4px each from the
    THEME's line height, not from a layout fraction. Left alone on purpose.

Two things deliberately NOT changed, each its own measured job:
  * The nav-hint line sits ~6px above Qud's on every card screen — the SHARED
    hook that already-parity-checked screens use.
  * Creating World below the dot strip: Qud draws world-map art there that has
    no counterpart in Raves, so pairing further would be fitting noise.

Pending externally: ONE Qud restart activates every export written for these
slices — startingLocations, pregens, mutations, cybernetics — plus the
name/pet embark params, and the heldLight field the torch work has been
waiting on since 2026-08-23.


Target: `docs/new-game.md` (Daniel's flow tree) + the capture set in
`~/screenshots/new game/`. Goal: Raves' guided chargen matches Qud's, screen for
screen, for Classic / Roleplay / Wander (+ Tutorial); Daily stays Qud-only.

## Where we stand

Built and measured (the ChargenCardScreen template carries the chrome):
- Choose Game Mode, Choose Character Type, Choose Genotype, Choose Caste/Calling.
- Embark via mod EmbarkDriver (genotype + subtype only) — the flow then jumps
  straight into the game, skipping everything after subtype.

`chargen.json` already exports: gameModes, charTypes, genotypes (stats,
statPoints, mutationPoints), subtype classes/categories/subtypes with
statBonuses + info lines. Missing from the export: pregens (Presets lane),
mutations catalog, cybernetics catalog, starting locations, pets, build codes.

## The slices, in order

Each slice ships alone: build -> hv-verified against the capture -> tag.

1. **Build Summary** (`:build summary:`) — the hub every lane funnels into.
   Attributes panel (genotype base + subtype bonuses), Mutations/Implants panel
   (info lines), portrait + name column. Embark moves HERE (the summary's Next),
   so every later slice just feeds this screen. Export Code / Save Build:
   footer affordances stubbed, wired in slice 8.
2. **Choose Starting Location** — card row from a new `startingLocations`
   export (map-tile cards, "Recommended for new players" flavour); embark
   gains a `location` param.
3. **Customize Character** — the two-row form (Name, Pet), Qud's row style;
   embark gains `name` + `pet`. Pets need a small export.
4. **Creating World + embark popup** — the staged progress screen (dots strip,
   log lines, rotating quote) over the existing embark wait; the
   "You embark for the caves of Qud." modal via PopupOverlay when the first
   snapshot lands. Pure client work, no mod change.
5. **Presets lane** — `pregens` export; Choose Preset card screen (portrait
   cards + build blurb) -> summary. This completes Daniel's screenshot lane.
6. **Random** — roll mode/genotype/subtype client-side from the catalog,
   jump to summary. Trivial after 1.
7. **Mutations / Attributes / Cybernetics pickers** (the New lane's middle) —
   the big one: point-buy logic (mutationPoints/statPoints/licenses from the
   catalog), three screens, live cost tallies. Split into 7a mutations,
   7b attributes, 7c cybernetics when we get there.
8. **Library** — build codes (export/import/save), needs Qud's build-code
   round-trip in the mod.
9. **Tutorial lane** — forced Marsh Taur -> forced caravanserai; smallest
   after everything above exists.

## Mod-change batching (ONE Qud restart)

Slices 1–5 need mod-side exports: pregens, startingLocations, pets, and
embark params (location/name/pet/mode honored). Write them ALL in one
EmbarkDriver/ChargenExporter change and restart Qud ONCE — which also finally
activates the heldLight field that has been waiting since the torch work.

## Verification per slice

Same discipline as everything else: hv goto the new scene (each screen gets
its own UiState scene name, like chargen_caste vs chargen_calling), screenshot
against the matching capture in `~/screenshots/new game/`, and the palette
constants stay MEASURED (sample the capture, never eyeball).
