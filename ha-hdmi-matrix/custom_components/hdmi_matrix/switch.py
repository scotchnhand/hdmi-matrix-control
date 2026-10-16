from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import MatrixCoordinator
from .entity import MatrixEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    coordinator: MatrixCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities(
        MatrixOutputPowerSwitch(coordinator, entry.entry_id, output["index"])
        for output in coordinator.data["outputs"]
    )


class MatrixOutputPowerSwitch(MatrixEntity, SwitchEntity):
    """Power state of one HDMI output."""

    _attr_icon = "mdi:television"
    _attr_device_class = "outlet"

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, output_index: int) -> None:
        super().__init__(coordinator, entry_id)
        self._output_index = output_index
        self._attr_unique_id = f"{entry_id}_output{output_index}_power"

    def _output(self) -> dict:
        return next(o for o in self.coordinator.data["outputs"] if o["index"] == self._output_index)

    @property
    def name(self) -> str:
        return f"{self._output()['name']} power"

    @property
    def is_on(self) -> bool:
        return self._output()["power"]

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self.coordinator.async_set_output_power(self._output_index, True)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self.coordinator.async_set_output_power(self._output_index, False)
