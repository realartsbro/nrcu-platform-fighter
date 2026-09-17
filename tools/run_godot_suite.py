"""Run one Godot suite with guaranteed process teardown (harness hygiene).

START -> run -> evidence -> deterministic teardown -> process exit ->
verify no owned child remains. Applies to PASS, FAIL, crash, and timeout:
only processes started/owned by THIS runner are ever touched (exact PID,
never a global taskkill /IM).

Usage:
  python tools/run_godot_suite.py --script res://tests/foo_test.gd
      [--timeout 300] [--headless] [--extra-arg ...]

Prints a JSON result line: {rc, timed_out, linger_killed, log}.
Exit code mirrors the suite (124 on runner timeout).
"""
import argparse
import json
import os
import subprocess
import sys
import time

ENGINE = "C:/Users/will/nrcu-fx-lab-v02-work/_vnext_work/_r3_remediation_work/NRCU_FX_LAB_vNEXT_STANDALONE_20260915/engine/Godot_v4.7.2-stable_win64_console.exe"
PROJECT = "C:/Users/will/git/nrcu-platform-fighter-vs-vfx"


def _alive(pid: int) -> bool:
    try:
        out = subprocess.run(
            ["C:/Windows/System32/tasklist.exe", "/FI", "PID eq %d" % pid,
             "/FO", "CSV", "/NH"],
            capture_output=True, text=True, timeout=15)
        return str(pid) in out.stdout
    except Exception:
        return False


def _kill_tree(pid: int) -> None:
    # Exact-PID kill incl. owned children (/T); console Godot ignores
    # cooperative terminate, so /F is the documented fallback here.
    subprocess.run(
        ["C:/Windows/System32/taskkill.exe", "/F", "/T", "/PID", str(pid)],
        capture_output=True, timeout=30)


def run(script: str, timeout: int, headless: bool, extra: list) -> dict:
    cmd = [ENGINE, "--path", PROJECT, "--script", script]
    if headless:
        cmd.insert(3, "--headless")
    else:
        cmd.append("--always-on-top")
    cmd.extend(extra)
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True)
    timed_out = False
    try:
        log, _ = proc.communicate(timeout=timeout)
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        log = ""
        try:
            part, _ = proc.communicate(timeout=5)
            log += part or ""
        except Exception:
            pass
        rc = 124
    finally:
        # Deterministic teardown: the owned PID must be gone afterwards.
        linger_killed = False
        if _alive(proc.pid):
            _kill_tree(proc.pid)
            linger_killed = True
            deadline = time.time() + 10
            while _alive(proc.pid) and time.time() < deadline:
                time.sleep(0.5)
        try:
            if proc.stdout:
                rest = proc.stdout.read()
                if rest:
                    log += rest
        except Exception:
            pass
    return {"rc": rc, "timed_out": timed_out, "linger_killed": linger_killed,
            "pid": proc.pid, "log": log or ""}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", required=True)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--headless", action="store_true")
    ap.add_argument("extra", nargs="*")
    args = ap.parse_args()
    result = run(args.script, args.timeout, args.headless, args.extra or [])
    log = result.pop("log")
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.write(log)
    sys.stdout.write("RUNNER_RC=%d\n" % result["rc"])
    return result["rc"]


if __name__ == "__main__":
    sys.exit(main())
