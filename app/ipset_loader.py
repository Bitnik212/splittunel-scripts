from __future__ import annotations

import subprocess

from .models import IpsetResult


class IpsetLoader:
    def __init__(self, ipset_name: str):
        self.ipset_name = ipset_name

    def load(self, ips: list[str], *, enabled: bool) -> IpsetResult:
        if not enabled:
            return IpsetResult(enabled=False, added=[], failed={})

        added: list[str] = []
        failed: dict[str, str] = {}
        for ip in ips:
            result = subprocess.run(
                ["ipset", "add", self.ipset_name, ip, "-exist"],
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                added.append(ip)
            else:
                failed[ip] = (result.stderr or result.stdout or "ipset failed").strip()

        return IpsetResult(enabled=True, added=added, failed=failed)
