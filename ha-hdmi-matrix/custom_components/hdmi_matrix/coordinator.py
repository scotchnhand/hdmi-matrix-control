"""DataUpdateCoordinator that polls the matrix's state over the LAN.

The matrix client itself is synchronous (plain urllib, matching the device's
own tiny HTTP server, which isn't given to keeping a persistent HA
aiohttp connection open well) so all of its calls run in HA's executor
via hass.async_add_executor_job, which is the standard pattern for
wrapping a blocking library in HA.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from datetime import timedelta
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN, UPDATE_INTERVAL_SECONDS
from .matrix_client import MatrixClient, MatrixError

if TYPE_CHECKING:
    from homeassistant.config_entries import ConfigEntry

_LOGGER = logging.getLogger(__name__)


class MatrixCoordinator(DataUpdateCoordinator[dict]):
    def __init__(self, hass: HomeAssistant, entry: ConfigEntry, client: MatrixClient) -> None:
        super().__init__(
            hass,
            _LOGGER,
            config_entry=entry,
            name=DOMAIN,
            update_interval=timedelta(seconds=UPDATE_INTERVAL_SECONDS),
        )
        self.client = client

    async def _async_update_data(self) -> dict:
        try:
            return await self.hass.async_add_executor_job(self.client.get_state)
        except MatrixError as err:
            raise UpdateFailed(str(err)) from err

    async def _command(self, func: Callable[..., Any], *args: Any, refresh: bool = True) -> None:
        """Run a client command, surfacing device errors as a clean HA error."""
        try:
            await self.hass.async_add_executor_job(func, *args)
        except MatrixError as err:
            raise HomeAssistantError(f"HDMI matrix command failed: {err}") from err
        if refresh:
            await self.async_request_refresh()

    async def async_set_route(self, output: int, input_: int) -> None:
        await self._command(self.client.set_route, output, input_)

    async def async_set_output_power(self, output: int, on: bool) -> None:
        await self._command(self.client.set_output_power, output, on)

    async def async_set_edid(self, input_: int, preset: int) -> None:
        await self._command(self.client.set_edid, input_, preset)

    async def async_set_audio(self, mode: str, value: int) -> None:
        await self._command(self.client.set_audio, mode, value)

    async def async_rename_port(self, kind: str, index: int, name: str) -> None:
        await self._command(self.client.rename_port, kind, index, name)

    async def async_reboot(self) -> None:
        # No refresh: the device is going away for a while, and the next
        # scheduled poll will mark entities unavailable until it's back.
        await self._command(self.client.reboot, refresh=False)
