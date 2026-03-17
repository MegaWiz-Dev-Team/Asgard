"""Email Service — SMTP/Gmail email sender for Asgard platform."""

from packages.email_service.client import EmailClient
from packages.email_service.templates import render_template

__all__ = ["EmailClient", "render_template"]
