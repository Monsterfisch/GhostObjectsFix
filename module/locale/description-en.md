# Ghost Objects Fix

Stops flags, stones, arrows, dust and other small objects from showing up in places where they don't belong.

The game keeps a list of the small objects standing on each tile and draws each list on its own tile.
Sometimes an object is deleted while it is still in a tile's list (the game's own update deletes an object
that links to itself without fixing the tile's list, for one). The next object created in that slot - a tower
flag, a catapult stone, an arrow - is then drawn on the old tile as well, often flickering, and the lists of
different tiles get tangled into each other. Saved games and maps keep the tangle.

This module rebuilds every tile's list from where each object really is, a few times a second, in games and in
the map editor. Works with Stronghold Crusader and Stronghold Crusader Extreme.
