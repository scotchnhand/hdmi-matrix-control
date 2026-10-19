from __future__ import annotations

from typing import TYPE_CHECKING, Any

from homeassistant.components.select import SelectEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .coordinator import MatrixCoordinator
from .entity import MatrixEntity

if TYPE_CHECKING:
    from . import MatrixConfigEntry

AUDIO_OFF = "Off"


def _port_labels(ports: list[dict], reserved: set[str] | frozenset[str] = frozenset()) -> dict[int, str]:
    """Return stable, unambiguous option labels keyed by port index."""
    counts: dict[str, int] = {}
    for port in ports:
        counts[port["name"]] = counts.get(port["name"], 0) + 1
    return {
        port["index"]: (
            f"{port['name']} ({port['index']})"
            if counts[port["name"]] > 1 or port["name"] in reserved
            else port["name"]
        )
        for port in ports
    }


async def async_setup_entry(
    hass: HomeAssistant, entry: MatrixConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator = entry.runtime_data
    entities: list[SelectEntity] = []

    for output in coordinator.data["outputs"]:
        entities.append(MatrixRouteSelect(coordinator, entry.entry_id, output["index"]))

    for input_ in coordinator.data["inputs"]:
        entities.append(MatrixEdidSelect(coordinator, entry.entry_id, input_["index"]))

    entities.append(MatrixAudioSelect(coordinator, entry.entry_id, "arc", "Audio return (ARC)", "mdi:audio-input-rca"))
    entities.append(MatrixAudioSelect(coordinator, entry.entry_id, "extraction", "Audio extraction", "mdi:speaker"))

    async_add_entities(entities)


class MatrixRouteSelect(MatrixEntity, SelectEntity):
    """Which input is routed to a given output -- the core "crosspoint" control.

    Deliberately stays available while the output is powered off: the matrix
    accepts routing changes either way, so automations can pick the source
    before turning the display on.
    """

    _attr_icon = "mdi:video-switch"

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, output_index: int) -> None:
        super().__init__(coordinator, entry_id)
        self._output_index = output_index
        self._attr_unique_id = f"{entry_id}_output{output_index}_route"

    def _output(self) -> dict:
        return next(o for o in self.coordinator.data["outputs"] if o["index"] == self._output_index)

    def _input_by_option(self, option: str) -> dict | None:
        labels = _port_labels(self.coordinator.data["inputs"])
        return next((i for i in self.coordinator.data["inputs"] if labels[i["index"]] == option), None)

    @property
    def name(self) -> str:
        return f"{self._output()['name']} source"

    @property
    def options(self) -> list[str]:
        labels = _port_labels(self.coordinator.data["inputs"])
        return [labels[i["index"]] for i in self.coordinator.data["inputs"]]

    @property
    def current_option(self) -> str | None:
        output = self._output()
        matched = next((i for i in self.coordinator.data["inputs"] if i["index"] == output["input_index"]), None)
        return _port_labels(self.coordinator.data["inputs"]).get(matched["index"]) if matched else None

    async def async_select_option(self, option: str) -> None:
        target = self._input_by_option(option)
        if target is None:
            raise ServiceValidationError(f"Unknown input: {option}")
        await self.coordinator.async_set_route(self._output_index, target["index"])


class MatrixEdidSelect(MatrixEntity, SelectEntity):
    """EDID profile advertised to a given input (resolution/channel caps)."""

    _attr_icon = "mdi:monitor-dashboard"
    _attr_entity_category = EntityCategory.CONFIG

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
            raise ServiceValidationError(f"Unknown EDID preset: {option}")
        await self.coordinator.async_set_edid(self._input_index, preset["index"])


class MatrixAudioSelect(MatrixEntity, SelectEntity):
    """Which output's audio feeds the ARC / extraction port, or Off.

    The protocol's values are 0=off, 1=Out-A (output 1), 2=Out-B (output 2).
    Options use the *output* names rather than the routed input's name (as the
    web app's buttons do) so they only change on a rename, not on every
    re-route -- automations need stable option strings. The input currently
    feeding that output is exposed as the `source` attribute instead.
    """

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, mode: str, label: str, icon: str) -> None:
        super().__init__(coordinator, entry_id)
        self._mode = mode
        self._attr_name = label
        self._attr_icon = icon
        self._attr_unique_id = f"{entry_id}_audio_{mode}"

    def _output(self, index: int) -> dict | None:
        return next((o for o in self.coordinator.data["outputs"] if o["index"] == index), None)

    @property
    def options(self) -> list[str]:
        labels = _port_labels(self.coordinator.data["outputs"], {AUDIO_OFF})
        return [AUDIO_OFF, *(labels[o["index"]] for o in self.coordinator.data["outputs"])]

    @property
    def current_option(self) -> str | None:
        value = self.coordinator.data["audio"][self._mode]["value"]
        if value == 0:
            return AUDIO_OFF
        output = self._output(value)
        return _port_labels(self.coordinator.data["outputs"], {AUDIO_OFF}).get(output["index"]) if output else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        value = self.coordinator.data["audio"][self._mode]["value"]
        output = self._output(value)
        if output is None:
            return {"source": None}
        source = next((i for i in self.coordinator.data["inputs"] if i["index"] == output["input_index"]), None)
        return {"source": source["name"] if source else None}

    async def async_select_option(self, option: str) -> None:
        if option == AUDIO_OFF:
            value = 0
        else:
            labels = _port_labels(self.coordinator.data["outputs"], {AUDIO_OFF})
            output = next((o for o in self.coordinator.data["outputs"] if labels[o["index"]] == option), None)
            if output is None:
                raise ServiceValidationError(f"Unknown audio source: {option}")
            value = output["index"]
        await self.coordinator.async_set_audio(self._mode, value)
