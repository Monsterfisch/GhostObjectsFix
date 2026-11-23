# Ghost Objects Fix

## UCP package

Repairs tile object lists so flags, stones, arrows and other small objects stop appearing on unrelated tiles. The repair interval is configurable.

- Module directory: `module/`
- Targets: Stronghold Crusader 1.41 and Stronghold Crusader Extreme 1.41
- Requires UCP framework 3.0.7 and frontend 1.0.2 or a compatible later version
- Requires Map Extensions 1.x for map and save load callbacks


A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme: stops flags, stones, arrows,
dust and other small objects from showing up on tiles where they don't belong.

## What it does

Stops flags, stones, arrows, dust and other small objects from showing up in places where they don't belong.

The game keeps a list of the small objects standing on each tile and draws each list on its own tile.
Sometimes an object is deleted while it is still in a tile's list (the game's own update deletes an object
that links to itself without fixing the tile's list, for one). The next object created in that slot - a tower
flag, a catapult stone, an arrow - is then drawn on the old tile as well, often flickering, and the lists of
different tiles get tangled into each other. Saved games and maps keep the tangle.

This module rebuilds every tile's list from where each object really is, a few times a second, in games and in
the map editor. Works with Stronghold Crusader and Stronghold Crusader Extreme.

## Install

Download the zip from the latest release, then in the UCP3 GUI use **Install extension** (or drag
the zip onto the window), press **F5** and enable **Ghost Objects Fix**.
