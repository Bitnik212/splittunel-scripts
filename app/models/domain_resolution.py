from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class DomainResolution:
    domain: str
    all_ips: list[str]
    raw_response: dict[str, Any]
