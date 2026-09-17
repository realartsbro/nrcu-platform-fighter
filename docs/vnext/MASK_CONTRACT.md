# NRCU FX Lab vNext — Mask Contract (MK-01..MK-05, Phase 5)

One contract for the four mask mechanisms. Each path answers: what it masks,
in which space, from which source, parameter semantics, enum meanings, missing
asset behavior, offscreen/transformed interaction, persistence/validation/
harvest/runtime consumption.

## P1 — layer.mask (post-FX opacity gate)

1. Masks final layer alpha: `alpha = fx_out.a * mask * layer_opacity`.
2. Sampled in `mask.space`: SOURCE_SPACE (pre-transform asset coords `uv_pre`),
   LAYER_SPACE (post-transform/displacement `final_uv`), PRESENTATION_SPACE
   (canvas px scan; content edges probed through the live transform).
3. Source (`mask.source`): NONE (no field), ORIGINAL_SOURCE_ALPHA
   (pre-transform silhouette), POST_DISPLACEMENT_ALPHA (displaced silhouette),
   CUSTOM_MASK (`mask.custom_mask` asset alpha).
4. `width_px` = band half-width anchor; `expand_contract_px` = silhouette
   offset (+ inside / − outside); `feather_px` = edge softness; `invert` flips.
5. Regions: FULL = whole layer (1.0, or 0.0 inverted); EDGE_BAND = centered
   band on the adjusted edge; OUTER_BAND = outside-only band; INNER_BAND =
   inside-only band. There is NO ALPHA region: alpha-proportional gating is
   expressed as source ORIGINAL/POST_DISPLACEMENT_ALPHA with region FULL.
   CUSTOM_MASK uses the asset field; OUTER/INNER select its outer/inner band.
   Enabled with source NONE is a documented no-op passthrough (field = 1.0),
   not an error — but authors should disable the mask instead.
6. Missing asset: Production validation rejects enabled CUSTOM_MASK without an
   asset or with an unresolvable asset (fail-closed at apply). The renderer
   reports a construct error for an unloadable asset. The shader samples EMPTY
   (0.0) when no asset is loaded — never full.
7. Offscreen/transformed: the field follows the selected space; POST always
   tracks the displaced result; ORIGINAL inverts through the live transform.
8. Persisted at `layer.mask`, validated by `_validate_mask` + MK rules,
   harvested (`mask.custom_mask`), consumed as `mask_*` uniforms.

## P2 — fx edge source (procedural edge modes)

1. Drives edge-weighted FX (fringe/wind/trail), not opacity.
2. Computed in layer UV space from alpha/luma gradients.
3. `edge_source_mode`: 0 = alpha, 1 = luma, 2 = both (max). There is NO
   custom mode: the legacy `custom_edge_mask_tex` path is unreachable (the
   renderer never selects it) and `fx.edge_mask_path` is REJECTED by
   validation — persisting it would pretend a semantic that never renders.
4. `edge_width`/`edge_threshold`/weights shape the procedural response.
5. N/A (no regions).
6. N/A — no asset participates. A non-empty `edge_mask_path` fails validation
   and fails the renderer construct.
7. Runs on the FX layer's actual input (viewport inputs included).
8. Persisted in `fx.*`, range-validated (0..2), consumed as `fx_edge_*`.

## P3 — fx treatment mask (effect gate)

1. Gates the v0.3 treatment/effect stage: `effect_mask_base` selects whether
   the base keeps showing through outside the mask.
2. Sampled in layer UV, clamped, multiplied by the inside-source guard.
3. `treatment_mask_path` asset red channel; `effect_mask_threshold` +
   `effect_mask_softness` shape it; `effect_mask_invert` flips.
4. Disabled (or asset missing at the shader) = 1.0 passthrough: the effect
   runs unmasked. This passthrough is the documented neutral default, NOT a
   silent fallback — enabling the mask WITHOUT an asset fails validation and
   fails the renderer construct.
5. No regions; threshold/softness define the gate.
6. Missing asset + enabled → validate error + construct error. Disabled +
   stale path → path is still existence-checked and harvested.
7. Runs on the FX layer's actual input.
8. Persisted in `fx.*`, validated (MK fx rules), harvested
   (`fx.treatment_mask_path`), consumed as `treatment_mask_tex`/`*_loaded`.

## P4 — displacement.influence_mask (displacement gate)

1. Scales the displacement offset: `offset = driver_offset * influence`.
2. Evaluated PRE-displacement (transform-only uv + pre-transform asset uv).
3. Same source/region/space contract as P1 (NONE/ALPHA-sources/CUSTOM).
4. Same width/expand/feather/invert semantics as P1.
5. Same region meanings as P1 (FULL = displace everywhere).
6. Missing CUSTOM asset → validate error + construct error + shader EMPTY
   (0.0 = no displacement where the field is missing).
7. Offscreen/transformed: follows the selected space like P1.
8. Persisted at `displacement.influence_mask`, validated by `_validate_mask`
   + MK rules, harvested (nested `custom_mask`), consumed as `disp_infl_*`.

## Redundancy verdict

No two live paths claim the same semantic: P1 gates opacity, P2 drives edge
response procedurally, P3 gates the treatment stage, P4 gates displacement.
The only overlap ever found (legacy custom edge texture) was removed from the
supported contract instead of being left parallel.
