from __future__ import annotations

from pydantic import BaseModel


class RemoveDomainRequest(BaseModel):
    domain: str
