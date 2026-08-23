#!/usr/bin/env python3
"""
PowerBarPro Overnight Calibration

Fully automatic calibration — run before sleep, get results in the morning.
Finds all non-critical apps, calibrates each one by killing it and measuring
the system power delta.

Usage:
  python3 calibrate_overnight.py              # Calibrate all apps
  python3 calibrate_overnight.py --dry-run    # Show what would be calibrated (no killing)

Results saved to: ~/Desktop/projects/personal/PowerBarPro/calibration_results.json
"""
import json, subprocess, signal, sys, time, os, datetime
import ctypes, ctypes.util, struct
from collections import defaultdict

# ── Config ──
STABILIZE_WAIT    = 45   # initial stabilization (wait for Claude to fully stop)
BASELINE_SECS     = 40   # baseline measurement per app
POST_BASE_SECS    = 40   # post-baseline measurement
MAX_SETTLE_SECS   = 90   # max settle wait (longer = more reliable)
SETTLE_VARIANCE   = 4.0  # stricter variance for overnight (we have time)
SETTLE_WINDOW     = 15   # seconds
DISCARD_INITIAL   = 20   # thermal discard
BETWEEN_APPS_WAIT = 30   # wait between calibrations for system to re-stabilize
EMA_ALPHA         = 0.12
MACPOW_INTERVAL   = 2000
MIN_POWER_MW      = 1.0  # skip apps using less than this (too small to measure)
RUSAGE_SAMPLE_SEC = 5    # how long to measure rusage

# Apps that must NEVER be killed
PROTECTED_APPS = {
    'kernel_task', 'launchd', 'WindowServer', 'loginwindow', 'Dock',
    'SystemUIServer', 'Finder', 'cfprefsd', 'distnoted', 'mds', 'mds_stores',
    'coreduetd', 'CoreServicesUIAgent', 'notifyd', 'opendirectoryd',
    'powerd', 'UserEventAgent', 'sharingd', 'cloudd', 'nsurlsessiond',
    'logd', 'syslogd', 'mediaremoted', 'coreaudiod', 'bluetoothd',
    'airportd', 'wifid', 'symptomsd', 'timed', 'CommCenter',
    'trustd', 'securityd', 'sandboxd', 'dasd', 'aned',
    # Also protect our own tools
    'macpow', 'macmon', 'PowerBar', 'PowerBarPro', 'python3', 'Python',
    'Terminal', 'iTerm2', 'ssh', 'sshd', 'caffeinate',
    # Protect Claude Code environment
    'claude', 'Claude', 'node', 'Code Helper', 'zsh', 'bash',
    # Desktop apps to keep
    'Amphetamine',
}

RESULTS_FILE = os.path.expanduser(
    '~/Desktop/projects/personal/PowerBarPro/calibration_results.json'
)
LOG_FILE = os.path.expanduser(
    '~/Desktop/projects/personal/PowerBarPro/calibration_log.txt'
)

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
    r = subprocess.run(['ps', '-eo', 'pid,comm'], capture_output=True, text=True)
    by_name = defaultdict(list)
    for line in r.stdout.strip().split('\n')[1:]:
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            name = parts[1].split('/')[-1][:40]
            by_name[name].append(int(parts[0]))
    return dict(by_name)

def measure_rusage(pids, duration=RUSAGE_SAMPLE_SEC):
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
    return total_nj / 1e9 / duration

def read_macpow_power(n_samples):
    proc = subprocess.Popen(
        ['macpow', '--json', '--interval', str(MACPOW_INTERVAL)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
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
                                proc.terminate()
                                proc.wait()
                                return readings
                    except:
                        pass
                    buf = ''
    except:
        pass
    proc.terminate()
    try: proc.wait(timeout=5)
    except: proc.kill()
    return readings

def ema(readings, alpha=EMA_ALPHA):
    if not readings: return 0
    s = readings[0]
    for v in readings[1:]:
        s = s * (1 - alpha) + v * alpha
    return s

def var_pct(values):
    if len(values) < 2: return 100
    m = sum(values) / len(values)
    if m < 0.01: return 100
    return ((sum((v - m)**2 for v in values) / len(values)) ** 0.5 / m) * 100

def log(msg):
    ts = datetime.datetime.now().strftime('%H:%M:%S')
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')

def wait_for_settle():
    """Wait until system power stabilizes."""
    log("  Settling...")
    proc = subprocess.Popen(
        ['macpow', '--json', '--interval', str(MACPOW_INTERVAL)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
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
                                window = int(SETTLE_WINDOW * 1000 / MACPOW_INTERVAL)
                                recent = readings[-max(1, window):]
                                v = var_pct(recent)
                                if v < SETTLE_VARIANCE and len(recent) >= 3:
                                    log(f"  Settled at {elapsed:.0f}s (variance {v:.1f}%)")
                                    settled = True

                            if settled or elapsed >= MAX_SETTLE_SECS:
                                if not settled:
                                    log(f"  Settle timeout at {elapsed:.0f}s")
                                proc.terminate()
                                proc.wait()
                                return settled
                    except:
                        pass
                    buf = ''
            if settled or (time.time() - start) >= MAX_SETTLE_SECS:
                break
    except:
        pass
    proc.terminate()
    try: proc.wait(timeout=5)
    except: proc.kill()
    return settled


def calibrate_app(name, pids):
    """Full calibration cycle for one app. Returns result dict or None."""
    log(f"\n{'='*50}")
    log(f"CALIBRATING: {name} ({len(pids)} PIDs: {pids[:5]})")
    log(f"{'='*50}")

    # Measure rusage
    log(f"  Measuring proc_pid_rusage ({RUSAGE_SAMPLE_SEC}s)...")
    rusage_w = measure_rusage(pids)
    log(f"  rusage: {rusage_w*1000:.1f} mW")

    if rusage_w < MIN_POWER_MW / 1000:
        log(f"  SKIP: too low ({rusage_w*1000:.2f} mW < {MIN_POWER_MW} mW threshold)")
        return None

    # Baseline
    n = BASELINE_SECS * 1000 // MACPOW_INTERVAL
    log(f"  Baseline measurement ({BASELINE_SECS}s)...")
    base_readings = read_macpow_power(n)
    base_ema = ema(base_readings)
    base_var = var_pct(base_readings[-5:]) if len(base_readings) >= 5 else 99
    log(f"  Baseline: {base_ema:.2f}W (var: {base_var:.1f}%)")

    # Kill
    log(f"  Killing {name}...")
    killed = 0
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
            killed += 1
        except:
            pass
    log(f"  Sent SIGTERM to {killed}/{len(pids)} PIDs")
    time.sleep(2)

    # Force kill remaining
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except:
            pass

    # Settle
    wait_for_settle()

    # Post-baseline
    log(f"  Post-baseline measurement ({POST_BASE_SECS}s)...")
    post_readings = read_macpow_power(POST_BASE_SECS * 1000 // MACPOW_INTERVAL)
    post_ema = ema(post_readings)
    post_var = var_pct(post_readings[-5:]) if len(post_readings) >= 5 else 99
    log(f"  Post-baseline: {post_ema:.2f}W (var: {post_var:.1f}%)")

    # Compute
    delta = base_ema - post_ema
    coeff = delta / rusage_w if rusage_w > 0.001 else 0

    result = {
        'app': name,
        'coefficient': round(coeff, 2),
        'baseline_w': round(base_ema, 3),
        'post_baseline_w': round(post_ema, 3),
        'delta_mw': round(delta * 1000, 1),
        'rusage_mw': round(rusage_w * 1000, 2),
        'baseline_var': round(base_var, 1),
        'post_var': round(post_var, 1),
        'reliable': 0.5 < coeff < 100 and base_var < 10 and post_var < 10,
        'timestamp': datetime.datetime.now().isoformat(),
    }

    status = "RELIABLE" if result['reliable'] else "UNRELIABLE"
    log(f"  RESULT: delta={delta*1000:.0f}mW, rusage={rusage_w*1000:.1f}mW, "
        f"coeff={coeff:.1f}x [{status}]")

    return result


def main():
    dry_run = '--dry-run' in sys.argv

    signal.signal(signal.SIGINT, lambda *_: (log("\nInterrupted. Partial results saved."), sys.exit(0)))

    log(f"\n{'#'*50}")
    log(f"  PowerBarPro Overnight Calibration")
    log(f"  Started: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}")
    log(f"  Mode: {'DRY RUN' if dry_run else 'LIVE'}")
    log(f"{'#'*50}")

    # Discover apps
    log("\nDiscovering running apps...")
    pids_by_name = get_pids_by_name()

    # Filter out protected
    candidates = {}
    for name, pids in pids_by_name.items():
        if name in PROTECTED_APPS:
            continue
        if any(p in name for p in PROTECTED_APPS):
            continue
        candidates[name] = pids

    # Measure power for all candidates (quick 3s scan)
    log(f"Measuring power for {len(candidates)} candidate apps (3s)...")
    snap1 = {}
    for name, pids in candidates.items():
        for pid in pids:
            e = get_energy_nj(pid)
            if e and e > 0:
                snap1[pid] = (name, e)

    time.sleep(3)

    app_power = defaultdict(lambda: {'watts': 0, 'pids': []})
    for pid, (name, e1) in snap1.items():
        e2 = get_energy_nj(pid)
        if e2 and e2 > e1:
            w = (e2 - e1) / 1e9 / 3.0
            app_power[name]['watts'] += w
            app_power[name]['pids'].append(pid)

    # Sort by power, filter by minimum
    sorted_apps = sorted(app_power.items(), key=lambda x: x[1]['watts'], reverse=True)
    to_calibrate = [(n, d) for n, d in sorted_apps if d['watts'] * 1000 >= MIN_POWER_MW]

    log(f"\nApps to calibrate ({len(to_calibrate)}):")
    for name, data in to_calibrate:
        log(f"  {name:<30} {data['watts']*1000:>8.1f} mW  ({len(data['pids'])} PIDs)")

    if not to_calibrate:
        log("No apps above threshold. Nothing to calibrate.")
        return

    if dry_run:
        log("\nDRY RUN — not killing anything. Exiting.")
        return

    # Estimate total time
    per_app_secs = RUSAGE_SAMPLE_SEC + BASELINE_SECS + MAX_SETTLE_SECS + POST_BASE_SECS + BETWEEN_APPS_WAIT
    total_est = STABILIZE_WAIT + len(to_calibrate) * per_app_secs
    log(f"\nEstimated time: ~{total_est // 60} minutes ({total_est}s)")
    log(f"Expected completion: {(datetime.datetime.now() + datetime.timedelta(seconds=total_est)).strftime('%H:%M')}")

    # Initial stabilization
    log(f"\nPhase 0: Initial stabilization ({STABILIZE_WAIT}s)...")
    log(f"  System going idle (Claude Code stopping)...")
    time.sleep(STABILIZE_WAIT)
    log(f"  Stabilized.")

    # Calibrate each app
    all_results = []
    if os.path.exists(RESULTS_FILE):
        with open(RESULTS_FILE) as f:
            all_results = json.load(f)

    for i, (name, data) in enumerate(to_calibrate):
        log(f"\n[{i+1}/{len(to_calibrate)}] Starting calibration for {name}")

        # Re-check if app is still running
        current_pids = get_pids_by_name().get(name, [])
        if not current_pids:
            log(f"  SKIP: {name} is no longer running")
            continue

        result = calibrate_app(name, current_pids)
        if result:
            all_results.append(result)
            # Save after each app (in case of interrupt)
            with open(RESULTS_FILE, 'w') as f:
                json.dump(all_results, f, indent=2)
            log(f"  Saved to {RESULTS_FILE}")

        # Wait between apps
        if i < len(to_calibrate) - 1:
            log(f"\n  Waiting {BETWEEN_APPS_WAIT}s before next app...")
            time.sleep(BETWEEN_APPS_WAIT)

    # Summary
    session_results = [r for r in all_results if r.get('timestamp', '').startswith(
        datetime.datetime.now().strftime('%Y-%m-%d')
    )]
    reliable = [r for r in session_results if r.get('reliable')]

    log(f"\n{'#'*50}")
    log(f"  CALIBRATION COMPLETE")
    log(f"  Apps calibrated: {len(session_results)}")
    log(f"  Reliable results: {len(reliable)}")
    if reliable:
        coeffs = sorted(r['coefficient'] for r in reliable)
        median = coeffs[len(coeffs) // 2]
        coeff_strs = [f"{r['app']}={r['coefficient']:.1f}x" for r in reliable]
        log(f"  Coefficients: {', '.join(coeff_strs)}")
        log(f"  Median coefficient: {median:.1f}x")
        log(f"  → proc_pid_rusage underestimates by ~{median:.0f}x on average")
    log(f"  Results: {RESULTS_FILE}")
    log(f"  Log: {LOG_FILE}")
    log(f"{'#'*50}\n")


if __name__ == '__main__':
    main()
