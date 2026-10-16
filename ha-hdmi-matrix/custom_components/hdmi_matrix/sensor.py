from __future__ import annotations

from homeassistant.components.sensor import SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import MatrixCoordinator
from .entity import MatrixEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    coordinator: MatrixCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([
        MatrixDeviceSensor(coordinator, entry.entry_id, "ip", "IP address", "mdi:ip-network"),
        MatrixDeviceSensor(coordinator, entry.entry_id, "firmware", "Firmware", "mdi:chip"),
    ])


class MatrixDeviceSensor(MatrixEntity, SensorEntity):
    _attr_entity_category = "diagnostic"

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, field: str, label: str, icon: str) -> None:
        super().__init__(coordinator, entry_id)
        self._field = field
        self._attr_name = label
        self._attr_icon = icon
        self._attr_unique_id = f"{entry_id}_{field}"

    @property
    def native_value(self) -> str | None:
        return self.coordinator.data["device"].get(self._field)
