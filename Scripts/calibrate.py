#!/usr/bin/env python3
"""
PowerBarPro Calibration Tool

Measures the real power impact of an app by comparing system power
before and after terminating it. Produces a calibration coefficient
that corrects proc_pid_rusage underestimation.

Usage:
  python3 calibrate.py                    # Interactive — choose app to calibrate
  python3 calibrate.py "Telegram"         # Calibrate specific app
  python3 calibrate.py --list             # Just show current apps and power

How it works:
  1. Wait 30s for Claude Code / system to stabilize
  2. Measure baseline system power (30s, EMA smoothed)
  3. Measure target app's proc_pid_rusage energy
  4. Kill target app (SIGTERM)
  5. Wait for system to settle (up to 60s, variance <5%)
  6. Measure post-baseline system power (30s)
  7. Coefficient = (baseline - post) / rusage_power

IMPORTANT: Don't touch the computer during calibration!
           Close unnecessary apps before starting.
"""
import json, subprocess, signal, sys, time, os
import ctypes, ctypes.util, struct
from collections import defaultdict

# ── Config ──
STABILIZE_WAIT   = 30   # seconds to wait before starting (for Claude to stop)
BASELINE_SECS    = 30   # seconds of baseline measurement
POST_BASE_SECS   = 30   # seconds of post-baseline measurement
MAX_SETTLE_SECS  = 60   # max time to wait for settling
SETTLE_VARIANCE  = 5.0  # % variance threshold for "settled"
SETTLE_WINDOW    = 10   # seconds of window for variance check
DISCARD_INITIAL  = 15   # seconds to discard after kill (thermal inertia)
EMA_ALPHA        = 0.15 # EMA smoothing factor
MACPOW_INTERVAL  = 2000 # macpow sample interval ms

# ── Colors ──
class C:
    R = "\033[0m"; B = "\033[1m"; D = "\033[2m"
    RED = "\033[91m"; GRN = "\033[92m"; YLW = "\033[93m"; CYN = "\033[96m"

# ── proc_pid_rusage ──
libproc = ctypes.CDLL(ctypes.util.find_library('proc') or '/usr/lib/libproc.dylib')

def get_energy_nj(pid):
    buf = ctypes.create_string_buffer(1024)
    if libproc.proc_pid_rusage(pid, 6, buf) != 0:
        return None
    try:
        return struct.unpack_from('<Q', buf.raw, 16 + 40 * 8)[0]
    except:
        return None

def get_pids_by_name():
    """Get all PIDs grouped by process name."""
    r = subprocess.run(['ps', '-eo', 'pid,comm'], capture_output=True, text=True)
    by_name = defaultdict(list)
    for line in r.stdout.strip().split('\n')[1:]:
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            name = parts[1].split('/')[-1][:30]
            by_name[name].append(int(parts[0]))
    return dict(by_name)

def measure_process_power(name, pids, duration=3):
    """Measure proc_pid_rusage power for a process over duration seconds."""
    snap1 = {}
    for pid in pids:
        e = get_energy_nj(pid)
        if e and e > 0:
            snap1[pid] = e

    time.sleep(duration)

    total_nj = 0
    for pid in snap1:
        e = get_energy_nj(pid)
        if e and e > snap1[pid]:
            total_nj += e - snap1[pid]

    return total_nj / 1e9 / duration  # watts

# ── macpow JSON stream reader ──
def read_macpow_samples(interval_ms, count):
    """Read N samples from macpow, return list of sys_power_w values."""
    proc = subprocess.Popen(
        ['macpow', '--json', '--interval', str(interval_ms)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )

    readings = []
    buf = ''
    depth = 0
    sample_num = 0

    try:
        for line in proc.stdout:
            for ch in line:
                if ch == '{': depth += 1
                elif ch == '}': depth -= 1
                buf += ch
                if depth == 0 and buf.strip():
                    try:
                        d = json.loads(buf)
                        sample_num += 1
                        if sample_num >= 2:  # skip warmup
                            readings.append(d.get('sys_power_w', 0))
                            if len(readings) >= count:
                                proc.terminate()
                                proc.wait()
                                return readings
                    except:
                        pass
                    buf = ''
    except:
        pass

    proc.terminate()
    proc.wait()
    return readings

def ema_smooth(readings, alpha=EMA_ALPHA):
    if not readings:
        return 0
    smoothed = readings[0]
    for v in readings[1:]:
        smoothed = smoothed * (1 - alpha) + v * alpha
    return smoothed

def variance_pct(values):
    if len(values) < 2:
        return 100
    mean = sum(values) / len(values)
    if mean < 0.01:
        return 100
    var = sum((v - mean)**2 for v in values) / len(values)
    return (var**0.5 / mean) * 100

def print_power_bar(watts, max_w=20, width=25):
    filled = min(int(watts / max_w * width), width)
    color = C.GRN if watts < 5 else (C.YLW if watts < 15 else C.RED)
    return color + "█" * filled + C.D + "░" * (width - filled) + C.R

# ── Main calibration ──
def main():
    target_name = None
    if len(sys.argv) > 1:
        if sys.argv[1] == '--list':
            show_current_state()
            return
        target_name = sys.argv[1]

    signal.signal(signal.SIGINT, lambda *_: (print(f"\n{C.R}Cancelled."), sys.exit(0)))

    print(f"\n{C.B}{C.CYN}  PowerBarPro Calibration Tool{C.R}")
    print(f"{C.D}{'─' * 50}{C.R}")

    if not target_name:
        show_current_state()
        target_name = input(f"\n{C.B}Enter app name to calibrate:{C.R} ").strip()
        if not target_name:
            print("No app specified. Exiting.")
            return

    pids_by_name = get_pids_by_name()
    matching = {k: v for k, v in pids_by_name.items() if target_name.lower() in k.lower()}

    if not matching:
        print(f"{C.RED}App '{target_name}' not found in running processes.{C.R}")
        return

    # Pick best match
    if len(matching) > 1:
        print(f"\nMultiple matches:")
        for i, (name, pids) in enumerate(matching.items()):
            print(f"  [{i}] {name} ({len(pids)} PIDs)")
        choice = input("Choose [0]: ").strip()
        idx = int(choice) if choice.isdigit() else 0
        items = list(matching.items())
        target_name, target_pids = items[min(idx, len(items)-1)]
    else:
        target_name, target_pids = list(matching.items())[0]

    print(f"\n{C.B}Target:{C.R} {target_name} ({len(target_pids)} PIDs: {target_pids})")

    # Phase 0: Stabilize
    print(f"\n{C.B}Phase 0: Stabilizing ({STABILIZE_WAIT}s){C.R}")
    print(f"{C.D}  Don't touch anything! Waiting for Claude Code to go idle...{C.R}")
    for i in range(STABILIZE_WAIT):
        remaining = STABILIZE_WAIT - i
        print(f"\r  Stabilizing... {remaining}s remaining  ", end='', flush=True)
        time.sleep(1)
    print(f"\r  {C.GRN}✓ Stabilized{C.R}                        ")

    # Phase 1: Measure proc_pid_rusage for target
    print(f"\n{C.B}Phase 1: Measuring proc_pid_rusage for {target_name} (5s){C.R}")
    rusage_watts = measure_process_power(target_name, target_pids, duration=5)
    print(f"  proc_pid_rusage: {rusage_watts*1000:.1f} mW")

    # Phase 2: Baseline
    n_baseline = BASELINE_SECS * 1000 // MACPOW_INTERVAL
    print(f"\n{C.B}Phase 2: Measuring baseline ({BASELINE_SECS}s, {n_baseline} samples){C.R}")
    print(f"{C.D}  System power WITH {target_name} running...{C.R}")

    baseline_readings = read_macpow_samples(MACPOW_INTERVAL, n_baseline)
    baseline_avg = sum(baseline_readings) / len(baseline_readings) if baseline_readings else 0
    baseline_ema = ema_smooth(baseline_readings)
    baseline_var = variance_pct(baseline_readings[-5:]) if len(baseline_readings) >= 5 else 99

    print(f"  Baseline: {baseline_ema:.2f}W (avg: {baseline_avg:.2f}W, var: {baseline_var:.1f}%)")
    print(f"  {print_power_bar(baseline_ema)}")

    # Phase 3: Kill target
    print(f"\n{C.B}Phase 3: Terminating {target_name}{C.R}")
    for pid in target_pids:
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"  Sent SIGTERM to PID {pid}")
        except ProcessLookupError:
            print(f"  PID {pid} already gone")
        except PermissionError:
            print(f"  {C.RED}Permission denied for PID {pid}{C.R}")

    # Phase 4: Settle
    print(f"\n{C.B}Phase 4: Waiting for system to settle (up to {MAX_SETTLE_SECS}s){C.R}")
    print(f"{C.D}  Discarding first {DISCARD_INITIAL}s (thermal inertia)...{C.R}")

    settle_start = time.time()
    settle_readings = []
    settle_proc = subprocess.Popen(
        ['macpow', '--json', '--interval', str(MACPOW_INTERVAL)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )

    buf = ''
    depth = 0
    sample_num = 0
    settled = False

    try:
        for line in settle_proc.stdout:
            for ch in line:
                if ch == '{': depth += 1
                elif ch == '}': depth -= 1
                buf += ch
                if depth == 0 and buf.strip():
                    try:
                        d = json.loads(buf)
                        sample_num += 1
                        if sample_num >= 2:
                            elapsed = time.time() - settle_start
                            power = d.get('sys_power_w', 0)
                            settle_readings.append(power)

                            if elapsed < DISCARD_INITIAL:
                                print(f"\r  [{elapsed:.0f}s] Discarding: {power:.1f}W   ", end='', flush=True)
                            else:
                                recent = settle_readings[-max(1, int(SETTLE_WINDOW * 1000 / MACPOW_INTERVAL)):]
                                var = variance_pct(recent)
                                print(f"\r  [{elapsed:.0f}s] Power: {power:.1f}W  Variance: {var:.1f}%  ", end='', flush=True)

                                if var < SETTLE_VARIANCE and len(recent) >= 3:
                                    print(f"\n  {C.GRN}✓ Settled! Variance {var:.1f}% < {SETTLE_VARIANCE}%{C.R}")
                                    settled = True

                            if settled or elapsed >= MAX_SETTLE_SECS:
                                if not settled:
                                    print(f"\n  {C.YLW}⚠ Timeout reached. Proceeding anyway.{C.R}")
                                settle_proc.terminate()
                                settle_proc.wait()
                                break
                    except:
                        pass
                    buf = ''
            if settled or (time.time() - settle_start) >= MAX_SETTLE_SECS:
                break
    except:
        pass

    settle_proc.terminate()
    try:
        settle_proc.wait(timeout=3)
    except:
        settle_proc.kill()

    # Phase 5: Post-baseline
    n_post = POST_BASE_SECS * 1000 // MACPOW_INTERVAL
    print(f"\n{C.B}Phase 5: Measuring post-baseline ({POST_BASE_SECS}s, {n_post} samples){C.R}")
    print(f"{C.D}  System power WITHOUT {target_name}...{C.R}")

    post_readings = read_macpow_samples(MACPOW_INTERVAL, n_post)
    post_avg = sum(post_readings) / len(post_readings) if post_readings else 0
    post_ema = ema_smooth(post_readings)
    post_var = variance_pct(post_readings[-5:]) if len(post_readings) >= 5 else 99

    print(f"  Post-baseline: {post_ema:.2f}W (avg: {post_avg:.2f}W, var: {post_var:.1f}%)")
    print(f"  {print_power_bar(post_ema)}")

    # Phase 6: Compute
    delta = baseline_ema - post_ema
    coefficient = delta / rusage_watts if rusage_watts > 0.001 else 0

    print(f"\n{C.B}{C.CYN}{'═' * 50}{C.R}")
    print(f"{C.B}  CALIBRATION RESULTS{C.R}")
    print(f"{C.D}{'─' * 50}{C.R}")
    print(f"  App:              {target_name}")
    print(f"  Baseline:         {baseline_ema:.2f}W (with app)")
    print(f"  Post-baseline:    {post_ema:.2f}W (without app)")
    print(f"  {C.B}Delta (real):     {delta*1000:.0f} mW{C.R}")
    print(f"  proc_pid_rusage:  {rusage_watts*1000:.1f} mW")
    print(f"  {C.B}{C.CYN}Coefficient:      {coefficient:.1f}x{C.R}")
    print(f"{C.D}{'─' * 50}{C.R}")

    if coefficient > 0.5 and coefficient < 100:
        print(f"  {C.GRN}✓ Reliable calibration{C.R}")
        print(f"  Meaning: real power ≈ proc_pid_rusage × {coefficient:.1f}")
        print(f"  Example: {rusage_watts*1000:.0f}mW × {coefficient:.1f} = {rusage_watts*coefficient*1000:.0f}mW (≈{delta*1000:.0f}mW measured)")
    else:
        print(f"  {C.YLW}⚠ Coefficient out of reasonable range{C.R}")
        if delta < 0:
            print(f"  System power INCREASED after kill — other processes may have reacted")
        elif rusage_watts < 0.001:
            print(f"  proc_pid_rusage too small to measure reliably")

    # Save results
    result = {
        'app': target_name,
        'coefficient': round(coefficient, 2),
        'baseline_w': round(baseline_ema, 2),
        'post_baseline_w': round(post_ema, 2),
        'delta_mw': round(delta * 1000, 1),
        'rusage_mw': round(rusage_watts * 1000, 1),
        'baseline_variance_pct': round(baseline_var, 1),
        'post_variance_pct': round(post_var, 1),
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
    }

    results_file = os.path.expanduser('~/Desktop/projects/personal/PowerBarPro/calibration_results.json')
    existing = []
    if os.path.exists(results_file):
        with open(results_file) as f:
            existing = json.load(f)
    existing.append(result)
    with open(results_file, 'w') as f:
        json.dump(existing, f, indent=2)
    print(f"\n  Results saved to: {results_file}")

    print(f"\n{C.D}Tip: Run again with other apps to build a full calibration profile.{C.R}")
    print(f"{C.D}Global coefficient = median of all per-app coefficients.{C.R}\n")


def show_current_state():
    """Show current running apps and their power."""
    print(f"\n{C.B}Current running apps (proc_pid_rusage, 3s sample):{C.R}")

    pids_by_name = get_pids_by_name()

    # Snapshot 1
    snap1 = {}
    for name, pids in pids_by_name.items():
        for pid in pids:
            e = get_energy_nj(pid)
            if e and e > 0:
                snap1[pid] = (name, e)

    time.sleep(3)

    # Snapshot 2
    results = defaultdict(lambda: {'watts': 0, 'pids': 0})
    for pid, (name, e1) in snap1.items():
        e2 = get_energy_nj(pid)
        if e2 and e2 > e1:
            w = (e2 - e1) / 1e9 / 3.0
            results[name]['watts'] += w
            results[name]['pids'] += 1

    sorted_r = sorted(results.items(), key=lambda x: x[1]['watts'], reverse=True)
    print(f"  {'App':<30} {'rusage mW':>10} {'PIDs':>5}")
    print(f"  {'-'*48}")
    for name, data in sorted_r[:20]:
        if data['watts'] > 0.0005:
            bar = print_power_bar(data['watts'] * 1000, max_w=200, width=15)
            print(f"  {name:<30} {data['watts']*1000:>8.1f} mW  x{data['pids']}  {bar}")


if __name__ == '__main__':
    main()
