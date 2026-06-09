"""
驷马C盘清理助手 WebUI Server v4.3 (Security Hardened)
Run: python server.py
Env:
  CLEAN_HOST=127.0.0.1
  CLEAN_PORT=8000
  CLEAN_TOKEN=your_token
  CLEAN_OPEN_FOLDER=0
"""

import json
import subprocess
import os
import logging
from pathlib import Path
from functools import wraps
from flask import Flask, render_template_string, jsonify, request, abort

app = Flask(__name__)

# =========================
# Environment config
# =========================
HOST = os.environ.get("CLEAN_HOST", "0.0.0.0")
PORT = int(os.environ.get("CLEAN_PORT", "5050"))
TOKEN = os.environ.get("CLEAN_TOKEN", "").strip()
OPEN_FOLDER_ENABLED = os.environ.get("CLEAN_OPEN_FOLDER", "0") == "1"

SCRIPT_DIR = Path(__file__).parent
SCRIPT_PATH = SCRIPT_DIR / "cleanup-cache.ps1"
LARGEFILE_SCRIPT = SCRIPT_DIR / "scan-largefiles.ps1"
MEMORY_SCRIPT = SCRIPT_DIR / "clean-memory.ps1"

# --- Logging ---
logging.basicConfig(
    filename=str(Path(os.environ.get("TEMP", "C:/Users/whb/AppData/Local/Temp")) / "cleanup_server.log"),
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    encoding="utf-8",
)
log = logging.getLogger("cleanup")

# --- Template cache ---
_template_cache = None

def load_template():
    global _template_cache
    if _template_cache is None:
        with open(SCRIPT_DIR / "template.html", "r", encoding="utf-8") as f:
            _template_cache = f.read()
    return _template_cache


def get_ps_script():
    return str(SCRIPT_PATH)


def run_ps(command, timeout=120):
    """Run a PowerShell command and return (stdout, stderr) as UTF-8 strings."""
    result = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        capture_output=True, timeout=timeout
    )
    stdout = result.stdout.decode("utf-8", errors="replace").strip()
    stderr = result.stderr.decode("utf-8", errors="replace").strip()
    return stdout, stderr


def extract_json(stdout):
    """Extract the first valid JSON object or array from PowerShell output."""
    # Try object first, then array
    for open_char, close_char in [('{', '}'), ('[', ']')]:
        start = stdout.find(open_char)
        end = stdout.rfind(close_char)
        if start >= 0 and end > start:
            try:
                return json.loads(stdout[start:end + 1])
            except json.JSONDecodeError:
                continue
    return None


def build_category_args(categories):
    if not categories:
        return ""
    valid = {"temp", "dev", "browser", "wupdate", "prefetch", "logs", "recycle", "thumbnails", "delivery", "installer"}
    filtered = [c for c in categories if c in valid]
    if not filtered:
        return ""
    return " -Categories " + ",".join(f'"{c}"' for c in filtered)


# --- Path security for open-folder ---
ALLOWED_DRIVE_ROOTS = [
    os.path.expanduser("~"),          # C:\Users\whb
    "D:\\Users",
    "E:\\",
    "F:\\",
    "I:\\",
]

def is_safe_path(path):
    """Check if the path is within allowed directories."""
    try:
        real = os.path.realpath(path)
    except Exception:
        return False
    return any(real.startswith(root) for root in ALLOWED_DRIVE_ROOTS)

# =========================
# Token guard
# =========================
def require_token(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if TOKEN:
            auth = request.headers.get("Authorization", "")
            if auth != f"Bearer {TOKEN}":
                log.warning("Unauthorized request to %s", request.path)
                abort(401)
        return f(*args, **kwargs)
    return wrapper


@app.route("/api/health")
def api_health():
    return jsonify({"status": "ok", "version": "4.3"})


@app.route("/")
def index():
    return render_template_string(load_template())


@app.route("/api/disk")
@require_token
def api_disk():
    stdout, _ = run_ps(
        "$d = Get-PSDrive C; "
        "@{ free=[math]::Round($d.Free/1GB,2); "
        "total=[math]::Round(($d.Used+$d.Free)/1GB,2); "
        "used=[math]::Round($d.Used/1GB,2) } | ConvertTo-Json"
    )
    data = extract_json(stdout)
    if data:
        return jsonify({"freeGB": data["free"], "totalGB": data["total"], "usedGB": data["used"]})
    return jsonify({"freeGB": 0, "totalGB": 0, "usedGB": 0})


@app.route("/api/scan")
@require_token
def api_scan():
    cats_param = request.args.get("categories", "")
    categories = [c.strip() for c in cats_param.split(",") if c.strip()] if cats_param else []
    cat_args = build_category_args(categories)
    stdout, stderr = run_ps(f'& "{get_ps_script()}" -DryRun -JsonOutput{cat_args}')
    log.info("Scan: categories=%s, stdout_len=%d", categories, len(stdout))
    data = extract_json(stdout)
    if data and "items" in data:
        return jsonify(data["items"])
    if stderr:
        log.warning("Scan stderr: %s", stderr[:200])
    return jsonify([{"Category": "Error", "Item": "Scan failed", "SizeMB": 0, "Status": "error"}])


@app.route("/api/clean", methods=["POST"])
@require_token
def api_clean():
    body = request.get_json(force=True)
    dry_run = body.get("dryRun", True)
    categories = body.get("categories", [])
    args = "-JsonOutput"
    if dry_run:
        args += " -DryRun"
    args += build_category_args(categories)
    stdout, stderr = run_ps(f'& "{get_ps_script()}" {args}')
    log.info("Clean: dryRun=%s, categories=%s, stdout_len=%d", dry_run, categories, len(stdout))
    data = extract_json(stdout)
    if data:
        return jsonify(data)
    if stderr:
        log.warning("Clean stderr: %s", stderr[:200])
    return jsonify({"error": f"Script output parse failed: {stderr or stdout[:200]}"})


@app.route("/api/largefiles")
@require_token
def api_largefiles():
    min_mb = request.args.get("minMB", "100")
    try:
        min_mb = int(min_mb)
    except ValueError:
        min_mb = 100
    stdout, stderr = run_ps(f'& "{str(LARGEFILE_SCRIPT)}" -MinSizeMB {min_mb} -MaxResults 50')
    log.info("LargeFiles: minMB=%d, stdout_len=%d", min_mb, len(stdout))
    data = extract_json(stdout)
    if data is not None:
        if isinstance(data, dict):
            data = [data]
        return jsonify(data)
    return jsonify([])


@app.route("/api/open-folder", methods=["POST"])
def api_open_folder():
    body = request.get_json(force=True)
    path = body.get("path", "")
    if not path:
        return jsonify({"error": "No path provided"}), 400
    if not os.path.exists(path):
        return jsonify({"error": "Path not found"}), 404
    if not is_safe_path(path):
        log.warning("Blocked open-folder for unsafe path: %s", path)
        return jsonify({"error": "Access denied: path not in allowed directories"}), 403
    try:
        subprocess.Popen(["explorer", path])
        log.info("Opened folder: %s", path)
        return jsonify({"ok": True})
    except Exception as e:
        log.error("Failed to open folder %s: %s", path, e)
        return jsonify({"error": str(e)}), 500


@app.route("/api/memory")
@require_token
def api_memory():
    """Get current memory usage stats."""
    stdout, _ = run_ps(
        "$os = Get-CimInstance Win32_OperatingSystem; "
        "@{ totalGB=[math]::Round($os.TotalVisibleMemorySize/1MB,2); "
        "freeGB=[math]::Round($os.FreePhysicalMemory/1MB,2); "
        "usedGB=[math]::Round(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB,2); "
        "usedPct=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1) } | ConvertTo-Json"
    )
    data = extract_json(stdout)
    if data:
        return jsonify(data)
    return jsonify({"totalGB": 0, "freeGB": 0, "usedGB": 0, "usedPct": 0})


@app.route("/api/memory-clean", methods=["POST"])
@require_token
def api_memory_clean():
    """Run memory cleanup."""
    body = request.get_json(force=True)
    aggressive = body.get("aggressive", False)
    args = "-JsonOutput"
    if aggressive:
        args += " -Aggressive"
    stdout, stderr = run_ps(f'& "{str(MEMORY_SCRIPT)}" {args}', timeout=60)
    log.info("MemoryClean: aggressive=%s, stdout_len=%d", aggressive, len(stdout))
    data = extract_json(stdout)
    if data:
        return jsonify(data)
    if stderr:
        log.warning("MemoryClean stderr: %s", stderr[:200])
    return jsonify({"error": f"Memory clean failed: {stderr or stdout[:200]}"})


if __name__ == "__main__":
    banner_url = f"http://{HOST}:{PORT}" if HOST != "0.0.0.0" else f"http://127.0.0.1:{PORT}"
    print("=" * 50)
    print("  驷马C盘清理助手 WebUI v4.3 (Security Hardened)")
    print(f"  {banner_url}")
    print("=" * 50)
    log.info("Server started on %s:%s", HOST, PORT)
    app.run(host=HOST, port=PORT, debug=False)
