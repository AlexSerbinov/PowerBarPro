#!/usr/bin/env python3
"""
Calibrate ONE app. Designed to be called by Claude Code sequentially.
Internal stabilization: 60s BEFORE + measurements + 30s AFTER.

Usage: python3 calibrate_one.py "AppName"
Returns JSON result to stdout, logs to stderr.
"""
import json, subprocess, signal, sys, time, os, datetime
import ctypes, ctypes.util, struct
from collections import defaultdict

STABILIZE_BEFORE = 60   # seconds to stabilize BEFORE (Claude just ran code)
STABILIZE_AFTER  = 30   # seconds after finishing (before Claude reads result)
BASELINE_SECS    = 40
POST_BASE_SECS   = 40
MAX_SETTLE_SECS  = 90
SETTLE_VARIANCE  = 4.0
SETTLE_WINDOW    = 15
DISCARD_INITIAL  = 20
EMA_ALPHA        = 0.12
MACPOW_INTERVAL  = 2000
RUSAGE_SAMPLE    = 5

libproc = ctypes.CDLL(ctypes.util.find_library('proc') or '/usr/lib/libproc.dylib')

def log(msg):
    ts = datetime.datetime.now().strftime('%H:%M:%S')
    print(f"[{ts}] {msg}", file=sys.stderr, flush=True)

def get_energy_nj(pid):
    buf = ctypes.create_string_buffer(1024)
    if libproc.proc_pid_rusage(pid, 6, buf) != 0: return None
    try: return struct.unpack_from('<Q', buf.raw, 16 + 40 * 8)[0]
    except: return None

def get_pids_for(name):
    r = subprocess.run(['ps', '-eo', 'pid,comm'], capture_output=True, text=True)
    pids = []
    for line in r.stdout.strip().split('\n')[1:]:
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            pname = parts[1].split('/')[-1]
            if name.lower() in pname.lower():
                pids.append(int(parts[0]))
    return pids

def measure_rusage(pids):
    snap = {}
    for pid in pids:
        e = get_energy_nj(pid)
        if e and e > 0: snap[pid] = e
    time.sleep(RUSAGE_SAMPLE)
    total = 0
    for pid, e1 in snap.items():
        e2 = get_energy_nj(pid)
        if e2 and e2 > e1: total += e2 - e1
    return total / 1e9 / RUSAGE_SAMPLE

def read_power(n_samples):
    proc = subprocess.Popen(
        ['macpow', '--json', '--interval', str(MACPOW_INTERVAL)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    readings = []
    buf, depth, num = '', 0, 0
    try:
        for line in proc.stdout:
            for ch in line:
                if ch == '{': depth += 1
                elif ch == '}': depth -= 1
                buf += ch
                if depth == 0 and buf.strip():
                    try:
                        d = json.loads(buf)
                        num += 1
                        if num >= 2:
                            readings.append(d.get('sys_power_w', 0))
                            if len(readings) >= n_samples:
                                proc.terminate(); proc.wait()
                                return readings
                    except: pass
                    buf = ''
    except: pass
    proc.terminate()
    try: proc.wait(timeout=5)
    except: proc.kill()
    return readings

def ema(r, alpha=EMA_ALPHA):
    if not r: return 0
    s = r[0]
    for v in r[1:]: s = s*(1-alpha) + v*alpha
    return s

def var_pct(v):
    if len(v) < 2: return 100
    m = sum(v)/len(v)
    if m < 0.01: return 100
    return ((sum((x-m)**2 for x in v)/len(v))**0.5/m)*100

def settle():
    proc = subprocess.Popen(
        ['macpow', '--json', '--interval', str(MACPOW_INTERVAL)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    buf, depth, num = '', 0, 0
    readings = []
    start = time.time()
    settled = False
    try:
        for line in proc.stdout:
            for ch in line:
                if ch == '{': depth += 1
                elif ch == '}': depth -= 1
                buf += ch
                if depth == 0 and buf.strip():
                    try:
                        d = json.loads(buf)
                        num += 1
                        if num >= 2:
                            elapsed = time.time() - start
                            readings.append(d.get('sys_power_w', 0))
                            if elapsed >= DISCARD_INITIAL:
                                w = int(SETTLE_WINDOW*1000/MACPOW_INTERVAL)
                                recent = readings[-max(1,w):]
                                v = var_pct(recent)
                                log(f"  settle {elapsed:.0f}s: {readings[-1]:.1f}W var={v:.1f}%")
                                if v < SETTLE_VARIANCE and len(recent) >= 3:
                                    settled = True
                            if settled or elapsed >= MAX_SETTLE_SECS:
                                proc.terminate(); proc.wait()
                                return settled
                    except: pass
                    buf = ''
            if settled or time.time()-start >= MAX_SETTLE_SECS: break
    except: pass
    proc.terminate()
    try: proc.wait(timeout=5)
    except: proc.kill()
    return settled

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 calibrate_one.py AppName", file=sys.stderr)
        sys.exit(1)

    target = sys.argv[1]
    log(f"=== Calibrating: {target} ===")

    pids = get_pids_for(target)
    if not pids:
        log(f"ERROR: {target} not found")
        print(json.dumps({"error": f"{target} not found"}))
        sys.exit(1)

    log(f"Found {len(pids)} PIDs: {pids[:10]}")

    # STABILIZE BEFORE
    log(f"Stabilizing {STABILIZE_BEFORE}s (Claude goes idle)...")
    time.sleep(STABILIZE_BEFORE)

    # Measure rusage
    log(f"Measuring proc_pid_rusage ({RUSAGE_SAMPLE}s)...")
    rusage_w = measure_rusage(pids)
    log(f"rusage: {rusage_w*1000:.1f} mW")

    # Baseline
    n = BASELINE_SECS*1000//MACPOW_INTERVAL
    log(f"Baseline ({BASELINE_SECS}s)...")
    base_r = read_power(n)
    base = ema(base_r)
    base_v = var_pct(base_r[-5:]) if len(base_r)>=5 else 99
    log(f"Baseline: {base:.2f}W (var {base_v:.1f}%)")

    # Kill
    log(f"Killing {target}...")
    for pid in pids:
        try: os.kill(pid, signal.SIGTERM)
        except: pass
    time.sleep(2)
    for pid in pids:
        try: os.kill(pid, signal.SIGKILL)
        except: pass

    # Settle
    log("Settling...")
    settle()

    # Post-baseline
    log(f"Post-baseline ({POST_BASE_SECS}s)...")
    post_r = read_power(POST_BASE_SECS*1000//MACPOW_INTERVAL)
    post = ema(post_r)
    post_v = var_pct(post_r[-5:]) if len(post_r)>=5 else 99
    log(f"Post: {post:.2f}W (var {post_v:.1f}%)")

    # Compute
    delta = base - post
    coeff = delta / rusage_w if rusage_w > 0.001 else 0

    result = {
        'app': target,
        'coefficient': round(coeff, 2),
        'baseline_w': round(base, 3),
        'post_w': round(post, 3),
        'delta_mw': round(delta*1000, 1),
        'rusage_mw': round(rusage_w*1000, 2),
        'reliable': 0.5 < coeff < 100 and delta > 0,
        'timestamp': datetime.datetime.now().isoformat(),
    }

    log(f"RESULT: delta={delta*1000:.0f}mW, rusage={rusage_w*1000:.1f}mW, coeff={coeff:.1f}x")
    log(f"{'RELIABLE' if result['reliable'] else 'UNRELIABLE'}")

    # STABILIZE AFTER (so Claude's next action doesn't pollute)
    log(f"Post-stabilization {STABILIZE_AFTER}s...")
    time.sleep(STABILIZE_AFTER)

    # Output JSON to stdout (Claude reads this)
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
