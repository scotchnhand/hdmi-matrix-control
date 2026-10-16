"""The HDMI Matrix integration.

Talks directly to the matrix over its own LAN HTTP protocol (see
matrix_client.py) -- no cloud, no bridge. See README.md in this repo for
why Matter isn't viable for this class of device.
"""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant

from .const import CONF_HOST, CONF_PASSWORD, CONF_USERNAME
from .coordinator import MatrixCoordinator
from .matrix_client import MatrixClient

PLATFORMS: list[Platform] = [Platform.SELECT, Platform.SWITCH, Platform.TEXT, Platform.BUTTON, Platform.SENSOR]

MatrixConfigEntry = ConfigEntry[MatrixCoordinator]


async def async_setup_entry(hass: HomeAssistant, entry: MatrixConfigEntry) -> bool:
    client = MatrixClient(
        entry.data[CONF_HOST],
        entry.data[CONF_USERNAME],
        entry.data[CONF_PASSWORD],
    )
    coordinator = MatrixCoordinator(hass, entry, client)
    await coordinator.async_config_entry_first_refresh()

    entry.runtime_data = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: MatrixConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
