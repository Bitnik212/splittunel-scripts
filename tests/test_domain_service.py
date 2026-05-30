from pathlib import Path

import pytest

from app.domain_service import DomainService
from app.domain_validator import DomainValidator
from app.errors import DomainError
from app.models import DomainResolution
from app.settings import Settings


def test_normalize_domain_lowercases_and_strips_trailing_dot() -> None:
    assert DomainValidator().normalize("MobileProxy.Passport.Yandex.Net.") == "mobileproxy.passport.yandex.net"


@pytest.mark.parametrize("domain", ["", "localhost", "-bad.example", "bad..example"])
def test_normalize_domain_rejects_invalid_values(domain: str) -> None:
    with pytest.raises(DomainError):
        DomainValidator().normalize(domain)


def test_add_domain_without_resolve_is_idempotent(tmp_path: Path) -> None:
    settings = Settings(
        data_dir=tmp_path,
        custom_domains_file=tmp_path / "custom_domains.txt",
        ru_ips_file=tmp_path / "ru.ips",
        responses_file=tmp_path / "responses.jsonl",
    )
    service = DomainService(settings)

    first = service.add_domain("Example.Ru", resolve=False)
    second = service.add_domain("example.ru", resolve=False)

    assert first["created"] is True
    assert second["created"] is False
    assert service.list_domains() == ["example.ru"]


def test_append_ips_deduplicates_and_sorts(tmp_path: Path) -> None:
    settings = Settings(
        data_dir=tmp_path,
        custom_domains_file=tmp_path / "custom_domains.txt",
        ru_ips_file=tmp_path / "ru.ips",
        responses_file=tmp_path / "responses.jsonl",
    )
    service = DomainService(settings)

    service.append_ips(["10.0.0.2/32", "10.0.0.1/32"])
    service.append_ips(["10.0.0.1/32"])

    assert service.list_custom_ips() == ["10.0.0.1/32", "10.0.0.2/32"]


def test_refresh_domains_deduplicates_ips(tmp_path: Path) -> None:
    settings = Settings(
        data_dir=tmp_path,
        custom_domains_file=tmp_path / "custom_domains.txt",
        ru_ips_file=tmp_path / "ru.ips",
        responses_file=tmp_path / "responses.jsonl",
    )
    service = DomainService(settings)
    service.add_domain("example.ru", resolve=False)
    service.resolve_domain = lambda domain: DomainResolution(  # type: ignore[method-assign]
        domain=domain,
        all_ips=["10.0.0.2/32", "10.0.0.1/32", "10.0.0.1/32"],
        raw_response={},
    )

    result = service.refresh_domains(load_to_ipset=False)

    assert result["resolved_ips"] == ["10.0.0.1/32", "10.0.0.2/32"]
    assert service.list_custom_ips() == ["10.0.0.1/32", "10.0.0.2/32"]
