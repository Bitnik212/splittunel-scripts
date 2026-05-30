from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _bool_env(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    data_dir: Path = Path(os.getenv("DATA_DIR", PROJECT_ROOT / "load-custom-domains"))
    custom_domains_file: Path = Path(
        os.getenv(
            "CUSTOM_DOMAINS_FILE",
            PROJECT_ROOT / "load-custom-domains" / "custom_domains.txt",
        )
    )
    ru_ips_file: Path = Path(os.getenv("RU_IPS_FILE", PROJECT_ROOT / "load-custom-domains" / "ru.ips"))
    responses_file: Path = Path(
        os.getenv("RESPONSES_FILE", PROJECT_ROOT / "load-custom-domains" / "responses.jsonl")
    )
    domain_resolver_url: str = os.getenv(
        "DOMAIN_RESOLVER_URL",
        "https://functions.yandexcloud.net/d4er6kvdg57fodc76j7g",
    )
    resolver_timeout_seconds: float = float(os.getenv("RESOLVER_TIMEOUT_SECONDS", "30"))
    ipset_name: str = os.getenv("IPSET_NAME", "ru")
    ipset_enabled: bool = _bool_env("IPSET_ENABLED", False)


settings = Settings()
