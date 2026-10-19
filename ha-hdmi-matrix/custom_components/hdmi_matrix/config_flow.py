from __future__ import annotations

import logging
from collections.abc import Mapping
from typing import Any

import voluptuous as vol
from homeassistant import config_entries
from homeassistant.config_entries import ConfigFlowResult
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResult
from homeassistant.exceptions import HomeAssistantError

from .const import CONF_HOST, CONF_PASSWORD, CONF_USERNAME, DEFAULT_PASSWORD, DEFAULT_USERNAME, DOMAIN
from .matrix_client import MatrixAuthError, MatrixClient, MatrixError

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
    except MatrixAuthError as err:
        raise InvalidAuth from err
    except MatrixError as err:
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

    async def async_step_reauth(self, entry_data: Mapping[str, Any]) -> ConfigFlowResult:
        """Ask for credentials again without creating a new config entry."""
        return await self.async_step_reauth_confirm()

    async def async_step_reauth_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        entry = self._get_reauth_entry()
        errors: dict[str, str] = {}
        if user_input is not None:
            data = {**entry.data, **user_input}
            try:
                await _validate(self.hass, data)
            except CannotConnect:
                errors["base"] = "cannot_connect"
            except InvalidAuth:
                errors["base"] = "invalid_auth"
            except Exception:  # noqa: BLE001
                _LOGGER.exception("Unexpected exception validating HDMI matrix reauthentication")
                errors["base"] = "unknown"
            else:
                return self.async_update_reload_and_abort(
                    entry, data=data, reason="reauth_successful"
                )

        schema = vol.Schema({
            vol.Required(CONF_USERNAME, default=entry.data[CONF_USERNAME]): str,
            vol.Required(CONF_PASSWORD): str,
        })
        return self.async_show_form(step_id="reauth_confirm", data_schema=schema, errors=errors)

    async def async_step_reconfigure(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        """Change the matrix host while preserving the existing entry ID."""
        entry = self._get_reconfigure_entry()
        errors: dict[str, str] = {}
        if user_input is not None:
            data = {**entry.data, **user_input}
            try:
                info = await _validate(self.hass, data)
            except CannotConnect:
                errors["base"] = "cannot_connect"
            except InvalidAuth:
                errors["base"] = "invalid_auth"
            except Exception:  # noqa: BLE001
                _LOGGER.exception("Unexpected exception validating HDMI matrix reconfiguration")
                errors["base"] = "unknown"
            else:
                return self.async_update_reload_and_abort(
                    entry,
                    data=data,
                    unique_id=data[CONF_HOST],
                    title=info["title"],
                    reason="reconfigure_successful",
                )

        schema = vol.Schema({
            vol.Required(CONF_HOST, default=entry.data[CONF_HOST]): str,
        })
        return self.async_show_form(step_id="reconfigure", data_schema=schema, errors=errors)


class CannotConnect(HomeAssistantError):
    """Error to indicate we cannot connect."""


class InvalidAuth(HomeAssistantError):
    """Error to indicate invalid credentials."""
