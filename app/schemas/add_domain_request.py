from __future__ import annotations

from pydantic import BaseModel, Field


class AddDomainRequest(BaseModel):
    domain: str = Field(..., examples=["mobileproxy.passport.yandex.net"])
    resolve: bool = True
    load_to_ipset: bool | None = None
