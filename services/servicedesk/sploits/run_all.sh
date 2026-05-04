#!/usr/bin/env bash
set -u

BASE="${BASE:-http://localhost:8080}"
CALLBACK_HOST="${CALLBACK_HOST:-host.docker.internal}"

cd "$(dirname "$0")"

echo "=== seeding victim ==="
python3 seed_victim.py --base "$BASE"
echo

for f in vuln1_ssrf vuln2_priv_esc vuln3_bola_artifact vuln4_share_token vuln5_ssti vuln6_path_traversal vuln7_directory_leak; do
    echo "=== $f ==="
    if [ "$f" = "vuln1_ssrf" ]; then
        python3 $f.py --base "$BASE" --callback-host "$CALLBACK_HOST" || echo "[!] $f failed"
    else
        python3 $f.py --base "$BASE" || echo "[!] $f failed"
    fi
    echo
done
