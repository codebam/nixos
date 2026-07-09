#!/usr/bin/env python3
import os
import sys
import time
import json
import subprocess
import threading
import glob
import signal
from datetime import datetime

# sysfs paths
SYSFS_DIR = "/sys/class/drm/card1/device"
PP_OD_FILE = os.path.join(SYSFS_DIR, "pp_od_clk_voltage")

# Cooldown time between loops to prevent simple thermal runoff, or set to 0 for maximum stress
COOLDOWN = 1.0

# Stats defaults
LOG_FILE = "./gpu_stress_test_log.json"

running = True

def get_hwmon_dir():
    paths = glob.glob(os.path.join(SYSFS_DIR, "hwmon", "hwmon*"))
    return paths[0] if paths else None

def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return None

class BenchmarkMonitor(threading.Thread):
    def __init__(self, interval=0.5):
        super().__init__()
        self.interval = interval
        self.running = True
        self.hwmon = get_hwmon_dir()
        self.lock = threading.Lock()
        
        self.max_edge = 0.0
        self.max_junc = 0.0
        self.max_mem = 0.0
        self.max_power = 0.0
        
    def run(self):
        if not self.hwmon:
            return
            
        edge_file = os.path.join(self.hwmon, "temp1_input")
        junc_file = os.path.join(self.hwmon, "temp2_input")
        mem_file = os.path.join(self.hwmon, "temp3_input")
        power_file = os.path.join(self.hwmon, "power1_average")
        
        while self.running:
            edge = read_file(edge_file)
            junc = read_file(junc_file)
            mem = read_file(mem_file)
            power = read_file(power_file)
            
            with self.lock:
                if edge:
                    self.max_edge = max(self.max_edge, float(edge) / 1000.0)
                if junc:
                    self.max_junc = max(self.max_junc, float(junc) / 1000.0)
                if mem:
                    self.max_mem = max(self.max_mem, float(mem) / 1000.0)
                if power:
                    self.max_power = max(self.max_power, float(power) / 1000000.0)
                    
            time.sleep(self.interval)
            
    def stop(self):
        self.running = False
        
    def get_stats(self):
        with self.lock:
            return {
                "max_edge_temp": self.max_edge,
                "max_junction_temp": self.max_junc,
                "max_mem_temp": self.max_mem,
                "max_power": self.max_power
            }

def get_dmesg_errors():
    try:
        res = subprocess.run(["dmesg"], capture_output=True, text=True)
        lines = res.stdout.splitlines()
        # Find any amdgpu or mesa or drm errors in last 100 lines
        errors = [line for line in lines[-100:] if any(x in line.lower() for x in ["amdgpu", "gpu reset", "ring gfx", "device lost", "context lost", "hardware hang"])]
        return "\n".join(errors)
    except Exception as e:
        return f"Could not read dmesg: {e}"

def signal_handler(sig, frame):
    global running
    print("\nStopping stress test loop...")
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def main():
    global running
    print("=======================================================")
    print("GPU Infinite Stress Test Loop Starting")
    print(f"Current Settings in sysfs:\n{read_file(PP_OD_FILE)}")
    print("=======================================================")
    
    # Check whoami (needs to drop privileges for vkmark display access)
    sudo_user = os.environ.get("SUDO_USER")
    
    loop_count = 0
    results = []
    
    cmd = ["nix", "shell", "nixpkgs#vkmark", "-c", "vkmark", "--fullscreen", 
           "-b", "shading:shading=phong:duration=10.0", 
           "-b", "effect2d:kernel=blur:background-resolution=1920x1080:duration=10.0", 
           "-b", "desktop:windows=12:background-resolution=1920x1080:duration=10.0"]
           
    if sudo_user:
        sudo_cmd = ["sudo", "-u", sudo_user, f"PATH={os.environ.get('PATH', '')}"]
        for ev in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"]:
            val = os.environ.get(ev)
            if val is not None:
                sudo_cmd.append(f"{ev}={val}")
        cmd = sudo_cmd + cmd
        
    env = os.environ.copy()
    
    while running:
        loop_count += 1
        timestamp = datetime.now().isoformat()
        print(f"\n[Loop #{loop_count}] Starting at {timestamp}...")
        
        monitor = BenchmarkMonitor(interval=0.5)
        monitor.start()
        
        process = None
        try:
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env
            )
            
            # Wait up to 60 seconds (benchmark duration is 30 seconds)
            stdout, stderr = process.communicate(timeout=60)
            monitor.stop()
            monitor.join()
            
            stats = monitor.get_stats()
            
            if process.returncode != 0:
                print(f"[-] CRASH DETECTED at Loop #{loop_count}! Exit code: {process.returncode}")
                if stderr:
                    print(f"Stderr: {stderr.strip()}")
                
                dmesg_info = get_dmesg_errors()
                print(f"\n=== DMESG GPU LOGS ===\n{dmesg_info}\n======================")
                
                results.append({
                    "loop": loop_count,
                    "status": "CRASHED",
                    "exit_code": process.returncode,
                    "stderr": stderr.strip(),
                    "dmesg": dmesg_info,
                    "stats": stats,
                    "timestamp": timestamp
                })
                break
                
            # Parse score
            score = 0
            for line in stdout.splitlines():
                if "vkmark Score:" in line:
                    try:
                        score = int(line.split(":")[-1].strip())
                    except ValueError:
                        pass
                        
            print(f"[+] Loop #{loop_count} STABLE. Score: {score} | MaxJunc: {stats['max_junction_temp']}°C | MaxPower: {stats['max_power']}W")
            
            results.append({
                "loop": loop_count,
                "status": "STABLE",
                "score": score,
                "stats": stats,
                "timestamp": timestamp
            })
            
        except subprocess.TimeoutExpired:
            monitor.stop()
            monitor.join()
            if process:
                process.kill()
                stdout, stderr = process.communicate()
            print(f"[-] TIMEOUT (GPU FREEZE) at Loop #{loop_count}!")
            dmesg_info = get_dmesg_errors()
            print(f"\n=== DMESG GPU LOGS ===\n{dmesg_info}\n======================")
            
            results.append({
                "loop": loop_count,
                "status": "TIMEOUT",
                "dmesg": dmesg_info,
                "stats": monitor.get_stats(),
                "timestamp": timestamp
            })
            break
        except Exception as e:
            monitor.stop()
            monitor.join()
            if process and process.poll() is None:
                process.kill()
            print(f"[-] Error during execution at Loop #{loop_count}: {e}")
            break
            
        # Write results to log file
        with open(LOG_FILE, "w") as f:
            json.dump({"loops_completed": loop_count, "results": results}, f, indent=2)
            
        if COOLDOWN > 0:
            time.sleep(COOLDOWN)
            
    print(f"\nStress test loop finished. Completed {loop_count} loops.")
    with open(LOG_FILE, "w") as f:
        json.dump({"loops_completed": loop_count, "results": results}, f, indent=2)

if __name__ == "__main__":
    main()
