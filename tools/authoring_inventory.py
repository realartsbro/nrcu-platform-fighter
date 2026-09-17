"""Phase 6 authoring inventory: two explicit scopes from CURRENT source.

    canonical_fx_109       — the binding 109-field FX matrix (neutral_fx keys
                             must equal docs/vnext/CANONICAL_FX_109.txt)
    full_authoring_surface — everything else authorable (layer, transform,
                             displacement, mask, motion, non-canonical fx keys)

Hard regression: canonical set equality (count AND names). Any delta is
reported as added/removed (never auto-fitted) and fails the run.

Columns per field: scope, persisted, validated, renderer_read,
direct_typed_authoring, macro_reachable, normal_ui, advanced_ui,
dependency, behavioral_status, evidence_test.

Heuristic discovery is labeled 'heuristic' and NEVER counts as VERIFIED.
'verified:<suite>' is assigned only by explicit proof registries below
(suites whose assertions isolate the field's behavior).

Usage: python tools/authoring_inventory.py [--out docs/vnext]
Exit 1 on canonical scope mismatch.
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else os.path.join(ROOT, "docs", "vnext")

# Explicit proof registry: field -> suite that isolates its behavior.
# Only entries here may carry behavioral_status=verified.
VERIFIED = {
    # Phase 4/5 readback + contract suites (isolated assertions)
    "fringe": "capability_parity",
    "rgb_shift_amount": "capability_parity",
    "dither_pixel": "capability_parity",
    "palette_strategy": "palette_contract",
    "edge_source_mode": "mask_contract",
    "effect_mask_enabled": "mask_contract",
    "treatment_mask_path": "mask_contract",
    "edge_mask_path": "mask_contract",
}


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def func_body(src, name):
    m = re.search(r"static func %s\(.*?\)[^:]*:\n((?:\t.*\n|\n)+)" % re.escape(name), src)
    return m.group(1) if m else ""


def keys_in(body):
    return re.findall(r'"([A-Za-z0-9_]+)"\s*:', body)


def main():
    look = read("scripts/fx_vnext/fx_look.gd")
    renderer = read("scripts/fx_vnext/fx_layer_renderer.gd")
    shell = read("scripts/fx_vnext_ui/lab_shell.gd")
    templates = read("scripts/fx_vnext/fx_templates.gd")

    frozen = [l.strip() for l in read("docs/vnext/CANONICAL_FX_109.txt").splitlines()
              if l.strip() and not l.startswith("#")]
    current_fx = keys_in(func_body(look, "neutral_fx"))
    current_set, frozen_set = set(current_fx), set(frozen)
    if current_set != frozen_set:
        print("CANONICAL SCOPE MISMATCH (not fitted, failing):")
        for f in sorted(frozen_set - current_set):
            print("  removed-or-renamed: %s" % f)
        for f in sorted(current_set - frozen_set):
            print("  added: %s" % f)
        print("Check against contract/migration bindings before touching the frozen list.")
        sys.exit(1)
    print("CANONICAL SCOPE OK: neutral_fx == frozen 109 (%d)" % len(frozen))

    validate_bodies = " ".join(re.findall(
        r"static func _validate_\w+\(.*?\)[^:]*:\n((?:\t.*\n|\n)+)", look))
    adv_markers = ["_build_advanced_page", "ADVANCED", "advanced_page"]
    adv_idx = min([shell.find(m) for m in adv_markers if shell.find(m) >= 0] or [len(shell)])
    normal_src, adv_src = shell[:adv_idx], shell[adv_idx:]

    dep_keys = {"custom_texture", "custom_mask", "treatment_mask_path",
                "edge_mask_path", "influence_mask"}

    surface_blocks = {
        "layer": ["type", "name", "layer_id", "enabled", "locked", "opacity",
                  "blend_mode", "plane", "input"],
        "transform": keys_in(func_body(look, "neutral_transform")),
        "displacement": keys_in(func_body(look, "neutral_displacement")),
        "mask": keys_in(func_body(look, "neutral_mask")),
        "motion": ["enabled", "tracks"],
        "motion.track": keys_in(func_body(look, "_neutral_motion_track")),
    }

    rows = []

    def emit(scope, block, field):
        lit = '"%s"' % field
        in_normal = lit in normal_src
        in_adv = lit in adv_src
        verified = VERIFIED.get(field)
        rows.append({
            "scope": scope,
            "block": block,
            "field": field,
            "persisted": "yes",
            "validated": "yes" if field in validate_bodies else "heuristic-gap",
            "renderer_read": "yes" if (lit in renderer or ("get(\"%s\"" % field) in renderer) else "no",
            "direct_typed_authoring": ("verified" if verified else "heuristic") if (in_normal or in_adv) else "no",
            "macro_reachable": "heuristic-template" if lit in templates else "no",
            "normal_ui": "yes" if in_normal else "no",
            "advanced_ui": "yes" if in_adv else "no",
            "dependency": "asset/incomplete-state" if field in dep_keys else "-",
            "behavioral_status": ("verified:" + verified) if verified else "open",
            "evidence_test": verified or "",
        })

    for field in frozen:
        emit("canonical_fx_109", "fx", field)
    for block, fields in surface_blocks.items():
        seen = set()
        for field in fields:
            if field in seen:
                continue
            seen.add(field)
            emit("full_authoring_surface", block, field)

    os.makedirs(OUT, exist_ok=True)
    csv_path = os.path.join(OUT, "AUTHORING_INVENTORY.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    canon_noui = [r for r in rows if r["scope"] == "canonical_fx_109"
                  and r["normal_ui"] == "no" and r["advanced_ui"] == "no"]
    lines = ["# Authoring inventory (current source)", "",
             "- canonical_fx_109: 109 (scope check PASS)",
             "- full_authoring_surface rows: %d" % (len(rows) - 109),
             "- canonical without any UI: %d (UI-01 work list)" % len(canon_noui), "",
             "## Canonical FX without UI (UI-01 work list)"]
    for r in canon_noui:
        lines.append("- fx.%s (renderer_read=%s, behavioral=%s)" %
                     (r["field"], r["renderer_read"], r["behavioral_status"]))
    md_path = os.path.join(OUT, "AUTHORING_INVENTORY.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("INVENTORY canonical_no_ui=%d total_rows=%d" % (len(canon_noui), len(rows)))


if __name__ == "__main__":
    main()
