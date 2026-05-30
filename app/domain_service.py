from __future__ import annotations

import threading
from typing import Any

from .domain_resolver import DomainResolver
from .domain_validator import DomainValidator
from .ipset_loader import IpsetLoader
from .line_file_repository import LineFileRepository
from .models import DomainResolution, IpsetResult
from .settings import Settings
from .utils.ip_networks import ip_sort_key


class DomainService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.validator = DomainValidator()
        self.repository = LineFileRepository()
        self.resolver = DomainResolver(
            settings.domain_resolver_url,
            settings.resolver_timeout_seconds,
            settings.responses_file,
        )
        self.ipset_loader = IpsetLoader(settings.ipset_name)
        self._lock = threading.Lock()

    def list_domains(self) -> list[str]:
        return self.repository.read(self.settings.custom_domains_file)

    def list_custom_ips(self) -> list[str]:
        return self.repository.read(self.settings.ru_ips_file)

    def add_domain(self, domain: str, *, resolve: bool = True, load_to_ipset: bool | None = None) -> dict[str, Any]:
        normalized_domain = self.validator.normalize(domain)
        with self._lock:
            domains = self.list_domains()
            created = normalized_domain not in domains
            if created:
                domains.append(normalized_domain)
                self.repository.write(self.settings.custom_domains_file, sorted(domains))

        resolution: DomainResolution | None = None
        ipset_result = IpsetResult(enabled=False, added=[], failed={})
        if resolve:
            resolution = self.resolve_domain(normalized_domain)
            self.append_ips(resolution.all_ips)
            ipset_result = self.load_ips_to_ipset(
                resolution.all_ips,
                enabled=self.settings.ipset_enabled if load_to_ipset is None else load_to_ipset,
            )

        return {
            "domain": normalized_domain,
            "created": created,
            "resolved_ips": [] if resolution is None else resolution.all_ips,
            "ipset": ipset_result.__dict__,
        }

    def remove_domain(self, domain: str) -> dict[str, Any]:
        normalized_domain = self.validator.normalize(domain)
        with self._lock:
            domains = self.list_domains()
            kept = [item for item in domains if item != normalized_domain]
            removed = len(kept) != len(domains)
            if removed:
                self.repository.write(self.settings.custom_domains_file, kept)
        return {"domain": normalized_domain, "removed": removed}

    def refresh_domains(self, *, load_to_ipset: bool | None = None) -> dict[str, Any]:
        domains = self.list_domains()
        results: list[dict[str, Any]] = []
        all_ips: list[str] = []

        for domain in domains:
            resolution = self.resolve_domain(domain)
            all_ips.extend(resolution.all_ips)
            results.append({"domain": domain, "resolved_ips": resolution.all_ips})

        unique_ips = sorted(set(all_ips), key=ip_sort_key)
        self.append_ips(unique_ips)
        ipset_result = self.load_ips_to_ipset(
            unique_ips,
            enabled=self.settings.ipset_enabled if load_to_ipset is None else load_to_ipset,
        )
        return {"domains": results, "resolved_ips": unique_ips, "ipset": ipset_result.__dict__}

    def resolve_domain(self, domain: str) -> DomainResolution:
        return self.resolver.resolve(domain)

    def append_ips(self, ips: list[str]) -> None:
        if not ips:
            return
        with self._lock:
            existing = set(self.list_custom_ips())
            merged = sorted(existing | set(ips), key=ip_sort_key)
            self.repository.write(self.settings.ru_ips_file, merged)

    def load_ips_to_ipset(self, ips: list[str], *, enabled: bool) -> IpsetResult:
        return self.ipset_loader.load(ips, enabled=enabled)
