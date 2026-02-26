import smtplib
from email.message import EmailMessage

from flask import current_app


def send_admin_notification(subject: str, body: str):
    if not current_app.config.get("MAIL_ENABLED", False):
        current_app.logger.info("MAIL_DISABLED: %s | %s", subject, body)
        return

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = current_app.config.get("MAIL_USERNAME") or "noreply@example.com"
    msg["To"] = current_app.config["ADMIN_EMAIL"]
    msg.set_content(body)

    try:
        with smtplib.SMTP(current_app.config["MAIL_SERVER"], current_app.config["MAIL_PORT"], timeout=10) as smtp:
            if current_app.config.get("MAIL_USE_TLS"):
                smtp.starttls()
            if current_app.config.get("MAIL_USERNAME"):
                smtp.login(current_app.config["MAIL_USERNAME"], current_app.config.get("MAIL_PASSWORD", ""))
            smtp.send_message(msg)
    except Exception as exc:
        current_app.logger.exception("Failed to send admin notification email: %s", exc)
