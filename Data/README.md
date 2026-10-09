# Adding a planet

1. Add the sprite image under `Textures`.
2. Duplicate a `Planet*.tres` resource in this folder. Set a unique ID, name, distance, description, resource values, and sprite.
3. In `SolarMap.tscn`, duplicate a `PlanetMarker` under `MapViewport/World/PlanetMarkers`. Assign the new data resource and place the marker in the scene.

The map reads the authored markers and expands its pan area to fit them. No gameplay script changes are needed for new planets.
