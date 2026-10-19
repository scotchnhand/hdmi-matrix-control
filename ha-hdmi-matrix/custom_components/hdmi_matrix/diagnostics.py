from __future__ import annotations

from homeassistant.components.diagnostics import async_redact_data
from homeassistant.core import HomeAssistant

from .const import CONF_PASSWORD

TO_REDACT = {CONF_PASSWORD, "account"}


async def async_get_config_entry_diagnostics(hass: HomeAssistant, entry) -> dict:
    """Return a password-redacted snapshot useful for issue reports."""
    coordinator = entry.runtime_data
    return {
        "entry": async_redact_data(dict(entry.data), TO_REDACT),
        "state": async_redact_data(coordinator.data, TO_REDACT),
    }
