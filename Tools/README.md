# Generated tracks

Everything in a circuit is generated at launch from a `TrackDefinition`
(`Sources/Racing/Track/TrackDefinition.swift`): the master curve and its
deformers, the swept road hull, the city around it and every texture.

Launch arguments: `-autostart YES` skips the menu and starts a race; `-track <0...3>`
picks a library circuit, `-seed <n>` generates a new one, `-car <0...5>` picks the car
and `-laps <n>` the distance. `-autoDrive YES` runs the demo (the car glides round the centre line
driver, no countdown). `-recordVideos <dir>` renders an overview, a start-line shot and a
drive-through per circuit instead of starting the game (`-recordStillsOnly YES` for stills only).

## Handling checks

`-driver <name>` replaces the player's thumb and prints race telemetry every two seconds
(position, distance, speed, wall hits, seconds spent scraping). It is the quickest check of
a handling or assist change:

- `rival`: the rival driver drives the player's car. The reference lap.
- `casual`: steers a quarter of a second late and never brakes. Should finish mid-pack on Normal.
- `handsoff`: no input at all. Should come last, with or without the assist; if it
  stops being last, the assist has started to drive.

Add `-menu.assist NO` to run any of them with the assist off.

```sh
xcrun simctl launch --console-pty booted com.racing.app -autostart YES -driver casual -laps 1
```
