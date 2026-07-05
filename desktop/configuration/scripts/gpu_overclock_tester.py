#!/usr/bin/env python3
import os
import sys
import time
import json
import argparse
import subprocess
import threading
import glob
import signal
import csv
import re
from datetime import datetime

# sysfs paths
SYSFS_DIR = "/sys/class/drm/card1/device"
PP_OD_FILE = os.path.join(SYSFS_DIR, "pp_od_clk_voltage")
DPM_LEVEL_FILE = os.path.join(SYSFS_DIR, "power_dpm_force_performance_level")

# safety thresholds
MAX_JUNCTION_TEMP = 111.0  # Celsius (Navi 31 TJunction limit is 110C)
MAX_MEM_TEMP = 106.0      # Celsius (Memory limit is 105C)
MAX_EDGE_TEMP = 90.0       # Celsius

# State & Log defaults
DEFAULT_STATE_FILE = "/tmp/gpu_overclock_state.json"
DEFAULT_LOG_FILE = "./gpu_overclock_test_results.csv"

# Global reference for cleanup on exit
original_settings = {}
original_power_cap = None
active_state_file = DEFAULT_STATE_FILE

def get_hwmon_dir():
    paths = glob.glob(os.path.join(SYSFS_DIR, "hwmon", "hwmon*"))
    return paths[0] if paths else None

def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return None

def write_file(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(value) + "\n")
        return True
    except Exception as e:
        print(f"Error writing '{value}' to '{path}': {e}", file=sys.stderr)
        return False

def parse_current_settings():
    content = read_file(PP_OD_FILE)
    if not content:
        return {}
    
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    settings = {}
    try:
        for i, line in enumerate(lines):
            if line.startswith("OD_SCLK:"):
                if i + 2 < len(lines):
                    match_min = re.search(r':\s*(\d+)', lines[i+1])
                    match_max = re.search(r':\s*(\d+)', lines[i+2])
                    if match_min and match_max:
                        settings['core_min'] = int(match_min.group(1))
                        settings['core_max'] = int(match_max.group(1))
            elif line.startswith("OD_MCLK:"):
                if i + 2 < len(lines):
                    match_min = re.search(r':\s*(\d+)', lines[i+1])
                    match_max = re.search(r':\s*(\d+)', lines[i+2])
                    if match_min and match_max:
                        settings['mem_min'] = int(match_min.group(1))
                        settings['mem_max'] = int(match_max.group(1))
            elif line.startswith("OD_VDDGFX_OFFSET:"):
                if i + 1 < len(lines):
                    match = re.search(r'-?\d+', lines[i+1])
                    if match:
                        settings['volt_offset'] = int(match.group())
    except Exception as e:
        print(f"Error parsing clock settings: {e}", file=sys.stderr)
    return settings

def get_power_cap():
    hwmon = get_hwmon_dir()
    if hwmon:
        cap_file = os.path.join(hwmon, "power1_cap")
        val = read_file(cap_file)
        if val:
            return int(val) // 1000000  # Convert microwatts to Watts
    return None

def set_power_cap(watts):
    hwmon = get_hwmon_dir()
    if hwmon and watts:
        cap_file = os.path.join(hwmon, "power1_cap")
        microwatts = watts * 1000000
        return write_file(cap_file, microwatts)
    return False

def apply_gpu_settings(core_min, core_max, mem_min, mem_max, volt_offset, power_cap=None):
    if not os.path.exists(PP_OD_FILE):
        print(f"Dry run (sysfs not writable or path not found: {PP_OD_FILE})")
        return True
    
    print(f"Applying: Core {core_min}-{core_max}MHz, Mem {mem_min}-{mem_max}MHz, Volt {volt_offset}mV, Power {power_cap}W")
    
    success = True
    success &= write_file(PP_OD_FILE, f"s 0 {core_min}")
    success &= write_file(PP_OD_FILE, f"s 1 {core_max}")
    success &= write_file(PP_OD_FILE, f"m 0 {mem_min}")
    success &= write_file(PP_OD_FILE, f"m 1 {mem_max}")
    success &= write_file(PP_OD_FILE, f"vo {volt_offset}")
    success &= write_file(PP_OD_FILE, "c")
    
    if power_cap:
        success &= set_power_cap(power_cap)
        
    write_file(DPM_LEVEL_FILE, "high")
    return success

def restore_defaults():
    if not original_settings:
        print("No stock settings captured to restore.")
        return
    print("\nRestoring stock GPU settings...")
    apply_gpu_settings(
        original_settings.get('core_min', 500),
        original_settings.get('core_max', 3150),
        original_settings.get('mem_min', 97),
        original_settings.get('mem_max', 1300),
        original_settings.get('volt_offset', 0),
        original_power_cap
    )
    write_file(DPM_LEVEL_FILE, "auto")

def signal_handler(sig, frame):
    print("\nInterrupted by user!")
    restore_defaults()
    sys.exit(1)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

class BenchmarkMonitor(threading.Thread):
    def __init__(self, interval=0.5):
        super().__init__()
        self.interval = interval
        self.running = True
        self.hwmon = get_hwmon_dir()
        self.lock = threading.Lock()
        
        # Stats tracked
        self.max_edge_temp = 0.0
        self.max_junction_temp = 0.0
        self.max_mem_temp = 0.0
        self.max_power = 0.0
        self.sum_power = 0.0
        self.power_samples = 0
        self.thermal_throttle = False
        
    def run(self):
        if not self.hwmon:
            return
            
        edge_file = os.path.join(self.hwmon, "temp1_input")
        junc_file = os.path.join(self.hwmon, "temp2_input")
        mem_file = os.path.join(self.hwmon, "temp3_input")
        power_file = os.path.join(self.hwmon, "power1_average")
        
        while self.running:
            # Read temperatures (convert millidegrees to degrees)
            edge = read_file(edge_file)
            junc = read_file(junc_file)
            mem = read_file(mem_file)
            power = read_file(power_file)
            
            with self.lock:
                if edge:
                    e_val = float(edge) / 1000.0
                    self.max_edge_temp = max(self.max_edge_temp, e_val)
                    if e_val >= MAX_EDGE_TEMP:
                        self.thermal_throttle = True
                if junc:
                    j_val = float(junc) / 1000.0
                    self.max_junction_temp = max(self.max_junction_temp, j_val)
                    if j_val >= MAX_JUNCTION_TEMP:
                        self.thermal_throttle = True
                if mem:
                    m_val = float(mem) / 1000.0
                    self.max_mem_temp = max(self.max_mem_temp, m_val)
                    if m_val >= MAX_MEM_TEMP:
                        self.thermal_throttle = True
                if power:
                    p_val = float(power) / 1000000.0  # microwatts to watts
                    self.max_power = max(self.max_power, p_val)
                    self.sum_power += p_val
                    self.power_samples += 1
                    
            time.sleep(self.interval)
            
    def stop(self):
        self.running = False
        
    def get_stats(self):
        with self.lock:
            avg_power = self.sum_power / self.power_samples if self.power_samples > 0 else 0.0
            return {
                "max_edge_temp": self.max_edge_temp,
                "max_junction_temp": self.max_junction_temp,
                "max_mem_temp": self.max_mem_temp,
                "max_power": self.max_power,
                "avg_power": avg_power,
                "thermal_throttle": self.thermal_throttle
            }

def run_benchmark(timeout=120):
    cmd = ["nix", "shell", "nixpkgs#vkmark", "-c", "vkmark", "-b", "vertex", "-b", "texture", "-b", "shading", "-b", "effect2d"]
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        sudo_cmd = ["sudo", "-u", sudo_user, f"PATH={os.environ.get('PATH', '')}"]
        for ev in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"]:
            val = os.environ.get(ev)
            if val is not None:
                sudo_cmd.append(f"{ev}={val}")
        cmd = sudo_cmd + cmd
        
    env = os.environ.copy()
    
    monitor = BenchmarkMonitor(interval=0.5)
    monitor.start()
    
    process = None
    try:
        # Run vkmark forwarding display environment
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env
        )
        
        # Wait with timeout
        stdout, stderr = process.communicate(timeout=timeout)
        monitor.stop()
        monitor.join()
        
        stats = monitor.get_stats()
        
        if process.returncode != 0:
            print(f"Benchmark process returned non-zero code {process.returncode}.", file=sys.stderr)
            if stderr:
                print(f"Stderr: {stderr.strip()}", file=sys.stderr)
            return {"status": "FAILED", "score": 0, "stats": stats, "error": f"Exit code {process.returncode}"}
            
        # Parse score
        score_match = re.search(r"vkmark Score:\s*(\d+)", stdout)
        score = int(score_match.group(1)) if score_match else 0
        
        if score == 0:
            return {"status": "FAILED", "score": 0, "stats": stats, "error": "Could not parse score"}
            
        if stats["thermal_throttle"]:
            return {"status": "THROTTLED", "score": score, "stats": stats}
            
        return {"status": "STABLE", "score": score, "stats": stats}
        
    except subprocess.TimeoutExpired:
        monitor.stop()
        monitor.join()
        if process:
            process.kill()
            stdout, stderr = process.communicate()
        print("Benchmark timed out (potential GPU freeze).", file=sys.stderr)
        return {"status": "FAILED", "score": 0, "stats": monitor.get_stats(), "error": "Timeout"}
    except Exception as e:
        monitor.stop()
        monitor.join()
        if process and process.poll() is None:
            process.kill()
        print(f"Exception during benchmark: {e}", file=sys.stderr)
        return {"status": "FAILED", "score": 0, "stats": monitor.get_stats(), "error": str(e)}

def save_state(state):
    try:
        with open(active_state_file, "w") as f:
            json.dump(state, f, indent=2)
    except Exception as e:
        print(f"Error saving state: {e}", file=sys.stderr)

def load_state():
    if os.path.exists(active_state_file):
        try:
            with open(active_state_file, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"Error loading state: {e}", file=sys.stderr)
    return None

def write_to_csv(log_path, result_row):
    file_exists = os.path.exists(log_path)
    try:
        with open(log_path, "a", newline="") as f:
            writer = csv.writer(f)
            if not file_exists:
                writer.writerow([
                    "Timestamp", "CoreMin", "CoreMax", "MemMin", "MemMax", "VoltOffset", 
                    "PowerLimit", "Status", "Score", "MaxEdgeTemp", "MaxJunctionTemp", 
                    "MaxMemTemp", "MaxPower", "AvgPower", "Error"
                ])
            writer.writerow(result_row)
    except Exception as e:
        print(f"Error writing to CSV: {e}", file=sys.stderr)

def main():
    global original_settings, original_power_cap, active_state_file
    
    parser = argparse.ArgumentParser(description="GPU Overclock Stability Automation Tester")
    
    # Ranges / Sweeps
    parser.add_argument("--mode", choices=["sequential", "grid"], default="sequential",
                        help="sequential (sweeps one variable at a time, recommended) or grid (sweeps all combinations)")
    parser.add_argument("--core-min", type=int, default=500, help="Core clock minimum (default: 500)")
    parser.add_argument("--core-max-start", type=int, default=3000, help="Core clock maximum start (default: 3000)")
    parser.add_argument("--core-max-end", type=int, default=3250, help="Core clock maximum end (default: 3250)")
    parser.add_argument("--core-max-step", type=int, default=25, help="Core clock maximum step (default: 25)")
    
    parser.add_argument("--mem-min", type=int, default=97, help="Memory clock minimum (default: 97)")
    parser.add_argument("--mem-max-start", type=int, default=1300, help="Memory clock maximum start (default: 1300)")
    parser.add_argument("--mem-max-end", type=int, default=1450, help="Memory clock maximum end (default: 1450)")
    parser.add_argument("--mem-max-step", type=int, default=25, help="Memory clock maximum step (default: 25)")
    
    parser.add_argument("--volt-start", type=int, default=-50, help="Voltage offset start mV (default: -50)")
    parser.add_argument("--volt-end", type=int, default=-150, help="Voltage offset end mV (default: -150)")
    parser.add_argument("--volt-step", type=int, default=-10, help="Voltage offset step mV (default: -10)")
    
    parser.add_argument("--power-limit", type=int, default=334, help="Power limit in Watts (default: 334)")
    
    # Execution & logging config
    parser.add_argument("--state-file", default=DEFAULT_STATE_FILE, help="File to track state for crash-recovery")
    parser.add_argument("--log-file", default=DEFAULT_LOG_FILE, help="CSV file for storing test results")
    parser.add_argument("--cooldown", type=int, default=10, help="Cooldown seconds between benchmark runs (default: 10)")
    parser.add_argument("--dry-run", action="store_true", help="Print settings instead of writing to sysfs, run mock benchmarks")
    
    args = parser.parse_args()
    active_state_file = args.state_file
    
    # Check permissions if not dry-run
    if not args.dry_run and os.getuid() != 0:
        print("Error: This script must be run as root to write to sysfs files.", file=sys.stderr)
        print("Please rerun with sudo, or use --dry-run for mock testing.", file=sys.stderr)
        sys.exit(1)
        
    # Capture original settings for revert/stock
    if not args.dry_run:
        original_settings = parse_current_settings()
        original_power_cap = get_power_cap()
        print(f"Captured stock settings: {original_settings}")
        print(f"Captured stock power limit: {original_power_cap}W")
    else:
        original_settings = {"core_min": 500, "core_max": 3150, "mem_min": 97, "mem_max": 1300, "volt_offset": 0}
        original_power_cap = 334
        print("Dry-run: captured mock stock settings.")
        
    # Load state if exists (crash recovery)
    state = load_state()
    if state and state.get("last_tested"):
        last = state["last_tested"]
        print(f"\n[!] WARNING: Detected previous run did not exit cleanly.")
        print(f"Last settings applied before crash: CoreMax={last['core_max']}MHz, MemMax={last['mem_max']}MHz, Volt={last['volt']}mV")
        
        # Log the crash
        timestamp = datetime.now().isoformat()
        crash_row = [
            timestamp, args.core_min, last["core_max"], args.mem_min, last["mem_max"], 
            last["volt"], args.power_limit, "CRASHED_SYSTEM", 0, 0, 0, 0, 0, 0, "System crash or freeze"
        ]
        write_to_csv(args.log_file, crash_row)
        print(f"Logged CRASHED_SYSTEM for settings: {last} to {args.log_file}")
        
        # Clear last_tested so we don't repeat the crash loop
        state["results"].append({
            "settings": last,
            "status": "CRASHED_SYSTEM",
            "score": 0,
            "stats": {}
        })
        state["last_tested"] = None
        save_state(state)
        
        # Clean GPU state before resuming
        if not args.dry_run:
            restore_defaults()
            print("System restored to stock. Waiting 15s to stabilize...")
            time.sleep(15)
            
        ans = input("Do you want to resume the testing loop? [Y/n]: ").strip().lower()
        if ans == 'n':
            sys.exit(0)
            
    # Generate list of tests if state doesn't exist
    if not state:
        pending_tests = []
        
        # Generate range arrays
        # Ensure correct range boundaries (taking steps into account)
        def make_range(start, end, step):
            if step == 0:
                return [start]
            if (step > 0 and start > end) or (step < 0 and start < end):
                return []
            vals = []
            curr = start
            if step > 0:
                while curr <= end:
                    vals.append(curr)
                    curr += step
            else:
                while curr >= end:
                    vals.append(curr)
                    curr += step
            return vals

        core_max_range = make_range(args.core_max_start, args.core_max_end, args.core_max_step)
        mem_max_range = make_range(args.mem_max_start, args.mem_max_end, args.mem_max_step)
        volt_range = make_range(args.volt_start, args.volt_end, args.volt_step)
        
        # Ensure we always have stock values as fallback
        if not core_max_range: core_max_range = [original_settings.get("core_max", 3150)]
        if not mem_max_range: mem_max_range = [original_settings.get("mem_max", 1300)]
        if not volt_range: volt_range = [original_settings.get("volt_offset", 0)]
        
        if args.mode == "grid":
            # Grid search: test all combinations
            for c in core_max_range:
                for m in mem_max_range:
                    for v in volt_range:
                        pending_tests.append({"core_max": c, "mem_max": m, "volt": v})
        else:
            # Sequential search:
            # 1. Sweep core clock (holding mem and volt at safe start values)
            safe_mem = mem_max_range[0]
            safe_volt = volt_range[0]
            for c in core_max_range:
                pending_tests.append({"core_max": c, "mem_max": safe_mem, "volt": safe_volt, "phase": "core_sweep"})
            
            # Note: in sequential mode, mem_sweep and volt_sweep phases will adapt dynamically 
            # to use the best stable core_max and mem_max found so far.
            # So instead of static combos, we will dynamically append tests or generate them as we go,
            # or we can generate them statically based on starting safe points.
            # Let's handle this in the main loop dynamically if Phase is indicated.
            
        state = {
            "mode": args.mode,
            "core_max_range": core_max_range,
            "mem_max_range": mem_max_range,
            "volt_range": volt_range,
            "pending": pending_tests,
            "results": [],
            "last_tested": None,
            # For sequential tracking
            "best_stable_core": original_settings.get("core_max", 3150),
            "best_stable_mem": original_settings.get("mem_max", 1300),
            "best_stable_volt": original_settings.get("volt_offset", 0),
            "current_phase": "core_sweep" if args.mode == "sequential" else "grid"
        }
        save_state(state)
        
    print(f"\nStarting testing loop in {state['mode']} mode.")
    print(f"Remaining runs in queue: {len(state['pending'])}")
    
    # Run loop
    try:
        while True:
            # If sequential mode and we transitioned phases, we might need to populate the next phase
            if state["mode"] == "sequential" and not state["pending"]:
                if state["current_phase"] == "core_sweep":
                    # Finished core sweep. Find best stable core max.
                    stable_runs = [r for r in state["results"] if r["status"] == "STABLE" and r["settings"].get("phase") == "core_sweep"]
                    if stable_runs:
                        best_run = max(stable_runs, key=lambda x: x["settings"]["core_max"])
                        state["best_stable_core"] = best_run["settings"]["core_max"]
                        print(f"\n[+] Core sweep done. Best stable core: {state['best_stable_core']} MHz")
                    else:
                        print(f"\n[-] No stable core settings found. Reverting to stock core: {state['best_stable_core']} MHz")
                        
                    # Transition to memory sweep phase
                    state["current_phase"] = "mem_sweep"
                    for m in state["mem_max_range"]:
                        state["pending"].append({
                            "core_max": state["best_stable_core"],
                            "mem_max": m,
                            "volt": state["best_stable_volt"],
                            "phase": "mem_sweep"
                        })
                    save_state(state)
                    print(f"Queued memory sweep tests: {len(state['mem_max_range'])} runs.")
                    continue
                    
                elif state["current_phase"] == "mem_sweep":
                    # Finished memory sweep. Find best stable mem max.
                    stable_runs = [r for r in state["results"] if r["status"] == "STABLE" and r["settings"].get("phase") == "mem_sweep"]
                    if stable_runs:
                        best_run = max(stable_runs, key=lambda x: x["settings"]["mem_max"])
                        state["best_stable_mem"] = best_run["settings"]["mem_max"]
                        print(f"\n[+] Memory sweep done. Best stable memory: {state['best_stable_mem']} MHz")
                    else:
                        print(f"\n[-] No stable memory settings found. Reverting to stock memory: {state['best_stable_mem']} MHz")
                        
                    # Transition to voltage sweep phase (undervolting)
                    state["current_phase"] = "volt_sweep"
                    for v in state["volt_range"]:
                        state["pending"].append({
                            "core_max": state["best_stable_core"],
                            "mem_max": state["best_stable_mem"],
                            "volt": v,
                            "phase": "volt_sweep"
                        })
                    save_state(state)
                    print(f"Queued voltage undervolt sweep tests: {len(state['volt_range'])} runs.")
                    continue
                    
                elif state["current_phase"] == "volt_sweep":
                    # Finished all phases
                    state["current_phase"] = "done"
                    break
            
            if not state["pending"]:
                break
                
            test = state["pending"].pop(0)
            c_max = test["core_max"]
            m_max = test["mem_max"]
            volt = test["volt"]
            
            # Save that we are testing this combination (so we can detect crash after reboot)
            state["last_tested"] = test
            save_state(state)
            
            # Apply GPU settings
            if not args.dry_run:
                success = apply_gpu_settings(args.core_min, c_max, args.mem_min, m_max, volt, args.power_limit)
                if not success:
                    print("Error applying settings, skipping run.", file=sys.stderr)
                    state["last_tested"] = None
                    save_state(state)
                    continue
            else:
                print(f"[Mock Apply] Core {args.core_min}-{c_max}, Mem {args.mem_min}-{m_max}, Volt {volt}, Power {args.power_limit}W")
                
            # Run benchmark
            print(f"Running benchmark...")
            if not args.dry_run:
                res = run_benchmark(timeout=90)
            else:
                # Simulation mode behavior
                time.sleep(3)
                # Mock a crash at very high clocks or low voltages
                is_crash = (c_max > 3225) or (m_max > 1425) or (volt < -130)
                if is_crash:
                    res = {"status": "FAILED", "score": 0, "stats": {"max_edge_temp": 75.0, "max_junction_temp": 85.0, "max_mem_temp": 80.0, "max_power": 310.0, "avg_power": 280.0, "thermal_throttle": False}, "error": "Mock crash/instability"}
                else:
                    mock_score = int(4200 + (c_max - 3000)*0.5 + (m_max - 1300)*0.8 + volt*0.2)
                    res = {
                        "status": "STABLE",
                        "score": mock_score,
                        "stats": {
                            "max_edge_temp": 68.0,
                            "max_junction_temp": 78.0,
                            "max_mem_temp": 74.0,
                            "max_power": 305.0,
                            "avg_power": 275.0,
                            "thermal_throttle": False
                        }
                    }
            
            print(f"Benchmark finished: Status={res['status']}, Score={res['score']}")
            if res.get("error"):
                print(f"Details: {res['error']}", file=sys.stderr)
                
            # Log results
            timestamp = datetime.now().isoformat()
            stats = res.get("stats", {})
            row = [
                timestamp, args.core_min, c_max, args.mem_min, m_max, volt, args.power_limit,
                res["status"], res["score"], stats.get("max_edge_temp", 0), stats.get("max_junction_temp", 0),
                stats.get("max_mem_temp", 0), stats.get("max_power", 0), stats.get("avg_power", 0), res.get("error", "")
            ]
            write_to_csv(args.log_file, row)
            
            state["results"].append({
                "settings": test,
                "status": res["status"],
                "score": res["score"],
                "stats": stats,
                "error": res.get("error", "")
            })
            
            # Clear last tested state
            state["last_tested"] = None
            save_state(state)
            
            # Revert to stock/safe to cooldown or avoid crash in idle
            if not args.dry_run:
                restore_defaults()
                print(f"Cooldown: waiting {args.cooldown} seconds...")
                time.sleep(args.cooldown)
            else:
                time.sleep(1)
                
        # End of loop
        print("\n=======================================================")
        print("Testing complete!")
        print(f"Results logged to: {args.log_file}")
        
        # Output summary of best stable results
        stable = [r for r in state["results"] if r["status"] == "STABLE"]
        if stable:
            best_score_run = max(stable, key=lambda x: x["score"])
            print(f"Best score achieved: {best_score_run['score']}")
            b_set = best_score_run["settings"]
            print(f"Settings: CoreMax={b_set['core_max']}MHz, MemMax={b_set['mem_max']}MHz, VoltOffset={b_set['volt']}mV")
        else:
            print("No stable configurations found.")
        print("=======================================================")
        
        # Cleanup state file on successful completion of all tests
        if os.path.exists(active_state_file):
            try:
                os.remove(active_state_file)
            except Exception:
                pass
                
    except KeyboardInterrupt:
        print("\nAborting test loop...", file=sys.stderr)
        if not args.dry_run:
            restore_defaults()
            
if __name__ == "__main__":
    main()
