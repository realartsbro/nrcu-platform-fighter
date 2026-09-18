"""Static/unit tests for the fail-closed Phase 7/8 gate runner."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MODULE = Path(__file__).with_name("run_phase78_gates.py")


def load_runner():
    spec = importlib.util.spec_from_file_location("run_phase78_gates", MODULE)
    if spec is None or spec.loader is None:
        raise AssertionError("could not load phase 7/8 gate runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Phase78GateRunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runner = load_runner()

    def test_source_has_no_global_taskkill_and_no_machine_specific_defaults(self):
        source = MODULE.read_text(encoding="utf-8")
        self.assertNotIn("taskkill", source.lower())
        self.assertNotIn("C:/Users/will", source)
        self.assertNotIn("C:\\\\Users\\\\will", source)

    def test_build_command_is_explicit_headless_and_records_requested_surface(self):
        command = self.runner.build_command(
            Path("/tools/godot.exe"),
            Path("/repo"),
            "res://tests/phase78_lane.gd",
            Path("/out/lane.engine.log"),
            renderer="gl_compatibility",
            viewport="1280x720",
            extra_args=["--fixed-fps", "60"],
        )
        self.assertEqual(command[0], str(Path("/tools/godot.exe")))
        self.assertIn("--headless", command)
        self.assertIn("--rendering-method", command)
        self.assertIn("gl_compatibility", command)
        self.assertIn("--resolution", command)
        self.assertIn("1280x720", command)
        self.assertIn("--path", command)
        self.assertIn(str(Path("/repo")), command)
        self.assertIn("--script", command)
        self.assertIn("res://tests/phase78_lane.gd", command)
        self.assertIn("--log-file", command)
        self.assertIn(str(Path("/out/lane.engine.log")), command)
        self.assertEqual(command[-2:], ["--fixed-fps", "60"])
        with self.assertRaises(ValueError):
            self.runner.build_command(
                Path("/tools/godot.exe"),
                Path("/repo"),
                "res://tests/phase78_lane.gd",
                Path("/out/lane.engine.log"),
                extra_args=["--script", "res://other.gd"],
            )

    def test_classify_rejects_every_fail_closed_condition(self):
        classify = self.runner.classify_run
        base = dict(returncode=0, timed_out=False, stdout="PHASE78_COMPLETE\n", engine_log="", artifacts=[])
        self.assertTrue(classify(**base)["passed"])
        for changed in (
            {"returncode": 1},
            {"timed_out": True},
            {"stdout": "PHASE78_COMPLETE\nSCRIPT ERROR: bad\n"},
            {"engine_log": "E 0:00:00:00 ERROR: renderer failed\n"},
            {"stdout": "PHASE78_COMPLETE\nFAIL: lane\n"},
            {"stdout": "no completion marker\n"},
            {"artifacts": [{"path": "missing.json", "exists": False, "size": 0}]},
            {"artifacts": [{"path": "empty.json", "exists": True, "size": 0}]},
        ):
            case = base.copy()
            case.update(changed)
            self.assertFalse(classify(**case)["passed"], changed)

    def test_prepare_output_is_fresh_and_rejects_project_root(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp) / "project"
            project.mkdir()
            output = project / ".verification" / "phase78"
            output.mkdir(parents=True)
            (output / "stale.txt").write_text("stale", encoding="utf-8")
            fresh = self.runner.prepare_output(project, output)
            self.assertEqual(fresh, output.resolve())
            self.assertTrue(fresh.is_dir())
            self.assertFalse((fresh / "stale.txt").exists())
            with self.assertRaises(ValueError):
                self.runner.prepare_output(project, project)

    def test_owned_process_captures_output_and_cleans_timeout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            quick_log = root / "quick.stdout.log"
            quick = self.runner.run_owned_command(
                [sys.executable, "-c", "print('phase78 quick', flush=True)"],
                root,
                5,
                quick_log,
                os.environ.copy(),
            )
            self.assertEqual(quick["returncode"], 0)
            self.assertFalse(quick["timed_out"])
            self.assertIn("phase78 quick", quick_log.read_text(encoding="utf-8"))

            timeout_log = root / "timeout.stdout.log"
            slow = self.runner.run_owned_command(
                [sys.executable, "-c", "import time; print('phase78 slow', flush=True); time.sleep(20)"],
                root,
                1.0,
                timeout_log,
                os.environ.copy(),
            )
            self.assertTrue(slow["timed_out"])
            self.assertIn("phase78 slow", timeout_log.read_text(encoding="utf-8"))
            self.assertLess(slow["seconds"], 10)

    def test_artifact_paths_are_confined_and_empty_artifacts_fail(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            good = output / "evidence.json"
            good.write_text("{}", encoding="utf-8")
            checks = self.runner.check_artifacts(output, ["evidence.json"])
            self.assertEqual(checks[0]["size"], 2)
            self.assertFalse(self.runner.check_artifacts(output, ["missing.json"])[0]["exists"])
            empty = output / "empty.png"
            empty.touch()
            self.assertEqual(self.runner.check_artifacts(output, ["empty.png"])[0]["size"], 0)
            with self.assertRaises(ValueError):
                self.runner.check_artifacts(output, ["../outside.json"])

    def test_dry_run_lists_only_explicit_scripts_without_running_engine(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            script = project / "lane.gd"
            script.write_text("extends SceneTree\n", encoding="utf-8")
            process = subprocess.run(
                [
                    sys.executable,
                    str(MODULE),
                    "--engine",
                    "not-installed-godot",
                    "--project",
                    str(project),
                    "--script",
                    str(script),
                    "--evidence",
                    "evidence.json",
                    "--dry-run",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(process.returncode, 0, process.stderr)
            plan = json.loads(process.stdout)
            self.assertEqual(plan["scripts"], ["res://lane.gd"])
            self.assertEqual(plan["renderer"], "gl_compatibility")
            self.assertEqual(plan["viewport"], "1280x720")
            self.assertIn("not-installed-godot", plan["commands"][0][0])

    def test_manifest_round_trip_requires_zero_failures(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "manifest.json"
            manifest = {"schema_version": 1, "failures": 0, "complete": True}
            self.runner.write_manifest(path, manifest)
            self.assertEqual(self.runner.read_verified_manifest(path), manifest)
            path.write_text('{"failures": 1, "complete": true}\n', encoding="utf-8")
            with self.assertRaises(ValueError):
                self.runner.read_verified_manifest(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
