from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException, Query, status

from .domain_service import DomainService
from .errors import DomainError, ResolverError
from .schemas import AddDomainRequest, RemoveDomainRequest
from .settings import settings


app = FastAPI(title="Split Tunnel Control API", version="0.1.0")
domain_service = DomainService(settings)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/custom-domains")
def list_custom_domains() -> dict[str, Any]:
    return {"domains": domain_service.list_domains()}


@app.post("/custom-domains", status_code=status.HTTP_201_CREATED)
def add_custom_domain(payload: AddDomainRequest) -> dict[str, Any]:
    try:
        return domain_service.add_domain(
            payload.domain,
            resolve=payload.resolve,
            load_to_ipset=payload.load_to_ipset,
        )
    except DomainError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
    except ResolverError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.delete("/custom-domains")
def remove_custom_domain(payload: RemoveDomainRequest) -> dict[str, Any]:
    try:
        return domain_service.remove_domain(payload.domain)
    except DomainError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc


@app.post("/custom-domains/refresh")
def refresh_custom_domains(load_to_ipset: bool | None = Query(default=None)) -> dict[str, Any]:
    try:
        return domain_service.refresh_domains(load_to_ipset=load_to_ipset)
    except ResolverError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@app.get("/custom-domains/ips")
def list_custom_domain_ips() -> dict[str, Any]:
    return {"ips": domain_service.list_custom_ips()}
