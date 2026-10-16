"""DataUpdateCoordinator that polls the matrix's state over the LAN.

The matrix client itself is synchronous (plain urllib, matching the device's
own tiny HTTP server, which isn't given to keeping a persistent HA
aiohttp connection open well) so all of its calls run in HA's executor
via hass.async_add_executor_job, which is the standard pattern for
wrapping a blocking library in HA.
"""

from __future__ import annotations

import logging
from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN, UPDATE_INTERVAL_SECONDS
from .matrix_client import MatrixClient, MatrixError

_LOGGER = logging.getLogger(__name__)


class MatrixCoordinator(DataUpdateCoordinator[dict]):
    def __init__(self, hass: HomeAssistant, client: MatrixClient) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=timedelta(seconds=UPDATE_INTERVAL_SECONDS),
        )
        self.client = client

    async def _async_update_data(self) -> dict:
        try:
            return await self.hass.async_add_executor_job(self.client.get_state)
        except MatrixError as err:
            raise UpdateFailed(str(err)) from err

    async def async_set_route(self, output: int, input_: int) -> None:
        await self.hass.async_add_executor_job(self.client.set_route, output, input_)
        await self.async_request_refresh()

    async def async_set_output_power(self, output: int, on: bool) -> None:
        await self.hass.async_add_executor_job(self.client.set_output_power, output, on)
        await self.async_request_refresh()

    async def async_set_edid(self, input_: int, preset: int) -> None:
        await self.hass.async_add_executor_job(self.client.set_edid, input_, preset)
        await self.async_request_refresh()

    async def async_reboot(self) -> None:
        await self.hass.async_add_executor_job(self.client.reboot)
