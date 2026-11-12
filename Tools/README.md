# Prop Placement

`TrackDecorations` normalizes imported templates before placing them:

- Y is up; local -Z is forward; local +X is right.
- The pivot is the horizontal bounding-box center at the lowest Y coordinate.
- Axis corrections happen inside the template, before centering and placement.
- Barriers and fences rotate 90 degrees around Y so their long axis follows -Z.
- Arches span X. Grandstand entrances and lamp faces point toward -Z.
- Placement aligns -Z to the track tangent or the inward road-facing direction.
- Source geometry, materials, dimensions, and existing placement scales are retained.

Do not compensate for an asset's native pivot or axes at individual call sites.
Normalize a newly introduced asset in the template loader instead.

## Regression Check

Run from the repository root on macOS. This compiles the production car and
track code and loads the real resources; no simulator or game build is needed.
It checks truck dimensions and grounding, road markings and UV continuity,
and prop placement. The four Kenney trucks use 1.4x scale: 2.10 m wide and
3.92-4.06 m long, fitting the 3.67 m lanes.

```sh
mkdir -p /tmp/RacingPropsCheck.app/Contents/MacOS
ln -sfn "$PWD/Resources" /tmp/RacingPropsCheck.app/Contents/Resources
swiftc Sources/Racing/Car/CarStyle.swift Sources/Racing/Car/CarNode.swift Sources/Racing/Track/TrackPath.swift Sources/Racing/Track/TrackMesh.swift Sources/Racing/Game/PhysicsCategory.swift Tools/check_prop_placement.swift -o /tmp/RacingPropsCheck.app/Contents/MacOS/RacingPropsCheck
/tmp/RacingPropsCheck.app/Contents/MacOS/RacingPropsCheck
```
## Car collision check

This opens a small SceneKit window on macOS and checks that the production car
controller lands on terrain, responds to a slope, and cannot tunnel through a
transparent obstacle at high speed. Run from the repository root:

```sh
swiftc Sources/Racing/Game/PhysicsCategory.swift Sources/Racing/Car/CarController.swift Tools/check_car_collisions.swift -o /tmp/RacingCollisionCheck
/tmp/RacingCollisionCheck
```
