# AGENTS.md

## Scope
These instructions apply to the entire repository.

## Goal
Maintain a Flask-based certificate management API with:
- Authentication and roles (`admin`, `user`)
- Mandatory first-login password change for `admin`
- Certificate request, admin review, upload, and download workflow

## Development Rules
- Keep code Python 3.11+ compatible.
- Prefer small, focused changes.
- Preserve existing API paths and payload formats.
- Do not commit secrets or real credentials.

## Run Commands
- Local: `python run.py`
- Container: `docker compose up --build`

## Validation
Before proposing changes, run:
- `python3 -m compileall app run.py`

## Notes
- Default seeded admin user is `admin` / `password` and must change password on first login.
- Email delivery is controlled by environment variables in `.env`.
