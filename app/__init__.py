import os

from flask import Flask, jsonify, request
from flask_login import LoginManager, current_user

from .models import Role, User, db


login_manager = LoginManager()


def create_app():
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY=os.getenv("SECRET_KEY", "dev-change-me"),
        SQLALCHEMY_DATABASE_URI=os.getenv("DATABASE_URL", "sqlite:///certificate_portal.db"),
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        ADMIN_EMAIL=os.getenv("ADMIN_EMAIL", "admin@example.com"),
        MAIL_ENABLED=os.getenv("MAIL_ENABLED", "false").lower() == "true",
        MAIL_SERVER=os.getenv("MAIL_SERVER", "localhost"),
        MAIL_PORT=int(os.getenv("MAIL_PORT", "25")),
        MAIL_USERNAME=os.getenv("MAIL_USERNAME", ""),
        MAIL_PASSWORD=os.getenv("MAIL_PASSWORD", ""),
        MAIL_USE_TLS=os.getenv("MAIL_USE_TLS", "false").lower() == "true",
        UPLOAD_FOLDER=os.getenv("UPLOAD_FOLDER", os.path.join(app.root_path, "uploads")),
    )

    os.makedirs(app.instance_path, exist_ok=True)
    os.makedirs(app.config["UPLOAD_FOLDER"], exist_ok=True)

    db.init_app(app)
    login_manager.init_app(app)

    from .routes import admin_bp, auth_bp, certificate_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(certificate_bp)
    app.register_blueprint(admin_bp)

    @app.route("/")
    def health():
        return jsonify({"status": "ok"})

    @app.before_request
    def enforce_password_change():
        if not current_user.is_authenticated or not current_user.must_change_password:
            return None

        allowed_endpoints = {"auth.change_password", "auth.logout", "auth.login", "health", "static"}
        if request.endpoint not in allowed_endpoints:
            return jsonify({
                "error": "password_change_required",
                "message": "You must change your password before using this endpoint.",
            }), 403
        return None

    with app.app_context():
        db.create_all()
        seed_defaults()

    return app


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


def seed_defaults():
    admin_role = Role.query.filter_by(name="admin").first()
    if not admin_role:
        admin_role = Role(name="admin")
        db.session.add(admin_role)

    user_role = Role.query.filter_by(name="user").first()
    if not user_role:
        user_role = Role(name="user")
        db.session.add(user_role)

    db.session.flush()

    admin = User.query.filter_by(username="admin").first()
    if not admin:
        admin = User(username="admin", email=os.getenv("ADMIN_EMAIL", "admin@example.com"), must_change_password=True)
        admin.set_password("password")
        admin.roles.append(admin_role)
        db.session.add(admin)

    db.session.commit()
