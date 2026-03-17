"""Tests for Email Service — sending, templates, validation.

TDD Red Phase: Tests before implementation.
"""

import pytest

from packages.email_service.client import EmailClient
from packages.email_service.templates import render_template


class TestEmailClient:
    """Test email client functionality."""

    def test_validates_email_format(self):
        client = EmailClient(smtp_host="localhost", smtp_port=587)
        assert client.validate_email("user@example.com") is True
        assert client.validate_email("invalid-email") is False
        assert client.validate_email("") is False

    def test_build_message(self):
        client = EmailClient(smtp_host="localhost", smtp_port=587)
        msg = client.build_message(
            to="user@example.com",
            subject="Test Alert",
            body_html="<h1>Hello</h1>",
            from_addr="noreply@asgard.ai",
        )
        assert msg["To"] == "user@example.com"
        assert msg["Subject"] == "Test Alert"
        assert msg["From"] == "noreply@asgard.ai"


class TestEmailTemplates:
    """Test HTML template rendering."""

    def test_alert_template(self):
        html = render_template("alert", title="Security Alert", body="Vulnerability found in nginx")
        assert "Security Alert" in html
        assert "Vulnerability found" in html
        assert "<html" in html.lower()
