# NRCU FX Lab — Canonical Authoring / Spatial / Production Backlog

This is the working checklist agreed with the researcher. `SOURCE DONE` means implemented and source-tested here; it does **not** mean Godot-runtime certified. `RUNTIME GATE` means implementation exists but must still pass the local Godot 4.7.2 evidence gate.

| # | Workstream | Status | Current implementation / remaining gate |
|---|---|---|---|
| 1 | Central parameter schema | SOURCE DONE | `PARAM_SCHEMA`, section ownership, ergonomic slider ranges, numeric freedom. Runtime UI gate pending. |
| 2 | Per-control / section / factory / revert reset | SOURCE DONE | Visible reset buttons and modified markers; section reset; Reset Look; Revert Look. Runtime UI gate pending. |
| 3 | Base Treatment / Base Opacity | SOURCE DONE | Independent Base Opacity + grade controls. Runtime render gate pending. |
| 4 | Presentation-space spatial authority | SOURCE DONE / RUNTIME GATE | Canonical presentation-size calculation + presentation-pixel shader geometry. Cross-asset rendered parity pending. |
| 5 | Spatial-parameter audit | SOURCE DONE / RUNTIME GATE | Edge Width, Reach, Split, Blur, Flow displacement, RGB, grids classified/decoupled. Rendered parity pending. |
| 6 | FX SIZE / FX INTENSITY / PATTERN SCALE | SOURCE DONE / RUNTIME GATE | Master controls in shader/UI. Extreme-value runtime behavior still to validate. |
| 7 | Semantic target registry | SOURCE DONE / RUNTIME GATE | Texture roles + Side Fields + Name Plates + Accent Lines. Direct visual parity pending. |
| 8 | Overscan / vector proxy architecture | SOURCE DONE / RUNTIME GATE | Padded texture proxy + generated presentation-mask vector proxies. Must pass transform/crop/alpha/multiplayer tests. |
| 9 | Direct target selection / zero-target guard | SOURCE DONE / RUNTIME GATE | Click selection, outline, explicit active-target status, NORMAL/DIM OTHERS/SOLO TARGET preview focus. Runtime hit-testing/ergonomics gate pending. |
| 10 | Full Element Study | SOURCE DONE / RUNTIME GATE | Real VS assets, semantic static IDs, production tints, fit/zoom/pan/backgrounds. Runtime ergonomics/parity gate pending. |
| 11 | Real transport / timeline authoring | SOURCE DONE / RUNTIME GATE | Play/Pause, drag scrub, frame step, direct time, FX Peak, separate clocks. Runtime reconstruction gate pending. |
| 12 | Fringe motion semantics | SOURCE DONE | Flow presented as Fringe Motion / Driver and disabled contextually. |
| 13 | Palette strategies | SOURCE DONE / RUNTIME GATE | Dominant, complement, split-complementary, analogous, triadic, monochrome, locks/swap/adjustments; vector proxies honor production tint. Perceptual OKLCH upgrade remains optional, not blocking. |
| 14 | Debug / inspection views | SOURCE DONE / RUNTIME GATE | Composite/Base/Effect/Edge/Coverage/Treatment/Driver views. Runtime visual gate pending. |
| 15 | Reusable Look vs Assignment separation | SOURCE DONE | Scratch looks + production Looks/Bindings separated. |
| 16 | Production binding schema / specificity | SOURCE DONE | Shared `vs_fx_style_registry.gd`; fighter/role/slot/visual-side/team-side/mode/stage/static identity; integration contract documented. Game rendering consumption intentionally remains a later integration step. |
| 17 | Production authoring UX | SOURCE DONE / RUNTIME GATE | Publish/Assign/Unassign/Load Resolved, production Look browser, Duplicate/Rename/Delete guard, binding browser, specificity/winner preview, and Production Coverage report over fighter/static identities. Runtime ergonomics/write gate pending. |
| 18 | Undo/Redo + copy/paste | SOURCE DONE | Look history + section clipboard. Runtime keyboard/UI gate pending. |
| 19 | Modified-state / collapsible-section polish | SOURCE DONE / RUNTIME GATE | Per-control reset marker, section non-default counts, collapsible LOOK/MOTION sections. Runtime layout gate pending. |
| 20 | Hotkeys / capture metadata | SOURCE DONE / RUNTIME GATE | Space/arrows/Home/B/F, Ctrl+S, Ctrl+Shift+S Save-As focus, Undo/Redo, capture JSON sidecar. Runtime focus/hotkey gate pending. |
| 21 | Cross-asset parity QA | SOURCE DRIVER DONE / RUNTIME GATE | `lab_spatial_parity.gd` + `RUN_SPATIAL_PARITY.bat`; must run on Godot 4.7.2 and calibrate tolerance from evidence. |
| 22 | Final authoring/production QA + fresh package | RUNTIME GATE | Source UX backlog is closed for this pass. One consolidated Godot 4.7.2 runtime/adversarial/fresh-package pass remains. |

## Deliberate non-goals for this pass

- arbitrary reorderable effect stacks;
- node-graph material authoring;
- multiple independently layered Fringe instances per target;
- choosing NRCU's final art direction on the researcher's behalf.
