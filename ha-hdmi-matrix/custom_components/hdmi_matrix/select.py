from __future__ import annotations

from homeassistant.components.select import SelectEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import MatrixCoordinator
from .entity import MatrixEntity


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback) -> None:
    coordinator: MatrixCoordinator = hass.data[DOMAIN][entry.entry_id]
    entities: list[SelectEntity] = []

    for output in coordinator.data["outputs"]:
        entities.append(MatrixRouteSelect(coordinator, entry.entry_id, output["index"]))

    for input_ in coordinator.data["inputs"]:
        entities.append(MatrixEdidSelect(coordinator, entry.entry_id, input_["index"]))

    async_add_entities(entities)


class MatrixRouteSelect(MatrixEntity, SelectEntity):
    """Which input is routed to a given output -- the core "crosspoint" control."""

    _attr_icon = "mdi:video-switch"

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, output_index: int) -> None:
        super().__init__(coordinator, entry_id)
        self._output_index = output_index
        self._attr_unique_id = f"{entry_id}_output{output_index}_route"

    def _output(self) -> dict:
        return next(o for o in self.coordinator.data["outputs"] if o["index"] == self._output_index)

    def _input_by_name(self, name: str) -> dict | None:
        return next((i for i in self.coordinator.data["inputs"] if i["name"] == name), None)

    @property
    def name(self) -> str:
        return f"{self._output()['name']} source"

    @property
    def options(self) -> list[str]:
        return [i["name"] for i in self.coordinator.data["inputs"]]

    @property
    def current_option(self) -> str | None:
        output = self._output()
        matched = next((i for i in self.coordinator.data["inputs"] if i["index"] == output["input_index"]), None)
        return matched["name"] if matched else None

    @property
    def available(self) -> bool:
        return super().available and self._output()["power"]

    async def async_select_option(self, option: str) -> None:
        target = self._input_by_name(option)
        if target is None:
            return
        await self.coordinator.async_set_route(self._output_index, target["index"])


class MatrixEdidSelect(MatrixEntity, SelectEntity):
    """EDID profile advertised to a given input (resolution/channel caps)."""

    _attr_icon = "mdi:monitor-dashboard"
    _attr_entity_category = "config"

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, input_index: int) -> None:
        super().__init__(coordinator, entry_id)
        self._input_index = input_index
        self._attr_unique_id = f"{entry_id}_input{input_index}_edid"

    def _input(self) -> dict:
        return next(i for i in self.coordinator.data["inputs"] if i["index"] == self._input_index)

    def _preset_by_name(self, label: str) -> dict | None:
        return next((p for p in self.coordinator.data["edid_presets"] if self._label(p) == label), None)

    @staticmethod
    def _label(preset: dict) -> str:
        return f"{preset['index']:02d}: {preset['name']}"

    @property
    def name(self) -> str:
        return f"{self._input()['name']} EDID"

    @property
    def options(self) -> list[str]:
        return [self._label(p) for p in self.coordinator.data["edid_presets"]]

    @property
    def current_option(self) -> str | None:
        current_index = self._input()["edid_preset"]
        preset = next((p for p in self.coordinator.data["edid_presets"] if p["index"] == current_index), None)
        return self._label(preset) if preset else None

    async def async_select_option(self, option: str) -> None:
        preset = self._preset_by_name(option)
        if preset is None:
            return
        await self.coordinator.async_set_edid(self._input_index, preset["index"])
