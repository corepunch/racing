# Generated tracks

Everything in a circuit is generated at launch from a `TrackDefinition`
(`Sources/Racing/Track/TrackDefinition.swift`): the master curve and its
deformers, the swept road hull, the city around it and every texture.

Launch arguments: `-track <0...3>` picks a library circuit, `-seed <n>` generates
a new one, `-autoDrive YES` runs the demo. `-recordVideos <dir>` renders an
overview, a start-line shot and a drive-through per circuit instead of starting
the game (`-recordStillsOnly YES` for stills only).

## Car physics check

This opens a small SceneKit window on macOS and checks four-wheel ground contact,
forward acceleration, right steering, braking, automatic reverse, and the return
to forward drive on a flat surface using the
production controller. Run from the repository root:

```sh
swiftc Sources/Racing/Game/PhysicsCategory.swift Sources/Racing/Car/CarController.swift Tools/check_car_collisions.swift -o /tmp/RacingCollisionCheck
/tmp/RacingCollisionCheck
```
