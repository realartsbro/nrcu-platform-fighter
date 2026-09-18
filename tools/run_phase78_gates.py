"""Fail-closed verification runner for explicit Phase 7/8 Godot lanes.

The runner deliberately does not discover tests and does not reuse the broader
project runners. Every invocation must name one or more scripts and one or more
expected evidence files. Each script is run headlessly in a fresh output
folder. A successful run requires all of the following for every script:

* exit code zero and no timeout;
* no Godot/script error or FAIL marker in stdout or the engine log;
* the configured completion marker in stdout or the engine log;
* every explicitly named evidence artifact exists and is non-empty; and
* the runner manifest is valid JSON with ``failures == 0``.

Example::

    python tools/run_phase78_gates.py \
        --engine C:/Godot/Godot_v4.7.2-stable_win64_console.exe \
        --project C:/src/nrcu-platform-fighter-vs-vfx \
        --script res://tests/phase7_behavior_test.gd \
        --script res://tests/phase8_behavior_test.gd \
        --evidence phase7/summary.json \
        --evidence phase8/summary.json \
        --completion-marker PHASE78_COMPLETE

``--list`` and ``--dry-run`` print the exact explicit script plan without
starting Godot or touching the output directory. The process owner uses a
Windows Job Object (and a new process group elsewhere) so timeout cleanup is
limited to descendants started by this runner; it never uses a global image
kill.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable, Sequence


SCHEMA_VERSION = 1
DEFAULT_RENDERER = "gl_compatibility"
DEFAULT_VIEWPORT = "1280x720"
DEFAULT_COMPLETION_MARKER = "PHASE78_COMPLETE"
DEFAULT_TIMEOUT = 180.0

# These patterns are intentionally conservative. A lane that prints an error
# is not a passing behavioral proof, even when it later prints a success line.
SCRIPT_ERROR_RE = re.compile(
    r"\b(?:SCRIPT\s+ERROR|PARSE\s+ERROR|COMPILE\s+ERROR|SCRIPT\s+BUG)\b",
    re.IGNORECASE,
)
ENGINE_ERROR_RE = re.compile(
    r"(?:\bERROR\b|\bFATAL\b|\bFAILED\b|\bE\s+\d+:[^\n]*:)",
    re.IGNORECASE,
)
FAIL_MARKER_RE = re.compile(
    r"(?:\bFAIL(?:ED|URE)?\b|\bfailures\s*[:=]\s*(?!0\b)\d+)",
    re.IGNORECASE,
)
VIEWPORT_RE = re.compile(r"^[1-9]\d*x[1-9]\d*$")
RESERVED_EXTRA_ARGS = {
    "--editor",
    "--headless",
    "--log-file",
    "--path",
    "--rendering-method",
    "--resolution",
    "--script",
    "--fullscreen",
    "--maximized",
    "--always-on-top",
}


class RunnerError(RuntimeError):
    """An operational error that should be recorded as a manifest failure."""


def _matching_lines(text: str, pattern: re.Pattern[str]) -> list[str]:
    return [line for line in text.splitlines() if pattern.search(line)]


def _relative_path(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def _resolve_project_path(project: Path, raw: str) -> Path:
    candidate = Path(raw).expanduser()
    if not candidate.is_absolute():
        candidate = project / candidate
    return candidate.resolve()


def normalize_script(project: Path, raw: str) -> str:
    """Validate one explicit script and return its project-relative Godot URI."""
    project = project.resolve()
    if raw.startswith("res://"):
        relative = Path(raw.removeprefix("res://"))
        candidate = (project / relative).resolve()
    else:
        candidate = _resolve_project_path(project, raw)
    if candidate == project or not candidate.is_relative_to(project):
        raise ValueError(f"script is outside project: {raw}")
    if candidate.suffix.lower() != ".gd":
        raise ValueError(f"script is not a GDScript file: {raw}")
    if not candidate.is_file():
        raise ValueError(f"script does not exist: {raw}")
    return "res://" + candidate.relative_to(project).as_posix()


def _validate_viewport(viewport: str) -> None:
    if not VIEWPORT_RE.fullmatch(viewport):
        raise ValueError("viewport must use WIDTHxHEIGHT with positive integers")


def build_command(
    engine: Path | str,
    project: Path,
    script: str,
    engine_log: Path,
    renderer: str = DEFAULT_RENDERER,
    viewport: str = DEFAULT_VIEWPORT,
    extra_args: Sequence[str] | None = None,
) -> list[str]:
    """Build the complete, reproducible headless Godot command."""
    if not renderer.strip():
        raise ValueError("renderer must not be empty")
    _validate_viewport(viewport)
    for extra in extra_args or []:
        option = str(extra).split("=", 1)[0]
        if option in RESERVED_EXTRA_ARGS:
            raise ValueError(f"extra argument would override runner-owned option: {extra}")
    command = [
        str(engine),
        "--headless",
        "--path",
        str(project),
        "--rendering-method",
        renderer,
        "--resolution",
        viewport,
        "--log-file",
        str(engine_log),
        "--script",
        script,
    ]
    command.extend(str(value) for value in (extra_args or []))
    return command


def _configure_windows_job() -> tuple[Any, Any, Any, Any, Any] | None:
    """Return Windows Job Object API handles/types, without loading them elsewhere."""
    if os.name != "nt":
        return None
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    handle_type = wintypes.HANDLE
    kernel32.CreateJobObjectW.argtypes = [handle_type, wintypes.LPCWSTR]
    kernel32.CreateJobObjectW.restype = handle_type
    kernel32.SetInformationJobObject.argtypes = [
        handle_type,
        wintypes.DWORD,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    kernel32.SetInformationJobObject.restype = wintypes.BOOL
    kernel32.AssignProcessToJobObject.argtypes = [handle_type, handle_type]
    kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [handle_type]
    kernel32.CloseHandle.restype = wintypes.BOOL
    return kernel32, handle_type, wintypes.DWORD, ctypes.c_void_p, wintypes.BOOL


if os.name == "nt":

    class _JobBasicLimitInformation(ctypes.Structure):
        _fields_ = [
            ("PerProcessUserTimeLimit", ctypes.c_longlong),
            ("PerJobUserTimeLimit", ctypes.c_longlong),
            ("LimitFlags", wintypes.DWORD),
            ("MinimumWorkingSetSize", ctypes.c_size_t),
            ("MaximumWorkingSetSize", ctypes.c_size_t),
            ("ActiveProcessLimit", wintypes.DWORD),
            ("Affinity", ctypes.c_size_t),
            ("PriorityClass", wintypes.DWORD),
            ("SchedulingClass", wintypes.DWORD),
        ]


    class _IoCounters(ctypes.Structure):
        _fields_ = [("ReadOperationCount", ctypes.c_ulonglong)] + [
            (name, ctypes.c_ulonglong)
            for name in (
                "WriteOperationCount",
                "OtherOperationCount",
                "ReadTransferCount",
                "WriteTransferCount",
                "OtherTransferCount",
            )
        ]


    class _JobExtendedLimitInformation(ctypes.Structure):
        _fields_ = [
            ("BasicLimitInformation", _JobBasicLimitInformation),
            ("IoInfo", _IoCounters),
            ("ProcessMemoryLimit", ctypes.c_size_t),
            ("JobMemoryLimit", ctypes.c_size_t),
            ("PeakProcessMemoryUsed", ctypes.c_size_t),
            ("PeakJobMemoryUsed", ctypes.c_size_t),
        ]


class _WindowsJob:
    """Own a process tree with a kill-on-close Windows Job Object."""

    JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000

    def __init__(self, process: subprocess.Popen[Any]):
        api = _configure_windows_job()
        if api is None:
            raise RunnerError("Windows Job Object requested on a non-Windows host")
        self._kernel32, self._handle_type, self._dword_type, _, _ = api
        self._handle = self._kernel32.CreateJobObjectW(None, None)
        if not self._handle:
            raise ctypes.WinError(ctypes.get_last_error())
        self._closed = False
        try:
            limits = _JobExtendedLimitInformation()
            limits.BasicLimitInformation.LimitFlags = self.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if not self._kernel32.SetInformationJobObject(
                self._handle,
                self.JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                ctypes.byref(limits),
                ctypes.sizeof(limits),
            ):
                raise ctypes.WinError(ctypes.get_last_error())
            if not self._kernel32.AssignProcessToJobObject(self._handle, process._handle):
                raise ctypes.WinError(ctypes.get_last_error())
        except BaseException:
            self.close()
            raise
    def close(self) -> None:
        if not getattr(self, "_closed", True) and self._handle:
            self._kernel32.CloseHandle(self._handle)
            self._closed = True
            self._handle = None


class _OwnedProcess:
    """Start and tear down only the process tree created by this runner."""

    def __init__(self, command: Sequence[str], cwd: Path, env: dict[str, str], stdout: Any):
        kwargs: dict[str, Any] = {
            "cwd": str(cwd),
            "env": env,
            "stdin": subprocess.DEVNULL,
            "stdout": stdout,
            "stderr": subprocess.STDOUT,
        }
        if os.name == "nt":
            kwargs["creationflags"] = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        else:
            kwargs["start_new_session"] = True
        self.process = subprocess.Popen(list(command), **kwargs)
        self._job: _WindowsJob | None = None
        self._closed = False
        if os.name == "nt":
            try:
                self._job = _WindowsJob(self.process)
            except BaseException:
                if self.process.poll() is None:
                    self.process.kill()
                self.process.wait()
                raise RunnerError("could not assign Godot process to an owned Windows Job Object")

    def wait(self, timeout: float) -> int:
        return self.process.wait(timeout=timeout)

    def kill_tree(self) -> list[str]:
        errors: list[str] = []
        if os.name == "nt":
            # Stop the root first, then close the KILL_ON_JOB_CLOSE job so
            # descendants are terminated even if the root races its wait.
            if self.process.poll() is None:
                try:
                    self.process.kill()
                except OSError as exc:
                    errors.append(f"owned root kill failed: {exc}")
            errors.extend(self.close())
        else:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except OSError as exc:
                errors.append(f"owned process-group kill failed: {exc}")
            if self.process.poll() is None:
                try:
                    self.process.kill()
                except OSError as exc:
                    errors.append(f"owned root kill failed: {exc}")
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            errors.append("owned process did not exit after cleanup")
        return errors

    def close(self) -> list[str]:
        if self._closed:
            return []
        self._closed = True
        if self._job is not None:
            try:
                self._job.close()
            except OSError as exc:
                return [f"Windows Job Object close failed: {exc}"]
        else:
            # ``start_new_session`` makes the root PID the process-group ID.
            # Once the root has exited, this only reaches descendants owned by
            # this invocation; ESRCH means the group is already gone.
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except OSError as exc:
                return [f"owned process-group close failed: {exc}"]
        return []


def run_owned_command(
    command: Sequence[str],
    cwd: Path,
    timeout: float,
    stdout_path: Path,
    env: dict[str, str],
) -> dict[str, Any]:
    """Run one command while retaining all output and owning its descendants."""
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    timed_out = False
    cleanup_errors: list[str] = []
    owner: _OwnedProcess | None = None
    try:
        with stdout_path.open("wb") as stdout_stream:
            owner = _OwnedProcess(command, cwd, env, stdout_stream)
            try:
                returncode = owner.wait(timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                cleanup_errors.extend(owner.kill_tree())
                returncode = owner.process.returncode
                if returncode is None:
                    returncode = 124
    except (OSError, RunnerError) as exc:
        returncode = 127
        cleanup_errors.append(f"process start failed: {exc}")
    finally:
        if owner is not None:
            cleanup_errors.extend(owner.close())
    return {
        "returncode": returncode,
        "timed_out": timed_out,
        "cleanup_errors": cleanup_errors,
        "seconds": round(time.monotonic() - started, 3),
    }


def check_artifacts(output: Path, artifact_specs: Iterable[str]) -> list[dict[str, Any]]:
    """Resolve exact artifact paths under output and report existence and size."""
    output = output.resolve()
    checks: list[dict[str, Any]] = []
    for raw in artifact_specs:
        candidate = Path(raw).expanduser()
        if not candidate.is_absolute():
            candidate = output / candidate
        candidate = candidate.resolve(strict=False)
        if candidate != output and not candidate.is_relative_to(output):
            raise ValueError(f"evidence artifact is outside output directory: {raw}")
        exists = candidate.is_file()
        size = candidate.stat().st_size if exists else 0
        checks.append(
            {
                "path": candidate.relative_to(output).as_posix(),
                "exists": exists,
                "size": size,
                "empty": not exists or size == 0,
            }
        )
    return checks


def classify_run(
    returncode: int,
    timed_out: bool,
    stdout: str,
    engine_log: str,
    artifacts: list[dict[str, Any]],
    completion_marker: str = DEFAULT_COMPLETION_MARKER,
    engine_log_missing: bool = False,
    cleanup_errors: Sequence[str] | None = None,
) -> dict[str, Any]:
    """Classify one lane with no success fallback for incomplete evidence."""
    script_errors = _matching_lines(stdout, SCRIPT_ERROR_RE)
    engine_errors = _matching_lines(stdout + "\n" + engine_log, ENGINE_ERROR_RE)
    fail_markers = _matching_lines(stdout + "\n" + engine_log, FAIL_MARKER_RE)
    failures: list[str] = []
    if timed_out:
        failures.append("timeout")
    if returncode != 0:
        failures.append(f"nonzero return code: {returncode}")
    if engine_log_missing:
        failures.append("missing engine log")
    if script_errors:
        failures.append("script errors present")
    if engine_errors:
        failures.append("engine errors present")
    if fail_markers:
        failures.append("FAIL marker present")
    marker_found = bool(completion_marker and completion_marker in (stdout + "\n" + engine_log))
    if not marker_found:
        failures.append(f"missing completion marker: {completion_marker}")
    artifact_failures = [item for item in artifacts if not item["exists"] or item["size"] <= 0]
    if artifact_failures:
        failures.append("missing or empty evidence artifact")
    for error in cleanup_errors or []:
        failures.append(error)
    return {
        "passed": not failures,
        "returncode": returncode,
        "timed_out": timed_out,
        "script_errors": script_errors,
        "engine_errors": engine_errors,
        "fail_markers": fail_markers,
        "completion_marker_found": marker_found,
        "artifact_failures": artifact_failures,
        "failures": failures,
    }


def write_manifest(path: Path, manifest: dict[str, Any]) -> None:
    """Write JSON atomically so a killed runner never leaves a false manifest."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_verified_manifest(path: Path) -> dict[str, Any]:
    """Read back and verify the success contract of a runner manifest."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"manifest is not readable JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError("manifest root must be an object")
    if type(value.get("failures")) is not int or value.get("failures") != 0:
        raise ValueError("manifest failures must equal 0")
    if value.get("complete") is not True:
        raise ValueError("manifest is not complete")
    return value


def prepare_output(project: Path, output: Path) -> Path:
    """Delete and recreate exactly one safe, caller-selected output directory."""
    project = project.resolve()
    probe = output.expanduser()
    while True:
        if probe.is_symlink():
            raise ValueError("refusing to replace an output path containing a symlink")
        if probe == probe.parent:
            break
        probe = probe.parent
    target = output.resolve(strict=False)
    if target == project or project.is_relative_to(target):
        raise ValueError("output must not be the project directory or one of its parents")
    if target == Path(target.anchor):
        raise ValueError("refusing to replace a filesystem root")
    if target.exists() and not target.is_dir():
        raise ValueError("output exists and is not a directory")
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=False)
    return target


def git_sha(project: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(project), "rev-parse", "--verify", "HEAD"],
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        detail = (result.stderr or result.stdout).strip()
        raise RunnerError(f"could not determine git SHA: {detail or 'git failed'}")
    return result.stdout.strip()


def engine_version(engine: Path | str, project: Path, timeout: float) -> str:
    # Use the same owned-process path as a lane. A broken engine must not be
    # able to leave a version-probe child behind while the gate is failing.
    with tempfile.TemporaryDirectory(prefix="phase78-engine-version-") as temp:
        version_log = Path(temp) / "version.stdout.log"
        result = run_owned_command(
            [str(engine), "--version"],
            project,
            timeout,
            version_log,
            os.environ.copy(),
        )
        value = version_log.read_text(encoding="utf-8", errors="replace").strip()
    if result["timed_out"]:
        raise RunnerError("engine --version timed out")
    if result["returncode"] != 0:
        detail = value or "; ".join(result["cleanup_errors"])
        raise RunnerError(f"engine --version failed with rc={result['returncode']}: {detail}")
    if not value:
        raise RunnerError("engine --version returned no version")
    return value


def _resolve_engine(raw: str) -> Path | str:
    candidate = Path(raw).expanduser()
    if candidate.exists():
        return candidate.resolve()
    located = shutil.which(raw)
    if located:
        return Path(located).resolve()
    return raw


def _output_arg(project: Path, raw: str | None) -> Path:
    value = raw or ".verification/phase78"
    candidate = Path(value).expanduser()
    if not candidate.is_absolute():
        candidate = project / candidate
    return candidate


def _plan(
    engine: Path | str,
    project: Path,
    scripts: Sequence[str],
    output: Path,
    renderer: str,
    viewport: str,
    evidence: Sequence[str],
    completion_marker: str,
    extra_args: Sequence[str],
) -> dict[str, Any]:
    commands = []
    for index, script in enumerate(scripts, 1):
        stem = Path(script.removeprefix("res://")).stem
        engine_log = output / f"{index:03d}_{stem}.engine.log"
        commands.append(build_command(engine, project, script, engine_log, renderer, viewport, extra_args))
    return {
        "mode": "dry-run",
        "scripts": list(scripts),
        "commands": commands,
        "evidence": list(evidence),
        "completion_marker": completion_marker,
        "renderer": renderer,
        "viewport": viewport,
        "output": str(output),
    }


def run_suite(
    engine: Path | str,
    project: Path,
    scripts: Sequence[str],
    output: Path,
    evidence: Sequence[str],
    timeout: float = DEFAULT_TIMEOUT,
    renderer: str = DEFAULT_RENDERER,
    viewport: str = DEFAULT_VIEWPORT,
    completion_marker: str = DEFAULT_COMPLETION_MARKER,
    extra_args: Sequence[str] | None = None,
) -> tuple[dict[str, Any], Path]:
    """Run the explicit lane list and return the manifest and its path."""
    if not scripts:
        raise ValueError("at least one explicit script is required")
    if not evidence:
        raise ValueError("at least one explicit evidence artifact is required")
    if timeout <= 0:
        raise ValueError("timeout must be positive")
    if not completion_marker:
        raise ValueError("completion marker must not be empty")
    _validate_viewport(viewport)
    fresh_output = prepare_output(project, output)
    manifest_path = fresh_output / "manifest.json"
    failures: list[str] = []
    metadata: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "complete": False,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "project": str(project.resolve()),
        "output": str(fresh_output),
        "engine": str(engine),
        "engine_version_command": [str(engine), "--version"],
        "renderer": renderer,
        "viewport": viewport,
        "completion_marker": completion_marker,
        "scripts": [],
        "commands": [],
        "failures": 0,
        "failure_reasons": [],
    }
    try:
        try:
            metadata["git_sha"] = git_sha(project)
        except Exception as exc:
            failures.append(str(exc))
            metadata["git_sha"] = None
        try:
            metadata["engine_version"] = engine_version(engine, project, min(timeout, 30.0))
        except Exception as exc:
            failures.append(str(exc))
            metadata["engine_version"] = None

        if not failures:
            env = os.environ.copy()
            env["FXLAB_EVIDENCE_DIR"] = str(fresh_output)
            env["NRCU_PHASE78_EVIDENCE_DIR"] = str(fresh_output)
            env["NRCU_PHASE78_OUTPUT_DIR"] = str(fresh_output)
            env["NRCU_PHASE78_COMPLETION_MARKER"] = completion_marker
            for index, script in enumerate(scripts, 1):
                stem = Path(script.removeprefix("res://")).stem
                stdout_path = fresh_output / f"{index:03d}_{stem}.stdout.log"
                engine_log_path = fresh_output / f"{index:03d}_{stem}.engine.log"
                command = build_command(
                    engine,
                    project,
                    script,
                    engine_log_path,
                    renderer,
                    viewport,
                    extra_args,
                )
                result = run_owned_command(command, project, timeout, stdout_path, env)
                stdout = stdout_path.read_text(encoding="utf-8", errors="replace")
                engine_log_missing = not engine_log_path.is_file()
                engine_log = (
                    engine_log_path.read_text(encoding="utf-8", errors="replace")
                    if not engine_log_missing
                    else ""
                )
                classified = classify_run(
                    result["returncode"],
                    result["timed_out"],
                    stdout,
                    engine_log,
                    [],
                    completion_marker=completion_marker,
                    engine_log_missing=engine_log_missing,
                    cleanup_errors=result["cleanup_errors"],
                )
                script_result = {
                    "script": script,
                    "command": command,
                    "stdout_log": _relative_path(stdout_path, fresh_output),
                    "engine_log": _relative_path(engine_log_path, fresh_output),
                    "seconds": result["seconds"],
                    **classified,
                }
                metadata["scripts"].append(script_result)
                metadata["commands"].append(command)
                failures.extend(f"{script}: {reason}" for reason in classified["failures"])

        try:
            artifacts = check_artifacts(fresh_output, evidence)
        except Exception as exc:
            artifacts = []
            failures.append(str(exc))
        metadata["evidence"] = artifacts
        if artifacts:
            missing = [item["path"] for item in artifacts if item["empty"]]
            failures.extend(f"evidence missing or empty: {path}" for path in missing)
        else:
            failures.append("no evidence artifacts were verified")
    except Exception as exc:
        failures.append(f"runner exception: {exc}")
    metadata["complete"] = True
    metadata["failures"] = len(failures)
    metadata["failure_reasons"] = failures
    metadata["finished_utc"] = datetime.now(timezone.utc).isoformat()
    write_manifest(manifest_path, metadata)
    if metadata["failures"] == 0:
        try:
            read_verified_manifest(manifest_path)
        except ValueError as exc:
            metadata["complete"] = True
            metadata["failures"] = 1
            metadata["failure_reasons"] = [f"manifest verification failed: {exc}"]
            write_manifest(manifest_path, metadata)
    return metadata, manifest_path


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, help="Godot console executable or PATH command")
    parser.add_argument("--project", default=".", help="Godot project directory (default: current directory)")
    parser.add_argument("--script", dest="scripts", action="append", required=True, help="Explicit res:// GDScript; repeat for each lane")
    parser.add_argument("--evidence", action="append", default=[], help="Exact non-empty artifact path relative to the fresh output; repeatable")
    parser.add_argument("--output", help="Fresh output directory (default: PROJECT/.verification/phase78)")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="Seconds per script")
    parser.add_argument("--renderer", default=DEFAULT_RENDERER, help="Godot rendering method to record and pass")
    parser.add_argument("--viewport", default=DEFAULT_VIEWPORT, help="Viewport metadata and Godot resolution, e.g. 1280x720")
    parser.add_argument("--completion-marker", default=DEFAULT_COMPLETION_MARKER, help="Literal marker every script must emit")
    parser.add_argument("--extra-arg", dest="extra_args", action="append", default=[], help="Additional Godot argument; repeatable")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--list", action="store_true", help="Print the explicit plan without running Godot")
    modes.add_argument("--dry-run", action="store_true", help="Alias for --list")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    project = Path(args.project).expanduser().resolve()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if not args.completion_marker:
        parser.error("--completion-marker must not be empty")
    try:
        _validate_viewport(args.viewport)
        normalized = [normalize_script(project, raw) for raw in args.scripts]
        if len(set(normalized)) != len(normalized):
            raise ValueError("duplicate explicit scripts are not allowed")
        if args.renderer.strip() == "":
            raise ValueError("--renderer must not be empty")
        output = _output_arg(project, args.output)
        plan = _plan(
            args.engine,
            project,
            normalized,
            output,
            args.renderer,
            args.viewport,
            args.evidence,
            args.completion_marker,
            args.extra_args,
        )
    except ValueError as exc:
        parser.error(str(exc))
    if args.list or args.dry_run:
        print(json.dumps(plan, indent=2, sort_keys=True))
        return 0
    if not project.is_dir() or not (project / "project.godot").is_file():
        parser.error("--project must contain project.godot")
    if not args.evidence:
        parser.error("at least one --evidence is required for an executing run")
    if any(Path(item).name == "manifest.json" for item in args.evidence):
        parser.error("manifest.json is reserved for the runner manifest")
    engine = _resolve_engine(args.engine)
    if isinstance(engine, Path) and not engine.is_file():
        parser.error(f"engine executable not found: {args.engine}")
    try:
        manifest, manifest_path = run_suite(
            engine,
            project,
            normalized,
            output,
            args.evidence,
            timeout=args.timeout,
            renderer=args.renderer,
            viewport=args.viewport,
            completion_marker=args.completion_marker,
            extra_args=args.extra_args,
        )
    except (OSError, RunnerError, ValueError) as exc:
        parser.error(str(exc))
    print(
        json.dumps(
            {
                "manifest": str(manifest_path),
                "failures": manifest["failures"],
                "complete": manifest["complete"],
            },
            sort_keys=True,
        )
    )
    return 0 if manifest["failures"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
