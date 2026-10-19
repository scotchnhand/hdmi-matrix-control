"""Config flow: the "Add Integration -> HDMI Matrix" form."""

from __future__ import annotations

import pytest
from custom_components.hdmi_matrix.const import CONF_HOST, CONF_PASSWORD, CONF_USERNAME, DOMAIN
from custom_components.hdmi_matrix.matrix_client import MatrixAuthError, MatrixError
from homeassistant import config_entries
from homeassistant.data_entry_flow import FlowResultType

USER_INPUT = {CONF_HOST: "matrix.local", CONF_USERNAME: "admin", CONF_PASSWORD: "admin"}


async def _submit(hass, user_input=USER_INPUT):
    result = await hass.config_entries.flow.async_init(DOMAIN, context={"source": config_entries.SOURCE_USER})
    assert result["type"] is FlowResultType.FORM
    return await hass.config_entries.flow.async_configure(result["flow_id"], user_input)


async def test_creates_entry(hass, fake_client):
    result = await _submit(hass)
    assert result["type"] is FlowResultType.CREATE_ENTRY
    assert result["title"] == "HDMI Matrix (192.168.17.238)"
    assert result["data"] == USER_INPUT


@pytest.mark.parametrize(
    ("error", "expected"),
    [
        (MatrixAuthError("Invalid user or password"), "invalid_auth"),
        # An unreachable/timed-out host is a MatrixError too, but must not be
        # reported as bad credentials.
        (MatrixError("Could not reach matrix"), "cannot_connect"),
        (RuntimeError("boom"), "unknown"),
    ],
)
async def test_errors_are_classified(hass, fake_client, error, expected):
    fake_client.fail_with = error
    result = await _submit(hass)
    assert result["type"] is FlowResultType.FORM
    assert result["errors"] == {"base": expected}

    # And the user can recover from the same form.
    fake_client.fail_with = None
    result = await hass.config_entries.flow.async_configure(result["flow_id"], USER_INPUT)
    assert result["type"] is FlowResultType.CREATE_ENTRY


async def test_aborts_if_already_configured(hass, fake_client, config_entry):
    config_entry.add_to_hass(hass)
    result = await _submit(hass)
    assert result["type"] is FlowResultType.ABORT
    assert result["reason"] == "already_configured"


async def test_reauth_updates_password_without_replacing_entry(hass, fake_client, config_entry):
    config_entry.add_to_hass(hass)
    result = await config_entry.start_reauth_flow(hass)
    assert result["type"] is FlowResultType.FORM
    assert result["step_id"] == "reauth_confirm"

    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_USERNAME: "admin", CONF_PASSWORD: "newpass1"}
    )
    assert result["type"] is FlowResultType.ABORT
    assert result["reason"] == "reauth_successful"
    assert config_entry.data[CONF_PASSWORD] == "newpass1"
    assert config_entry.unique_id == "matrix.local"


async def test_reconfigure_updates_host_without_replacing_entry(hass, fake_client, config_entry):
    config_entry.add_to_hass(hass)
    result = await config_entry.start_reconfigure_flow(hass)
    assert result["type"] is FlowResultType.FORM
    assert result["step_id"] == "reconfigure"

    result = await hass.config_entries.flow.async_configure(
        result["flow_id"], {CONF_HOST: "matrix-new.local"}
    )
    assert result["type"] is FlowResultType.ABORT
    assert result["reason"] == "reconfigure_successful"
    assert config_entry.data[CONF_HOST] == "matrix-new.local"
    assert config_entry.unique_id == "matrix-new.local"
