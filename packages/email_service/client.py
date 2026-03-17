"""Email Client — send emails via SMTP with HTML support.

Supports Gmail and standard SMTP servers.
"""

import re
from dataclasses import dataclass
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart


_EMAIL_REGEX = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')


@dataclass
class EmailClient:
    """Email sender via SMTP.

    Args:
        smtp_host: SMTP server hostname.
        smtp_port: SMTP server port (587 for TLS, 465 for SSL).
        username: SMTP auth username (optional).
        password: SMTP auth password (optional).
    """

    smtp_host: str
    smtp_port: int = 587
    username: str = ""
    password: str = ""

    def validate_email(self, email: str) -> bool:
        """Validate email address format.

        Args:
            email: Email address to validate.

        Returns:
            True if email format is valid.
        """
        if not email:
            return False
        return bool(_EMAIL_REGEX.match(email))

    def build_message(
        self,
        to: str,
        subject: str,
        body_html: str,
        from_addr: str = "noreply@asgard.ai",
    ) -> MIMEMultipart:
        """Build MIME email message.

        Args:
            to: Recipient email address.
            subject: Email subject line.
            body_html: HTML body content.
            from_addr: Sender email address.

        Returns:
            MIMEMultipart message object.
        """
        msg = MIMEMultipart("alternative")
        msg["To"] = to
        msg["Subject"] = subject
        msg["From"] = from_addr

        html_part = MIMEText(body_html, "html", "utf-8")
        msg.attach(html_part)

        return msg
