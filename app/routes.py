import os
from functools import wraps
from uuid import uuid4

from flask import Blueprint, current_app, jsonify, request, send_file
from flask_login import current_user, login_required, login_user, logout_user
from werkzeug.utils import secure_filename

from .email_utils import send_admin_notification
from .models import CertificateRequest, User, db


auth_bp = Blueprint("auth", __name__)
certificate_bp = Blueprint("certificate", __name__, url_prefix="/certificate")
admin_bp = Blueprint("admin", __name__, url_prefix="/admin")


def role_required(role_name):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not current_user.is_authenticated:
                return jsonify({"error": "authentication_required"}), 401
            if not current_user.has_role(role_name):
                return jsonify({"error": "forbidden", "message": "Insufficient role"}), 403
            return func(*args, **kwargs)

        return wrapper

    return decorator


@auth_bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    username = data.get("username", "").strip()
    password = data.get("password", "")

    if not username or not password:
        return jsonify({"error": "username_and_password_required"}), 400

    user = User.query.filter_by(username=username).first()
    if not user or not user.check_password(password):
        return jsonify({"error": "invalid_credentials"}), 401

    login_user(user)
    return jsonify({
        "message": "login_successful",
        "must_change_password": user.must_change_password,
        "roles": [role.name for role in user.roles],
    })


@auth_bp.post("/logout")
@login_required
def logout():
    logout_user()
    return jsonify({"message": "logout_successful"})


@auth_bp.post("/change-password")
@login_required
def change_password():
    data = request.get_json(silent=True) or {}
    old_password = data.get("old_password", "")
    new_password = data.get("new_password", "")

    if not old_password or not new_password:
        return jsonify({"error": "old_password_and_new_password_required"}), 400

    if len(new_password) < 8:
        return jsonify({"error": "password_too_short", "message": "Minimum 8 characters"}), 400

    if not current_user.check_password(old_password):
        return jsonify({"error": "invalid_old_password"}), 400

    current_user.set_password(new_password)
    current_user.must_change_password = False
    db.session.commit()

    return jsonify({"message": "password_changed"})


@certificate_bp.post("/request")
@login_required
def create_certificate_request():
    payload = request.get_json(silent=True) or {}
    requester_uuid = payload.get("uuid", "").strip()
    anydesk = payload.get("anydesk", "").strip()

    if not requester_uuid or not anydesk:
        return jsonify({"error": "uuid_and_anydesk_are_required"}), 400

    reference_id = uuid4().hex
    cert_request = CertificateRequest(
        reference_id=reference_id,
        requester_uuid=requester_uuid,
        anydesk=anydesk,
        status=CertificateRequest.STATUS_PENDING,
        requested_by_user_id=current_user.id,
    )
    db.session.add(cert_request)
    db.session.commit()

    send_admin_notification(
        subject=f"New certificate request {reference_id}",
        body=(
            "A new certificate request has been received.\n"
            f"Reference ID: {reference_id}\n"
            f"UUID: {requester_uuid}\n"
            f"AnyDesk: {anydesk}\n"
            f"Requested by: {current_user.username}\n"
        ),
    )

    return jsonify({"reference_id": reference_id}), 201


@certificate_bp.get("/download/<reference_id>")
@login_required
def download_certificate(reference_id):
    cert_request = CertificateRequest.query.filter_by(reference_id=reference_id).first()
    if not cert_request:
        return jsonify({"error": "request_not_found"}), 404

    if cert_request.status == CertificateRequest.STATUS_REFUSED:
        return jsonify({
            "error": "request_refused",
            "message": cert_request.refusal_reason or "Certificate request refused",
        }), 403

    if cert_request.status != CertificateRequest.STATUS_UPLOADED:
        return jsonify({"error": "certificate_not_ready"}), 409

    if not cert_request.file_exists():
        return jsonify({"error": "certificate_package_missing"}), 500

    filename = cert_request.original_filename or os.path.basename(cert_request.package_path)
    return send_file(cert_request.package_path, as_attachment=True, download_name=filename)


@admin_bp.get("/requests")
@login_required
@role_required("admin")
def list_requests():
    requests = CertificateRequest.query.order_by(CertificateRequest.created_at.desc()).all()
    return jsonify([
        {
            "reference_id": item.reference_id,
            "uuid": item.requester_uuid,
            "anydesk": item.anydesk,
            "status": item.status,
            "refusal_reason": item.refusal_reason,
            "requested_by": item.requested_by.username if item.requested_by else None,
            "created_at": item.created_at.isoformat() + "Z",
            "updated_at": item.updated_at.isoformat() + "Z",
        }
        for item in requests
    ])


@admin_bp.post("/requests/<reference_id>/refuse")
@login_required
@role_required("admin")
def refuse_request(reference_id):
    cert_request = CertificateRequest.query.filter_by(reference_id=reference_id).first()
    if not cert_request:
        return jsonify({"error": "request_not_found"}), 404

    if cert_request.status == CertificateRequest.STATUS_UPLOADED:
        return jsonify({"error": "already_uploaded", "message": "Cannot refuse uploaded request"}), 409

    data = request.get_json(silent=True) or {}
    reason = data.get("reason", "Refused by admin").strip()

    cert_request.status = CertificateRequest.STATUS_REFUSED
    cert_request.refusal_reason = reason
    cert_request.reviewed_by_user_id = current_user.id
    db.session.commit()

    return jsonify({"message": "request_refused", "reference_id": cert_request.reference_id})


@admin_bp.post("/requests/<reference_id>/upload")
@login_required
@role_required("admin")
def upload_certificate(reference_id):
    cert_request = CertificateRequest.query.filter_by(reference_id=reference_id).first()
    if not cert_request:
        return jsonify({"error": "request_not_found"}), 404

    if cert_request.status == CertificateRequest.STATUS_REFUSED:
        return jsonify({"error": "already_refused", "message": "Cannot upload refused request"}), 409

    if "certificate" not in request.files:
        return jsonify({"error": "certificate_file_required", "message": "Use multipart form key 'certificate'"}), 400

    file = request.files["certificate"]
    if not file.filename:
        return jsonify({"error": "empty_filename"}), 400

    safe_name = secure_filename(file.filename)
    req_folder = os.path.join(current_app.config["UPLOAD_FOLDER"], cert_request.reference_id)
    os.makedirs(req_folder, exist_ok=True)

    package_path = os.path.join(req_folder, safe_name)
    file.save(package_path)

    cert_request.package_path = package_path
    cert_request.original_filename = safe_name
    cert_request.status = CertificateRequest.STATUS_UPLOADED
    cert_request.refusal_reason = None
    cert_request.reviewed_by_user_id = current_user.id
    db.session.commit()

    return jsonify({"message": "certificate_uploaded", "reference_id": cert_request.reference_id})
