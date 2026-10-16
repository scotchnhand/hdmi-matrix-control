from __future__ import annotations

from typing import TYPE_CHECKING

from homeassistant.components.text import TextEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .coordinator import MatrixCoordinator
from .entity import MatrixEntity
from .matrix_client import NAME_RE
from .select import AUDIO_OFF

if TYPE_CHECKING:
    from . import MatrixConfigEntry

# kind -> (coordinator data key, protocol kind, label)
PORT_KINDS = {
    "input": ("inputs", "in", "Input"),
    "output": ("outputs", "out", "Output"),
}


async def async_setup_entry(
    hass: HomeAssistant, entry: MatrixConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator = entry.runtime_data
    async_add_entities(
        MatrixPortNameText(coordinator, entry.entry_id, kind, port["index"])
        for kind, (key, _, _) in PORT_KINDS.items()
        for port in coordinator.data[key]
    )


class MatrixPortNameText(MatrixEntity, TextEntity):
    """The name the matrix stores for one input or output port.

    The entity's own name is positional ("Input 3 name") rather than the
    port's current name, so renaming a port never renames this entity.
    """

    _attr_icon = "mdi:rename"
    _attr_entity_category = EntityCategory.CONFIG
    _attr_native_min = 3
    _attr_native_max = 15
    _attr_pattern = NAME_RE.pattern

    def __init__(self, coordinator: MatrixCoordinator, entry_id: str, kind: str, index: int) -> None:
        super().__init__(coordinator, entry_id)
        self._key, self._protocol_kind, label = PORT_KINDS[kind]
        self._index = index
        self._attr_name = f"{label} {index} name"
        self._attr_unique_id = f"{entry_id}_{kind}{index}_name"

    @property
    def native_value(self) -> str | None:
        port = next((p for p in self.coordinator.data[self._key] if p["index"] == self._index), None)
        return port["name"] if port else None

    async def async_set_value(self, value: str) -> None:
        value = value.strip()
        if not NAME_RE.match(value):
            raise ServiceValidationError("Name must be 3-15 letters, numbers, or underscores")
        # Route and audio selects identify ports by name, so names must stay
        # unique within a kind, and an output can't take the audio "Off" option.
        if any(p["name"] == value and p["index"] != self._index for p in self.coordinator.data[self._key]):
            raise ServiceValidationError(f"Another {self._key[:-1]} is already named {value}")
        if self._key == "outputs" and value == AUDIO_OFF:
            raise ServiceValidationError(f"{AUDIO_OFF!r} is reserved for the audio selects")
        await self.coordinator.async_rename_port(self._protocol_kind, self._index, value)
