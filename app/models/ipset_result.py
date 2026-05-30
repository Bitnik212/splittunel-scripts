from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class IpsetResult:
    enabled: bool
    added: list[str]
    failed: dict[str, str]
