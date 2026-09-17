extends SceneTree
# ============================================================================
# Gate E — trustworthy benchmark per researcher protocol:
#   >=300 warm-up frames per case; >=600 measured frames per case per pass;
#   >=3 passes with rotated order; neutral before AND after the stress set;
#   per-frame elapsed deltas (usec); median / p95 / min / pass variance.
# ============================================================================

var lab: Node
var out_dir: String
var results: Array = []

func _init() -> void:
    out_dir = OS.get_environment("FXLAB_EVIDENCE_DIR")
    if out_dir == "":
        out_dir = ProjectSettings.globalize_path("user://evidence")
    DirAccess.make_dir_recursive_absolute(out_dir)
    lab = load("res://scenes/nrcu_fx_lab.tscn").instantiate()
    root.add_child(lab)
    await settle(45)
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    await settle(10)

    # cases: name -> config
    var stress := [
        ["mark_smooth_fringe_flow_off", {"fx": ["fringe"], "driver": 0.0, "blur": 0.0, "format": "1v1"}],
        ["echoes_smooth_fringe_flow_on", {"fx": ["fringe", "flow"], "driver": 0.0, "blur": 0.0, "format": "1v1"}],
        ["ffa4_primaries_generic_driver", {"fx": ["fringe", "flow"], "driver": 2.5, "blur": 0.0, "format": "FFA_4"}],
        ["all_colour_blur", {"fx": ["dither", "fringe", "flow", "rgb"], "driver": 0.0, "blur": 1.0, "format": "1v1", "signal": 2.0}],
        ["team2v2_vector_proxy_overscan", {"fx": ["fringe", "flow", "rgb"], "driver": 2.5, "blur": 1.0, "format": "TEAM_2V2", "signal": 2.0, "target_mode": "ALL"}],
    ]
    var neutral := {"fx": [], "driver": 0.0, "blur": 0.0, "format": "1v1", "signal": 0.0, "target_mode": "ALL"}

    # warm-up: >=300 rendered frames per case
    var all_cases := [["neutral", neutral]]
    for s in stress:
        all_cases.append(s)
    for entry in all_cases:
        await apply_case(entry[1])
        for i in 320:
            await RenderingServer.frame_post_draw

    for p in 3:
        var order := []
        for i in all_cases.size():
            order.append(all_cases[(i + p) % all_cases.size()])
        results.append({"pass": p + 1, "order": order.map(func(e): return e[0]), "cases": []})
        for entry in order:
            await apply_case(entry[1])
            await settle(30)
            var times := PackedFloat32Array()
            var i := 0
            var last := Time.get_ticks_usec()
            while i < 620:
                await RenderingServer.frame_post_draw
                var now := Time.get_ticks_usec()
                if i >= 20:
                    times.append(float(now - last) / 1000.0)  # ms
                last = now
                i += 1
            var stats := _stats(times)
            results[len(results) - 1]["cases"].append({"case": entry[0], "stats": stats})
            print("[BENCH] pass %d %-32s median %.2f ms (%.1f fps) · p95 %.2f ms · min %.1f fps" % [
                p + 1, entry[0], stats["median_ms"], stats["median_fps"], stats["p95_ms"], stats["min_fps"]])

    # summary per case across passes
    var summary := {}
    for pentry in results:
        for c in pentry["cases"]:
            if not summary.has(c["case"]):
                summary[c["case"]] = []
            summary[c["case"]].append(c["stats"])
    print("=== summary (median fps per pass, variance) ===")
    var summary_rows := []
    for name in summary.keys():
        var meds := []
        for st in summary[name]:
            meds.append(st["median_fps"])
        var v: float = (meds.max() - meds.min()) / meds.max() * 100.0
        summary_rows.append({"case": name, "median_fps_per_pass": meds, "variance_pct": snappedf(v, 1),
            "p95_ms_last": summary[name][2]["p95_ms"], "min_fps_last": summary[name][2]["min_fps"]})
        print("[SUMMARY] %-32s medians=%s variance=%.1f%%" % [name, str(meds), v])

    lab.state["color_blur"] = 0.0
    lab.state["driver_mode"] = 0.0
    lab.state["signal_posterize"] = 0.0
    lab.state["pure_continuous"] = false
    await apply_case(neutral)
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
    var f := FileAccess.open(out_dir.path_join("summary_benchmark.json"), FileAccess.WRITE)
    if f != null:
        f.store_string(JSON.stringify({"passes": results, "summary": summary_rows}, "  "))
        f.close()
    print("[BENCH] done")
    quit()

func _stats(times: PackedFloat32Array) -> Dictionary:
    var sorted := times.duplicate()
    sorted.sort()
    var n := sorted.size()
    var median := sorted[n / 2]
    var p95 := sorted[int(float(n) * 0.95)]
    var worst := sorted[n - 1]
    return {"median_ms": snappedf(median, 2), "median_fps": snappedf(1000.0 / median, 1),
        "p95_ms": snappedf(p95, 2), "worst_ms": snappedf(worst, 2), "min_fps": snappedf(1000.0 / worst, 1),
        "frames": n}

func apply_case(cfg: Dictionary) -> void:
    var wanted: String = str(cfg.get("format", "1v1"))
    if lab.mode_format != wanted:
        lab._on_format(lab.FORMAT_NAMES.find(wanted))
        await settle(20)
    lab.state["driver_mode"] = float(cfg.get("driver", 0.0))
    lab.state["color_blur"] = float(cfg.get("blur", 0.0))
    lab.state["signal_posterize"] = float(cfg.get("signal", 0.0))
    if cfg.has("target_mode"):
        lab.target_mode = str(cfg.get("target_mode", "ALL"))
    for f in ["dither", "fringe", "flow", "rgb"]:
        lab.state["fx_on"][f] = f in cfg["fx"]
    lab._apply_fx()
    await settle(4)

func settle(n: int) -> void:
    for i in n:
        await process_frame
