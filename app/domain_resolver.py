from __future__ import annotations

import json
import threading
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from .errors import ResolverError
from .models import DomainResolution
from .utils.ip_networks import ip_sort_key, validate_ip_network


class DomainResolver:
    def __init__(self, resolver_url: str, timeout_seconds: float, responses_file: Path):
        self.resolver_url = resolver_url
        self.timeout_seconds = timeout_seconds
        self.responses_file = responses_file
        self._lock = threading.Lock()

    def resolve(self, domain: str) -> DomainResolution:
        payload = json.dumps({"domain": domain}).encode("utf-8")
        request = urllib.request.Request(
            self.resolver_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                data = json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise ResolverError(f"failed to resolve domain {domain}: {exc}") from exc

        ips = sorted({validate_ip_network(ip) for ip in data.get("all_ips", [])}, key=ip_sort_key)
        self._append_jsonl(data)
        return DomainResolution(domain=domain, all_ips=ips, raw_response=data)

    def _append_jsonl(self, data: dict[str, Any]) -> None:
        self.responses_file.parent.mkdir(parents=True, exist_ok=True)
        with self._lock:
            with self.responses_file.open("a", encoding="utf-8") as file:
                file.write(json.dumps(data, ensure_ascii=True, sort_keys=True))
                file.write("\n")
