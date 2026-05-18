#!/usr/bin/env python3
"""Validate firewall/allowed-ips line by line.

A typo in the allowed-ips file silently creates iptables rules that don't
match the intended IPs, locking out the operator. Format:

  - one IP or CIDR per line
  - blank lines and comments (#) ignored
  - inline comments after the IP allowed (e.g. "1.2.3.4/32  # home")

Exit code 0 on success, 1 on any invalid entry. Prints the offending line
number for fast diagnosis.

Run via `just test` (project) or directly:
  python3 tests/validate_allowed_ips.py [path/to/allowed-ips]

Defaults to firewall/allowed-ips. If that file is missing (it's gitignored),
the script exits 0 with a notice — there's nothing to validate locally.
"""
from __future__ import annotations

import ipaddress
import sys
from pathlib import Path


def validate_file(path: Path) -> int:
    if not path.exists():
        print(f"[validate-allowed-ips] {path} not found (gitignored on fresh clones); skipping")
        return 0

    errors: list[str] = []
    with path.open() as f:
        for lineno, raw in enumerate(f, start=1):
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            # Inline comment support: "1.2.3.4/32  # home" → "1.2.3.4/32"
            ip_field = stripped.split()[0]
            try:
                ipaddress.ip_network(ip_field, strict=False)
            except ValueError as exc:
                errors.append(f"line {lineno}: {ip_field!r} is not a valid IP/CIDR: {exc}")

    if errors:
        print(f"[validate-allowed-ips] {len(errors)} error(s) in {path}:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1

    # Count valid entries for the success message.
    valid = sum(
        1 for line in path.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    )
    print(f"[validate-allowed-ips] {valid} valid entries in {path}")
    return 0


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    default_path = repo_root / "firewall" / "allowed-ips"
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else default_path
    return validate_file(path)


if __name__ == "__main__":
    sys.exit(main())
