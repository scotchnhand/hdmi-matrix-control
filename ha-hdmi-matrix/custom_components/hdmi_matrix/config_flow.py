from __future__ import annotations

import logging
from typing import Any

import voluptuous as vol
from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResult
from homeassistant.exceptions import HomeAssistantError

from .const import CONF_HOST, CONF_PASSWORD, CONF_USERNAME, DEFAULT_PASSWORD, DEFAULT_USERNAME, DOMAIN
from .matrix_client import MatrixClient, MatrixError

_LOGGER = logging.getLogger(__name__)

STEP_USER_SCHEMA = vol.Schema({
    vol.Required(CONF_HOST, default="matrix.local"): str,
    vol.Required(CONF_USERNAME, default=DEFAULT_USERNAME): str,
    vol.Required(CONF_PASSWORD, default=DEFAULT_PASSWORD): str,
})


async def _validate(hass: HomeAssistant, data: dict[str, Any]) -> dict[str, Any]:
    client = MatrixClient(data[CONF_HOST], data[CONF_USERNAME], data[CONF_PASSWORD])

    def _try_login():
        client.login()
        return client.get_state()

    try:
        state = await hass.async_add_executor_job(_try_login)
    except MatrixError as err:
        raise InvalidAuth from err
    except Exception as err:  # noqa: BLE001 - surface anything as "cannot connect"
        raise CannotConnect from err

    return {"title": f"HDMI Matrix ({state['device'].get('ip', data[CONF_HOST])})"}


class ConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> FlowResult:
        errors: dict[str, str] = {}
        if user_input is not None:
            await self.async_set_unique_id(user_input[CONF_HOST])
            self._abort_if_unique_id_configured()
            try:
                info = await _validate(self.hass, user_input)
            except CannotConnect:
                errors["base"] = "cannot_connect"
            except InvalidAuth:
                errors["base"] = "invalid_auth"
            except Exception:  # noqa: BLE001
                _LOGGER.exception("Unexpected exception validating HDMI matrix connection")
                errors["base"] = "unknown"
            else:
                return self.async_create_entry(title=info["title"], data=user_input)

        return self.async_show_form(step_id="user", data_schema=STEP_USER_SCHEMA, errors=errors)


class CannotConnect(HomeAssistantError):
    """Error to indicate we cannot connect."""


class InvalidAuth(HomeAssistantError):
    """Error to indicate invalid credentials."""
