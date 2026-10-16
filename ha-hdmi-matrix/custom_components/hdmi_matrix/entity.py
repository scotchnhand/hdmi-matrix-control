from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import MatrixCoordinator


class MatrixEntity(CoordinatorEntity[MatrixCoordinator]):
    """Base entity sharing one HA device per physical matrix."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str) -> None:
        super().__init__(coordinator)
        self._entry_id = entry_id

    @property
    def device_info(self) -> DeviceInfo:
        device = self.coordinator.data["device"]
        return DeviceInfo(
            identifiers={(DOMAIN, self._entry_id)},
            name="HDMI Matrix",
            manufacturer="Generic",
            model="4x2 HDMI Matrix",
            sw_version=device.get("firmware"),
            configuration_url=f"http://{device.get('ip')}" if device.get("ip") else None,
        )
