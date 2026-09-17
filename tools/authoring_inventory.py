"""Phase 6 authoring inventory: every canonical field mapped against the
CURRENT source (not historical matrix assumptions).

Columns: block, field, persisted, validated, renderer_read, shader_uniform,
normal_ui, advanced_ui, dependency, test.

Heuristic, documented: 'validated' = key checked inside a _validate_* body;
'renderer_read' = key read via .get()/string literal in fx_layer_renderer;
'normal_ui'/'advanced_ui' = key referenced in lab_shell page builders
(normal inspector pages vs advanced page); 'shader_uniform' = uniform with a
matching name exists. Per-field BEHAVIORAL proof is delivered by the UI
regression suites, not by this table.

Usage: python tools/authoring_inventory.py [--out docs/vnext]
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else os.path.join(ROOT, "docs", "vnext")


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
    try:
        with open(os.path.join(ROOT, "shaders", "nrcu_fx_vnext_layer.gdshader"), encoding="utf-8") as f:
            shader = f.read()
    except OSError:
        shader = ""
    shader_uniforms = set(re.findall(r"uniform\s+\w+\s+(\w+)", shader))

    validate_bodies = " ".join(re.findall(
        r"static func _validate_\w+\(.*?\)[^:]*:\n((?:\t.*\n|\n)+)", look))

    blocks = {
        "layer": ["type", "name", "layer_id", "enabled", "locked", "opacity",
                  "blend_mode", "plane", "input"],
        "transform": keys_in(func_body(look, "neutral_transform")),
        "displacement": keys_in(func_body(look, "neutral_displacement")),
        "mask": keys_in(func_body(look, "neutral_mask")),
        "fx": keys_in(func_body(look, "neutral_fx")),
        "motion": ["enabled", "tracks"],
        "motion.track": keys_in(func_body(look, "_neutral_motion_track")),
    }

    # normal vs advanced UI: split shell at the advanced page builder
    adv_markers = ["_build_advanced_page", "ADVANCED", "advanced_page"]
    adv_idx = min([shell.find(m) for m in adv_markers if shell.find(m) >= 0] or [len(shell)])
    normal_src, adv_src = shell[:adv_idx], shell[adv_idx:]

    dep_keys = {"custom_texture", "custom_mask", "treatment_mask_path",
                "edge_mask_path", "influence_mask"}

    rows = []
    for block, fields in blocks.items():
        seen = set()
        for field in fields:
            if field in seen:
                continue
            seen.add(field)
            lit = '"%s"' % field
            rows.append({
                "block": block,
                "field": field,
                "persisted": "yes",
                "validated": "yes" if field in validate_bodies else "heuristic",
                "renderer_read": "yes" if (lit in renderer or "get(\"%s\"" % field in renderer) else "no",
                "shader_uniform": "yes" if field in shader_uniforms else "n/a",
                "normal_ui": "yes" if lit in normal_src else "no",
                "advanced_ui": "yes" if lit in adv_src else "no",
                "dependency": "asset/incomplete-state" if field in dep_keys else "-",
                "test": "",
            })

    os.makedirs(OUT, exist_ok=True)
    csv_path = os.path.join(OUT, "AUTHORING_INVENTORY.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    total = len(rows)
    no_ui = [r for r in rows if r["normal_ui"] == "no" and r["advanced_ui"] == "no"]
    no_normal = [r for r in rows if r["normal_ui"] == "no" and r["advanced_ui"] == "yes"]
    lines = ["# Authoring inventory (current source, %d fields)" % total, "",
             "- no UI reachability at all: %d" % len(no_ui),
             "- advanced-only: %d" % len(no_normal), "",
             "## No UI reachability (UI-01 hit list)"]
    for r in no_ui:
        lines.append("- %s.%s (renderer_read=%s)" % (r["block"], r["field"], r["renderer_read"]))
    lines += ["", "## Advanced-only (UI-05/06 surface)"]
    for r in no_normal:
        lines.append("- %s.%s" % (r["block"], r["field"]))
    md_path = os.path.join(OUT, "AUTHORING_INVENTORY.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("INVENTORY fields=%d no_ui=%d advanced_only=%d" % (total, len(no_ui), len(no_normal)))
    print("wrote %s and %s" % (csv_path, md_path))


if __name__ == "__main__":
    main()
