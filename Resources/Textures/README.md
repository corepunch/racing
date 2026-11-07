# Arcade Road Strip

`racing-road.png` is a baked 1024 x 1024 LDR road texture, covering the full
11-metre road width and approximately 12 metres along the track. Two rows of
15-cm white dashes divide the road into three lanes, with 3-metre dashes and
3-metre gaps. Softened paint ends and directionally blurred grain give an
arcade racing appearance without camera motion blur or HDR rendering.

The grain is derived from [ambientCG Asphalt 012](https://ambientcg.com/a/Asphalt012)
by Lennart Demes, licensed [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The original color map is desaturated, contrast-reduced and blurred along the
driving axis. Markings are generated locally; no pixels are copied from the
game screenshot. Original PBR maps are not bundled.

Rebuild from the downloaded CC0 source:

```sh
curl -fL 'https://ambientcg.com/get?file=Asphalt012_2K-JPG.zip' -o /tmp/Asphalt012_2K-JPG.zip
unzip -o /tmp/Asphalt012_2K-JPG.zip 'Asphalt012_2K-JPG_Color.jpg' -d /tmp/racing-road-source
swift Tools/bake_road_texture.swift /tmp/racing-road-source/Asphalt012_2K-JPG_Color.jpg Resources/Textures/racing-road.png
```

UVs clamp across the width and repeat along the track, using an integer repeat
count and duplicated closing vertices to avoid a start/finish seam. Mipmaps
and 16x anisotropic filtering keep distant markings stable.