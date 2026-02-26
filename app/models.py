import os
from datetime import datetime

from flask_login import UserMixin
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import check_password_hash, generate_password_hash


db = SQLAlchemy()

user_roles = db.Table(
    "user_roles",
    db.Column("user_id", db.Integer, db.ForeignKey("users.id"), primary_key=True),
    db.Column("role_id", db.Integer, db.ForeignKey("roles.id"), primary_key=True),
)


class Role(db.Model):
    __tablename__ = "roles"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(32), unique=True, nullable=False)


class User(UserMixin, db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(255), unique=True, nullable=True)
    password_hash = db.Column(db.String(255), nullable=False)
    must_change_password = db.Column(db.Boolean, default=False, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    roles = db.relationship("Role", secondary=user_roles, lazy="joined")

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def has_role(self, role_name: str) -> bool:
        return any(role.name == role_name for role in self.roles)


class CertificateRequest(db.Model):
    __tablename__ = "certificate_requests"

    STATUS_PENDING = "pending"
    STATUS_REFUSED = "refused"
    STATUS_UPLOADED = "uploaded"

    id = db.Column(db.Integer, primary_key=True)
    reference_id = db.Column(db.String(64), unique=True, nullable=False, index=True)
    requester_uuid = db.Column(db.String(255), nullable=False)
    anydesk = db.Column(db.String(255), nullable=False)
    status = db.Column(db.String(32), default=STATUS_PENDING, nullable=False)
    refusal_reason = db.Column(db.String(255), nullable=True)
    package_path = db.Column(db.String(1024), nullable=True)
    original_filename = db.Column(db.String(255), nullable=True)

    requested_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    reviewed_by_user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    requested_by = db.relationship("User", foreign_keys=[requested_by_user_id], lazy="joined")
    reviewed_by = db.relationship("User", foreign_keys=[reviewed_by_user_id], lazy="joined")

    def file_exists(self) -> bool:
        return bool(self.package_path) and os.path.isfile(self.package_path)
