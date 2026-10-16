from __future__ import annotations

from homeassistant.components.button import ButtonEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import MatrixCoordinator
from .entity import MatrixEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    coordinator: MatrixCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([MatrixRebootButton(coordinator, entry.entry_id)])


class MatrixRebootButton(MatrixEntity, ButtonEntity):
    _attr_name = "Reboot"
    _attr_icon = "mdi:restart"
    _attr_entity_category = "config"

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str) -> None:
        super().__init__(coordinator, entry_id)
        self._attr_unique_id = f"{entry_id}_reboot"

    async def async_press(self) -> None:
        await self.coordinator.async_reboot()
