from __future__ import annotations

import re

from .errors import DomainError


DOMAIN_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


class DomainValidator:
    def normalize(self, domain: str) -> str:
        value = domain.strip().lower().rstrip(".")
        if not value:
            raise DomainError("domain is required")

        try:
            ascii_domain = value.encode("idna").decode("ascii")
        except UnicodeError as exc:
            raise DomainError("domain is not a valid IDN hostname") from exc

        if len(ascii_domain) > 253:
            raise DomainError("domain is too long")

        labels = ascii_domain.split(".")
        if len(labels) < 2:
            raise DomainError("domain must include at least one dot")
        if any(not DOMAIN_LABEL_RE.match(label) for label in labels):
            raise DomainError("domain contains an invalid label")

        return ascii_domain
