"""Entity setup and behaviour, inside a real in-process Home Assistant."""

from __future__ import annotations

from datetime import timedelta

import pytest
from custom_components.hdmi_matrix.const import UPDATE_INTERVAL_SECONDS
from custom_components.hdmi_matrix.diagnostics import async_get_config_entry_diagnostics
from custom_components.hdmi_matrix.matrix_client import MatrixError
from homeassistant.config_entries import ConfigEntryState
from homeassistant.const import STATE_OFF, STATE_ON, STATE_UNAVAILABLE, EntityCategory
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers import entity_registry as er
from pytest_homeassistant_custom_component.common import async_fire_time_changed


async def _call(hass, domain, service, entity_id, **data):
    await hass.services.async_call(domain, service, {"entity_id": entity_id, **data}, blocking=True)


async def test_setup_registers_all_entities_with_categories(hass, setup_integration):
    assert setup_integration.state is ConfigEntryState.LOADED
    registry = er.async_get(hass)
    entries = {e.entity_id: e for e in er.async_entries_for_config_entry(registry, setup_integration.entry_id)}

    # 2 route + 4 EDID + 2 audio selects, 2 power switches, 6 name texts,
    # 1 reboot button, 2 diagnostic sensors.
    assert len(entries) == 19

    assert entries["select.hdmi_matrix_windows_edid"].entity_category is EntityCategory.CONFIG
    assert entries["button.hdmi_matrix_reboot"].entity_category is EntityCategory.CONFIG
    assert entries["sensor.hdmi_matrix_firmware"].entity_category is EntityCategory.DIAGNOSTIC
    assert entries["text.hdmi_matrix_input_1_name"].entity_category is EntityCategory.CONFIG
    assert entries["select.hdmi_matrix_left_source"].entity_category is None

    assert hass.states.get("sensor.hdmi_matrix_firmware").state == "V0.0.11"


async def test_unload(hass, setup_integration):
    assert await hass.config_entries.async_unload(setup_integration.entry_id)
    assert setup_integration.state is ConfigEntryState.NOT_LOADED


async def test_route_select(hass, setup_integration, fake_client):
    state = hass.states.get("select.hdmi_matrix_left_source")
    assert state.state == "AppleTv"
    assert state.attributes["options"] == ["Windows", "MacBook", "AppleTv", "MacMini"]

    await _call(hass, "select", "select_option", "select.hdmi_matrix_left_source", option="MacBook")
    await hass.async_block_till_done()
    assert ("set_route", 1, 2) in fake_client.calls
    assert hass.states.get("select.hdmi_matrix_left_source").state == "MacBook"


async def test_route_select_disambiguates_duplicate_input_names(hass, setup_integration, fake_client):
    fake_client.state["inputs"][0]["name"] = "MacBook"
    await setup_integration.runtime_data.async_request_refresh()
    await hass.async_block_till_done()

    state = hass.states.get("select.hdmi_matrix_left_source")
    assert state.attributes["options"] == ["MacBook (1)", "MacBook (2)", "AppleTv", "MacMini"]
    await _call(hass, "select", "select_option", "select.hdmi_matrix_left_source", option="MacBook (2)")
    assert ("set_route", 1, 2) in fake_client.calls


async def test_route_select_available_while_output_off(hass, setup_integration, fake_client):
    # Right is powered off; it should still be routable so automations can
    # pick a source before turning the display on.
    assert hass.states.get("switch.hdmi_matrix_right_power").state == STATE_OFF
    assert hass.states.get("select.hdmi_matrix_right_source").state == "AppleTv"

    await _call(hass, "select", "select_option", "select.hdmi_matrix_right_source", option="Windows")
    assert ("set_route", 2, 1) in fake_client.calls


async def test_power_switch(hass, setup_integration, fake_client):
    await _call(hass, "switch", "turn_on", "switch.hdmi_matrix_right_power")
    await hass.async_block_till_done()
    assert ("set_output_power", 2, True) in fake_client.calls
    assert hass.states.get("switch.hdmi_matrix_right_power").state == STATE_ON


async def test_edid_select(hass, setup_integration, fake_client):
    assert hass.states.get("select.hdmi_matrix_appletv_edid").state == "11: 4K HDR 10Bit 2CH"
    await _call(hass, "select", "select_option", "select.hdmi_matrix_appletv_edid", option="03: 1080P 6CH")
    assert ("set_edid", 3, 3) in fake_client.calls


async def test_command_failure_raises_clean_ha_error(hass, setup_integration, fake_client):
    fake_client.fail_with = MatrixError("Could not reach matrix")
    with pytest.raises(HomeAssistantError, match="HDMI matrix command failed"):
        await _call(hass, "switch", "turn_on", "switch.hdmi_matrix_right_power")


async def _next_poll(hass, freezer) -> None:
    freezer.tick(timedelta(seconds=UPDATE_INTERVAL_SECONDS + 1))
    async_fire_time_changed(hass)
    # Scheduled refreshes run as background tasks.
    await hass.async_block_till_done(wait_background_tasks=True)


async def test_poll_failure_marks_entities_unavailable(hass, setup_integration, fake_client, freezer):
    fake_client.fail_with = MatrixError("timed out")
    await _next_poll(hass, freezer)
    assert hass.states.get("select.hdmi_matrix_left_source").state == STATE_UNAVAILABLE

    fake_client.fail_with = None
    await _next_poll(hass, freezer)
    assert hass.states.get("select.hdmi_matrix_left_source").state == "AppleTv"


async def test_reboot_button(hass, setup_integration, fake_client):
    await _call(hass, "button", "press", "button.hdmi_matrix_reboot")
    assert ("reboot",) in fake_client.calls


# -- audio ----------------------------------------------------------------


async def test_audio_selects_reflect_state(hass, setup_integration):
    arc = hass.states.get("select.hdmi_matrix_audio_return_arc")
    assert arc.state == "Off"
    assert arc.attributes["options"] == ["Off", "Left", "Right"]
    assert arc.attributes["source"] is None

    ext = hass.states.get("select.hdmi_matrix_audio_extraction")
    assert ext.state == "Left"
    # The input actually feeding that output -- what you'd hear.
    assert ext.attributes["source"] == "AppleTv"


async def test_audio_select_sets_value(hass, setup_integration, fake_client):
    await _call(hass, "select", "select_option", "select.hdmi_matrix_audio_return_arc", option="Right")
    await _call(hass, "select", "select_option", "select.hdmi_matrix_audio_extraction", option="Off")
    await hass.async_block_till_done()
    assert ("set_audio", "arc", 2) in fake_client.calls
    assert ("set_audio", "extraction", 0) in fake_client.calls
    assert hass.states.get("select.hdmi_matrix_audio_return_arc").state == "Right"


async def test_audio_select_disambiguates_duplicate_and_reserved_output_names(
    hass, setup_integration, fake_client
):
    fake_client.state["outputs"][0]["name"] = "Off"
    fake_client.state["outputs"][1]["name"] = "Off"
    await setup_integration.runtime_data.async_request_refresh()
    await hass.async_block_till_done()

    state = hass.states.get("select.hdmi_matrix_audio_extraction")
    assert state.attributes["options"] == ["Off", "Off (1)", "Off (2)"]
    await _call(hass, "select", "select_option", "select.hdmi_matrix_audio_extraction", option="Off (2)")
    assert ("set_audio", "extraction", 2) in fake_client.calls


async def test_diagnostics_redact_credentials_and_account(hass, setup_integration):
    diagnostics = await async_get_config_entry_diagnostics(hass, setup_integration)
    assert diagnostics["entry"]["password"] != "admin"
    assert diagnostics["state"]["device"]["account"] != "admin"


# -- renaming -------------------------------------------------------------


async def test_rename_input(hass, setup_integration, fake_client):
    assert hass.states.get("text.hdmi_matrix_input_3_name").state == "AppleTv"
    await _call(hass, "text", "set_value", "text.hdmi_matrix_input_3_name", value="Apple_TV")
    await hass.async_block_till_done()

    assert ("rename_port", "in", 3, "Apple_TV") in fake_client.calls
    assert hass.states.get("text.hdmi_matrix_input_3_name").state == "Apple_TV"
    # The route select's options follow the new name; its entity_id doesn't change.
    assert "Apple_TV" in hass.states.get("select.hdmi_matrix_left_source").attributes["options"]


async def test_rename_output_updates_audio_options(hass, setup_integration, fake_client):
    await _call(hass, "text", "set_value", "text.hdmi_matrix_output_1_name", value="Projector")
    await hass.async_block_till_done()
    ext = hass.states.get("select.hdmi_matrix_audio_extraction")
    assert ext.attributes["options"] == ["Off", "Projector", "Right"]
    assert ext.state == "Projector"


@pytest.mark.parametrize(
    ("entity_id", "value"),
    [
        ("text.hdmi_matrix_input_1_name", "MacBook"),  # duplicate input name
        ("text.hdmi_matrix_output_2_name", "Left"),  # duplicate output name
        ("text.hdmi_matrix_output_2_name", "Off"),  # collides with audio "Off"
    ],
)
async def test_rename_rejects_ambiguous_names(hass, setup_integration, fake_client, entity_id, value):
    with pytest.raises(ServiceValidationError):
        await _call(hass, "text", "set_value", entity_id, value=value)
    assert not any(c[0] == "rename_port" for c in fake_client.calls)


async def test_rename_rejects_invalid_chars(hass, setup_integration, fake_client):
    # HA's text entity enforces the pattern/length before we're called.
    with pytest.raises(ValueError):
        await _call(hass, "text", "set_value", "text.hdmi_matrix_input_1_name", value="has space")
    assert not any(c[0] == "rename_port" for c in fake_client.calls)
