"""Run the MATLAB probes headless, each in a new MATLAB, longest first.

Each probe runs in a MATLAB started with -noFigureWindows -batch,
OM_APP_HEADLESS=1 and an empty MATLAB_PREFDIR of its own (MATLAB reads it at
start-up), through tests/run_probes_worker.m. Up to --workers MATLABs run at
the same time. The summary counts the PASS, FAIL and SKIP lines of each probe.

Usage:
    python tests/run_probes.py --logs <new log folder> [--matlab <matlab>]
        [--workers 2] [--timings tests/probe_timings.tsv] [--reuse-matlab]
        [--min-ram-gb 8] [--min-free-gb <folder>=<GB> ...] [name ...]

MATLAB comes from --matlab, else the OM_MATLAB environment variable, else
"matlab" on the PATH. With no names, every tests/probe_*.m and smoke_*.m is
run.

--reuse-matlab (off by default) lets one MATLAB run probe after probe, which
saves its start-up time. Between probes the worker puts MATLAB's state back
(see run_probes_worker.m) and compares it with the start; when something is
left, the next probe gets a new MATLAB. One part of the reset is weaker than
a new MATLAB: a class whose deleted objects (the app's, for example) are
still referenced cannot be unloaded with clear classes, so the worker falls
back to clear functions and the old class definition stays loaded. The
probes in ISOLATED always get a MATLAB of their own. Before a job starts, the
runner waits (it never fails) until free memory (--min-ram-gb, default the
OM_PROBES_MIN_RAM_GB environment variable, else 8 GB) and the free space of
each --min-free-gb folder (default: the temporary folder, 9 GB) are at their
floor; the first wait is printed on the console, every wait in waits.txt.
Each MATLAB uses the number of computational threads MATLAB chooses for the
machine.
The data variables the probes read (OM_REDO_DS and so on) are passed on from
the environment. Writes <logs>/<job>.log for each job and <logs>/summary.tsv:
job, status, seconds, passed, failed, skipped, worker, verdict.
"""
from __future__ import annotations

import argparse
import csv
import ctypes
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

TESTS = Path(__file__).resolve().parent
REPO = TESTS.parent

# Probes that do not run in a shared MATLAB, and why
ISOLATED = {
    "probe_fresh_and_restore_journeys":
        "checks the MATLAB process's child processes; in a shared MATLAB those are not the "
        "probe's alone",
}


def find_matlab(arg: str | None) -> str:
    """The MATLAB executable: --matlab, OM_MATLAB, or matlab on the PATH."""
    for cand in (arg, os.environ.get("OM_MATLAB"), shutil.which("matlab")):
        if cand and (Path(cand).is_file() or shutil.which(cand)):
            return cand
    sys.exit("MATLAB not found: pass --matlab or set OM_MATLAB.")


def free_ram_gb() -> float | None:
    """Free physical memory in GB, or None when it cannot be read here."""
    try:
        if platform.system() == "Windows":
            class Mem(ctypes.Structure):
                _fields_ = [("len", ctypes.c_ulong), ("load", ctypes.c_ulong),
                            ("total", ctypes.c_ulonglong), ("avail", ctypes.c_ulonglong),
                            ("tpage", ctypes.c_ulonglong), ("apage", ctypes.c_ulonglong),
                            ("tvirt", ctypes.c_ulonglong), ("avirt", ctypes.c_ulonglong),
                            ("aext", ctypes.c_ulonglong)]
            m = Mem()
            m.len = ctypes.sizeof(Mem)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
            return m.avail / 1024 ** 3
        if Path("/proc/meminfo").is_file():
            for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
                if line.startswith("MemAvailable:"):
                    return int(line.split()[1]) / 1024 ** 2
        if platform.system() == "Darwin":
            out = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
            page = int(re.search(r"page size of (\d+)", out).group(1))
            pages = sum(int(re.search(rf"{k}:\s+(\d+)", out).group(1)) for k in ("Pages free", "Pages inactive"))
            return pages * page / 1024 ** 3
    except (OSError, AttributeError, ValueError):
        pass
    return None


def kill_tree(proc: subprocess.Popen) -> None:
    """Stop a MATLAB this runner started, with its children (matlab starts a second process)."""
    if proc.poll() is not None:
        return
    if platform.system() == "Windows":
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    proc.wait()


def leftover_copies(job: str, since: float) -> list[Path]:
    """Remove the scratch copies (tests/helpers/om_redo_copy.m: <tempdir>/tp..._<probe>) that a
    MATLAB stopped by a time-out or a crash made for job and could not remove itself."""
    name = job
    tmp = Path(os.environ.get("TMPDIR") or os.environ.get("TEMP") or os.environ.get("TMP") or tempfile.gettempdir())
    gone = []
    for d in tmp.glob(f"tp*_{name}"):
        if d.is_dir() and d.stat().st_mtime >= since - 5:
            shutil.rmtree(d, ignore_errors=True)
            gone.append(d)
    return gone


def counts(text: str) -> tuple[int, int, int, str]:
    """Passed, failed and skipped checks from a probe log, and its verdict lines."""
    res = re.findall(r"(?:RESULT:|^\S+:)\s*(\d+) passed, (\d+) (?:failed|required)", text, re.M)
    if res:
        passed, failed = (int(x) for x in res[-1])
    else:                                           # lines "PASS ...", "U1 PASS ..." or "name PASS"
        passed = len(re.findall(r"^\s*(?:\S+\s+)?PASS\b", text, re.M))
        failed = len(re.findall(r"^\s*(?:\S+\s+)?FAIL\b", text, re.M))
    skipped = len(re.findall(r"^(?:PROBE_)?SKIP(?:_NONPASS)?\b", text, re.M))
    verdict = re.findall(r"PROBE_OK[^\n]*|PROBE_FAIL[^\n]*|RESULT:[^\n]*|RESET_INCOMPLETE[^\n]*|SHARED_COPY_CHANGED[^\n]*", text)
    return passed, failed, skipped, " | ".join(verdict[-3:])


class Worker:
    """One MATLAB serving jobs from its queue folder."""

    def __init__(self, k: int, args, env: dict):
        self.k = k
        self.queue = Path(args.logs) / "workers" / f"w{k}_{uuid.uuid4().hex[:6]}"
        self.queue.mkdir(parents=True)
        pref = self.queue / "prefs"                # a new empty preference folder per MATLAB
        pref.mkdir()
        wenv = dict(env, OM_APP_HEADLESS="1", MATLAB_PREFDIR=str(pref))
        tests = TESTS.as_posix().replace("'", "''")
        q = self.queue.as_posix().replace("'", "''")
        cmd = f"addpath('{tests}'); run_probes_worker('{q}')"
        self.out = (self.queue / "matlab_output.txt").open("w", encoding="utf-8", errors="replace")
        self.proc = subprocess.Popen([args.matlab, "-noFigureWindows", "-batch", cmd], stdout=self.out,
                                     stderr=subprocess.STDOUT, env=wenv, cwd=str(self.queue),
                                     start_new_session=platform.system() != "Windows")
        self.job = None
        self.single = False                        # True: this MATLAB runs one job only
        self.seq = 0
        self.t0 = 0.0
        self.jobs_done = 0

    def give(self, job: str, log: Path) -> None:
        self.seq += 1
        self.job, self.t0 = job, time.time()
        tmp = self.queue / "next.tmp"
        tmp.write_text(f"{self.seq}\t{job}\t{log}", encoding="utf-8")
        os.replace(tmp, self.queue / "next.txt")   # whole, never half a line

    def result(self) -> dict | None:
        p = self.queue / f"result_{self.seq}.json"
        if p.is_file():
            return json.loads(p.read_text(encoding="utf-8"))
        return None

    def stop(self) -> None:
        if self.proc.poll() is None:
            tmp = self.queue / "next.tmp"
            tmp.write_text("STOP", encoding="utf-8")
            os.replace(tmp, self.queue / "next.txt")
            try:
                self.proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                kill_tree(self.proc)
        self.out.close()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("--logs", required=True)
    ap.add_argument("--matlab")
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("--timings", default=str(TESTS / "probe_timings.tsv"))
    ap.add_argument("--reuse-matlab", action="store_true",
                    help="let one MATLAB run several probes, with a reset between them (see above)")
    ap.add_argument("--timeout", type=float, default=2400, help="seconds per job")
    ap.add_argument("--max-jobs-per-worker", type=int, default=30)
    ap.add_argument("--min-ram-gb", type=float, default=float(os.environ.get("OM_PROBES_MIN_RAM_GB") or 8),
                    help="free memory (GB) to wait for before a job starts (default: OM_PROBES_MIN_RAM_GB, else 8)")
    ap.add_argument("--min-free-gb", action="append", default=[], metavar="FOLDER=GB")
    args = ap.parse_args()
    args.matlab = find_matlab(args.matlab)
    logs = Path(args.logs).resolve()
    logs.mkdir(parents=True, exist_ok=True)
    args.logs = str(logs)
    floors = [(Path(f.rpartition("=")[0]), float(f.rpartition("=")[2])) for f in args.min_free_gb] or \
        [(Path(tempfile.gettempdir()), 9.0)]

    names = args.names or sorted(p.stem for p in TESTS.glob("probe_*.m")) + \
        sorted(p.stem for p in TESTS.glob("smoke_*.m"))
    jobs = list(names)
    timing = {}
    if Path(args.timings).is_file():
        for row in csv.reader(Path(args.timings).open(encoding="utf-8"), delimiter="\t"):
            if len(row) >= 2 and row[1].replace(".", "", 1).isdigit():
                timing[row[0]] = float(row[1])
    jobs.sort(key=lambda j: -timing.get(j, 60.0))
    env = dict(os.environ)
    rows, workers, free_slots = [], [], list(range(args.workers))
    waits = logs / "waits.txt"
    not_before = [0.0]                              # after a failed check, look again 30 s later
    told = [False]                                  # the first wait is said on the console too

    def ready() -> bool:
        if time.time() < not_before[0]:
            return False
        ram = free_ram_gb()
        low = [f"{p} {shutil.disk_usage(p).free / 1024 ** 3:.1f} GB" for p, gb in floors
               if shutil.disk_usage(p).free / 1024 ** 3 < gb]
        if (ram is not None and ram < args.min_ram_gb) or low:
            line = (f"{time.strftime('%H:%M:%S')} waiting: RAM {ram if ram is None else round(ram, 1)} GB "
                    f"{'; '.join(low)}")
            with waits.open("a", encoding="utf-8") as f:
                f.write(line + "\n")
            if not told[0]:
                print(f"{line} (floors: RAM {args.min_ram_gb:g} GB; "
                      f"{', '.join(f'{p} {gb:g} GB' for p, gb in floors)}); waiting, see waits.txt", flush=True)
                told[0] = True
            not_before[0] = time.time() + 30
            return False
        return True

    def record(w: Worker, status: str, seconds: float) -> None:
        text = (logs / f"{w.job}.log").read_text(encoding="utf-8", errors="replace") \
            if (logs / f"{w.job}.log").is_file() else ""
        p, f, s, verdict = counts(text)
        rows.append([w.job, status, f"{seconds:.0f}", p, f, s, w.k, verdict])
        with (logs / "summary.tsv").open("w", encoding="utf-8", newline="") as fh:
            out = csv.writer(fh, delimiter="\t")
            out.writerow(["job", "status", "sec", "passed", "failed", "skipped", "worker", "verdict"])
            out.writerows(rows)
        print(f"{time.strftime('%H:%M:%S')} {status:8s} {w.job} {seconds:.0f} s  {p} passed, {f} failed",
              flush=True)

    t_start = time.time()
    while jobs or workers:
        # Results, crashes and time-outs of the running workers
        for w in list(workers):
            if w.job is None:
                continue
            r = w.result()
            dead = w.proc.poll() is not None
            if r is not None:
                record(w, r["status"], r["seconds"])
                w.jobs_done += 1
                w.job = None
                single = not args.reuse_matlab or w.single
                if r.get("recycle") or single or w.jobs_done >= args.max_jobs_per_worker or not jobs:
                    w.stop()
                    workers.remove(w)
                    free_slots.append(w.k)
            elif dead or time.time() - w.t0 > args.timeout:
                status = "CRASH" if dead else "TIMEOUT"
                kill_tree(w.proc)
                w.out.flush()
                log = logs / f"{w.job}.log"
                with log.open("a", encoding="utf-8") as fh:   # what MATLAB printed, for the reason
                    fh.write(f"\n{status}; the worker's output:\n")
                    fh.write((w.queue / "matlab_output.txt").read_text(encoding="utf-8", errors="replace")[-4000:])
                    for d in leftover_copies(w.job, w.t0):
                        fh.write(f"\nremoved the scratch copy left by the stopped MATLAB: {d}\n")
                record(w, status, time.time() - w.t0)
                w.out.close()
                workers.remove(w)
                free_slots.append(w.k)
        # Idle shared workers take the next shared job; free slots start a MATLAB
        for w in [w for w in workers if w.job is None]:
            nxt = next((j for j in jobs if j not in ISOLATED), None)
            if nxt is None:
                w.stop()
                workers.remove(w)
                free_slots.append(w.k)
            elif ready():
                jobs.remove(nxt)
                w.give(nxt, logs / f"{nxt}.log")
        while free_slots and jobs and ready():
            job = jobs.pop(0)
            w = Worker(free_slots.pop(0), args, env)
            w.single = job in ISOLATED
            workers.append(w)
            w.give(job, logs / f"{job}.log")
            time.sleep(5)                           # stagger the MATLAB start-ups
        time.sleep(1)
    bad = [r for r in rows if r[1] != "ok" or int(r[4]) > 0]
    print(f"done: {len(rows)} jobs in {time.time() - t_start:.0f} s, {len(bad)} not ok", flush=True)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
