# Generated tracks

Everything in a circuit is generated at launch from a `TrackDefinition`
(`Sources/Racing/Track/TrackDefinition.swift`): the master curve and its
deformers, the swept road hull, the city around it and every texture.

Launch arguments: `-autostart YES` skips the menu and starts a race; `-track <0...3>`
picks a library circuit, `-seed <n>` generates a new one, `-ship <0...5>` picks the ship
and `-laps <n>` the distance. `-autoDrive YES` runs the demo (every ship flown by the rival
driver, no countdown). `-recordVideos <dir>` renders an overview, a start-line shot and a
drive-through per circuit instead of starting the game (`-recordStillsOnly YES` for stills only).

## Handling checks

`-driver <name>` replaces the player's thumb and prints race telemetry every two seconds
(position, distance, speed, wall hits, seconds spent scraping). It is the quickest check of
a handling or assist change:

- `rival`: the rival driver flies the player's ship. The reference lap.
- `casual`: steers a quarter of a second late and never airbrakes. Should finish mid-pack on Normal.
- `handsoff`: no input at all. Should come last, with or without the wall guard; if it
  stops being last, the assist has started to drive.

Add `-menu.assist NO` to run any of them with the wall guard off.

```sh
xcrun simctl launch --console-pty booted com.racing.app -autostart YES -driver casual -laps 1
```
