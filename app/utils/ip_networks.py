from __future__ import annotations

import ipaddress

from app.errors import ResolverError


def validate_ip_network(value: str) -> str:
    try:
        return str(ipaddress.ip_network(value, strict=False))
    except ValueError as exc:
        raise ResolverError(f"resolver returned invalid IP/network: {value}") from exc


def ip_sort_key(value: str) -> tuple[int, int, int]:
    network = ipaddress.ip_network(value, strict=False)
    return (network.version, int(network.network_address), network.prefixlen)
