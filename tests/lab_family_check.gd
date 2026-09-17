extends SceneTree
# Family mount verification: FFA_3 / FFA_4 / TEAM_2V2 / TEAM_2V1 targets + snaps.
var lab: Node
var out_dir: String
var checks: Array = []

func _init() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(40)
    lab._on_target_mode(lab.TARGET_MODES.find("ALL"))
    await settle(6)
    for fam in ["FFA_3", "FFA_4", "TEAM_2V2", "TEAM_2V1"]:
        var idx: int = lab.FORMAT_NAMES.find(fam)
        if idx < 0:
            _check(fam + " exists in FORMAT_NAMES", false, str(lab.FORMAT_NAMES))
            continue
        lab._on_format(idx)
        await settle(60)
        var keys: Array = lab._target_keys()
        var primaries := 0
        for k in keys:
            if "primary" in str(k):
                primaries += 1
        var expected := 3 if fam == "FFA_3" or fam == "TEAM_2V1" else 4
        _check(fam + " mounts with expected primaries", lab.mode_format == fam and primaries == expected,
            "format=%s primaries=%d (expected %d) keys=%d" % [lab.mode_format, primaries, expected, keys.size()])
        await RenderingServer.frame_post_draw
        var img: Image = root.get_texture().get_image()
        img.save_png(out_dir.path_join("70_family_%s.png" % fam))
    # restore duel
    lab._on_format(lab.FORMAT_NAMES.find("1v1"))
    await settle(40)
    var f := FileAccess.open(out_dir.path_join("summary_families.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify({"checks": checks}, "  "))
        f.close()
    print("[FAMILIES] done · checks=", checks.size())
    quit()

func settle(n: int) -> void:
    for i in n:
        await process_frame

func _check(name: String, ok: bool, detail: String = "") -> void:
    checks.append({"check": name, "ok": ok, "detail": detail})
    print("[CHECK] ", "PASS" if ok else "FAIL", "  ", name, "  ", detail)
