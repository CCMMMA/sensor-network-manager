# Sensor Network Manager - Certificate Service

Flask service with users/roles and certificate request flow.

## Implemented Requirements
- User and roles management (`admin`, `user`)
- Pre-registered admin account:
  - username: `admin`
  - password: `password`
- Admin must change password at first login
- API `POST /certificate/request` with JSON payload:
  - `uuid`
  - `anydesk`
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

## Run in Container

### Docker Compose (recommended)
```bash
cp .env.example .env
docker compose up --build
```

Service is available at:
- `http://127.0.0.1:5000`

To stop:
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

## Admin Endpoints
- `GET /admin/requests`
- `POST /admin/requests/<reference_id>/refuse`
- `POST /admin/requests/<reference_id>/upload` (multipart form file field: `certificate`)

## Notes
- First login with `admin/password` only allows password change.
- By default email sending is disabled (`MAIL_ENABLED=false`) and notification is logged.
- Enable SMTP in `.env` to send real emails.
