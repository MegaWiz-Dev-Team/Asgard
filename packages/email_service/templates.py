"""Email Templates — HTML templates for common notifications."""

_TEMPLATES = {
    "alert": """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #dc3545; color: white; padding: 20px; border-radius: 8px 8px 0 0;">
    <h1 style="margin: 0;">⚠️ {title}</h1>
  </div>
  <div style="padding: 20px; border: 1px solid #ddd; border-radius: 0 0 8px 8px;">
    <p>{body}</p>
    <hr style="border: none; border-top: 1px solid #eee;">
    <p style="color: #666; font-size: 12px;">Sent by Asgard AI Platform</p>
  </div>
</body>
</html>""",
    "report": """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #0d6efd; color: white; padding: 20px; border-radius: 8px 8px 0 0;">
    <h1 style="margin: 0;">📊 {title}</h1>
  </div>
  <div style="padding: 20px; border: 1px solid #ddd; border-radius: 0 0 8px 8px;">
    <p>{body}</p>
    <hr style="border: none; border-top: 1px solid #eee;">
    <p style="color: #666; font-size: 12px;">Sent by Asgard AI Platform</p>
  </div>
</body>
</html>""",
    "notification": """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
  <div style="background: #198754; color: white; padding: 20px; border-radius: 8px 8px 0 0;">
    <h1 style="margin: 0;">🔔 {title}</h1>
  </div>
  <div style="padding: 20px; border: 1px solid #ddd; border-radius: 0 0 8px 8px;">
    <p>{body}</p>
    <hr style="border: none; border-top: 1px solid #eee;">
    <p style="color: #666; font-size: 12px;">Sent by Asgard AI Platform</p>
  </div>
</body>
</html>""",
}


def render_template(template_name: str, **kwargs) -> str:
    """Render an HTML email template.

    Args:
        template_name: One of 'alert', 'report', 'notification'.
        **kwargs: Template variables (title, body, etc.).

    Returns:
        Rendered HTML string.

    Raises:
        ValueError: If template_name is not found.
    """
    template = _TEMPLATES.get(template_name)
    if template is None:
        raise ValueError(f"Unknown template: {template_name}. Available: {list(_TEMPLATES.keys())}")
    return template.format(**kwargs)
