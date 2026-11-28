#!/usr/bin/env bash
# Inventory + prove every in-tree JSON contract for rpc-portal-go, edge-go,
# dev-portal-go, and fcgbds-dashboard-go. Does not dial production.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
root = Path(".")
dirs = [
    root / "tests/rebuild/contracts/rpc-portal-go",
    root / "tests/rebuild/contracts/edge-go",
    root / "tests/rebuild/contracts/dev-portal-go",
    root / "tests/rebuild/contracts/fcgbds-dashboard-go",
]
sidecar = (root / "tools/rebuild-unauth-sidecar-diff.sh").read_text()
portal = (root / "tools/rebuild-portal-diff.sh").read_text()
sop = (root / "tools/rebuild-sop-proxy-diff.sh").read_text()
wired = []
unwired = []
for d in dirs:
    for p in sorted(d.glob("*.json")):
        name = str(p).replace("\\", "/")
        ok = name in sidecar or p.name in sidecar
        if p.name in ("healthz.json", "not-found.json", "maintenance.json", "dist-missing.json"):
            ok = True
        if not ok:
            unwired.append(name)
        else:
            wired.append(name)
print("wired_json", len(wired))
for n in wired:
    print("  ", n)
if unwired:
    print("UNWIRED")
    for n in unwired:
        print("  ", n)
    raise SystemExit(2)
assert "api-events.json" in sidecar
assert "api-stream-wall-tilt.json" in sidecar
assert "method-not-allowed.json" in sidecar
assert "fcgbds-dashboard-go.json" in portal
assert "rpc-portal-go.json" in portal
assert "dev-portal-go-auth.json" in portal
assert "edge-go" in sop
print("inventory_ok")
PY

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt-more.vire").read_text()
host = Path("Vire.cs").read_text()
assert "33554432" in rt or "33554432" in Path("src/rt.vire").read_text()
assert "int itemCap = 100000;" in host
assert "itemCap = 1000000;" in host
assert "5000000" in host
print("caps_src_ok arena=33554432 list=100000 steps=5000000 itemCap=100000/1000000")
PY

bash "$ROOT/tools/rebuild-unauth-sidecar-diff.sh"
echo "prove-fcg-portal-contracts ok"
