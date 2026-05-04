#!/usr/bin/env python3
import subprocess
import sys


VULNS = ["0", "1", "2", "3", "4"]


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: smoke_test.py <host>")
        return 2

    host = sys.argv[1]
    checker = [sys.executable, "checker.py"]

    cp = run(checker + ["check", host])
    if cp.returncode != 101:
        print("check failed")
        print(cp.stdout.strip())
        print(cp.stderr.strip())
        return cp.returncode or 1

    for vuln in VULNS:
        flag = f"SMOKE_FLAG_{vuln}"
        put = run(checker + ["put", host, "smoke", flag, vuln])
        if put.returncode != 101:
            print(f"put failed vuln={vuln}")
            print(put.stdout.strip())
            print(put.stderr.strip())
            return put.returncode or 1
        flag_id = put.stdout.strip().splitlines()[-1].strip()

        get = run(checker + ["get", host, flag_id, flag, vuln])
        if get.returncode != 101:
            print(f"get failed vuln={vuln}")
            print(get.stdout.strip())
            print(get.stderr.strip())
            return get.returncode or 1

        print(f"vuln {vuln}: ok")

    print("smoke: all 5 vulns passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
