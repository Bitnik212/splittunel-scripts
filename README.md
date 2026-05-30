# Split Tunnel Control API

FastAPI replacement for the custom-domain shell flow.

It keeps the existing data files:

- `load-custom-domains/custom_domains.txt`
- `load-custom-domains/ru.ips`
- `load-custom-domains/responses.jsonl`

## Run locally

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Add a custom domain

```bash
curl -X POST http://127.0.0.1:8000/custom-domains \
  -H 'Content-Type: application/json' \
  -d '{"domain":"mobileproxy.passport.yandex.net"}'
```

By default the API resolves the domain through the same Yandex Cloud function used by
`load-custom-domains/load-custom-domains.sh`, saves the domain, and appends resolved
IPs to `load-custom-domains/ru.ips`.

## Load resolved IPs into ipset

The API does not run `ipset` by default, which makes local development safe on machines
without root access or ipset installed.

Enable it on the server:

```bash
IPSET_ENABLED=true uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Or enable it per request:

```bash
curl -X POST http://127.0.0.1:8000/custom-domains \
  -H 'Content-Type: application/json' \
  -d '{"domain":"example.ru","load_to_ipset":true}'
```

The ipset name defaults to `ru`; override it with `IPSET_NAME`.

## Endpoints

- `GET /health`
- `GET /custom-domains`
- `POST /custom-domains`
- `DELETE /custom-domains`
- `POST /custom-domains/refresh`
- `GET /custom-domains/ips`

## Configuration

- `DOMAIN_RESOLVER_URL`
- `RESOLVER_TIMEOUT_SECONDS`
- `CUSTOM_DOMAINS_FILE`
- `RU_IPS_FILE`
- `RESPONSES_FILE`
- `IPSET_ENABLED`
- `IPSET_NAME`
