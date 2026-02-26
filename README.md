# Sensor Network Manager - Certificate Service

Flask service with users/roles and certificate request/download workflow.

## Implemented Requirements
- User and roles management (`admin`, `user`)
- Pre-registered admin account:
  - username: `admin`
  - password: `password`
- Admin must change password at first login
- API `POST /certificate/request` accepts JSON payload with:
  - `uuid`
  - `anydesk`
  - `country`
  - `city`
  - `lat`
  - `lon`
  Returns a generated `reference_id`
- API `GET /certificate/download/<reference_id>` returns certificate package only after admin upload
- On `/certificate/request`, an email notification is sent to admin
- Admin can:
  - refuse request: `POST /admin/requests/<reference_id>/refuse`
  - upload certificate package: `POST /admin/requests/<reference_id>/upload`

## Local Run
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python run.py
```

Service URL:
- `http://127.0.0.1:5000`

## Run in Container

### Docker Compose (recommended)
```bash
cp .env.example .env
docker compose up --build
```

Stop:
```bash
docker compose down
```

### Docker (without Compose)
```bash
cp .env.example .env
docker build -t sensor-network-manager .
docker run --rm -p 5000:5000 --env-file .env \
  -v "$(pwd)/instance:/app/instance" \
  -v "$(pwd)/app/uploads:/app/app/uploads" \
  sensor-network-manager
```

## Authentication Endpoints
- `POST /login`
- `POST /change-password`
- `POST /logout`

## Certificate Endpoints
- `POST /certificate/request`
- `GET /certificate/download/<reference_id>`

Example request payload:
```json
{
  "uuid": "it.uniparthenope.meteo.myhost.lab",
  "anydesk": "123 456 789",
  "country": "Italy",
  "city": "Naples",
  "lat": 40.8518,
  "lon": 14.2681
}
```

## Admin Endpoints
- `GET /admin/requests`
- `POST /admin/requests/<reference_id>/refuse`
- `POST /admin/requests/<reference_id>/upload` (multipart form file field: `certificate`)

## Client Script
The helper script creates a certificate request and waits until download is available:
- `scripts/request_certificate_and_wait.sh`

Default behavior:
- Auto-detects `uuid` from reversed host FQDN with root `it.uniparthenope.meteo`
- Auto-detects AnyDesk ID
- Auto-detects geo info using:
  - `http://ip-api.com/json?fields=country,city`
  - `http://ip-api.com/json?fields=lat,lon`

Usage:
```bash
./scripts/request_certificate_and_wait.sh
./scripts/request_certificate_and_wait.sh output.zip
./scripts/request_certificate_and_wait.sh <uuid> <anydesk> [output_file]
```

Useful env overrides:
- `BASE_URL`, `USERNAME`, `PASSWORD`, `NEW_PASSWORD`
- `UUID_ROOT`, `ANYDESK_ID`
- `COUNTRY`, `CITY`, `LAT`, `LON`
- `POLL_INTERVAL`, `MAX_WAIT_SECONDS`

## Notes
- First login with `admin/password` only allows password change.
- By default email sending is disabled (`MAIL_ENABLED=false`) and notifications are logged.
- Enable SMTP in `.env` to send real emails.
