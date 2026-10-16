from __future__ import annotations

from typing import TYPE_CHECKING

from homeassistant.components.button import ButtonEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .coordinator import MatrixCoordinator
from .entity import MatrixEntity

if TYPE_CHECKING:
    from . import MatrixConfigEntry


async def async_setup_entry(
    hass: HomeAssistant, entry: MatrixConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator = entry.runtime_data
    async_add_entities([MatrixRebootButton(coordinator, entry.entry_id)])


class MatrixRebootButton(MatrixEntity, ButtonEntity):
    _attr_name = "Reboot"
    _attr_icon = "mdi:restart"
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str) -> None:
        super().__init__(coordinator, entry_id)
        self._attr_unique_id = f"{entry_id}_reboot"

    async def async_press(self) -> None:
        await self.coordinator.async_reboot()
