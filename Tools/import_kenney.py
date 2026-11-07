import argparse
import json
from pathlib import Path
import shutil
import sys

import bpy
from mathutils import Vector


parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
parser.add_argument("--asset", action="append", default=[])
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])

formats = {
    "racing-kit": "GLTF format",
    "nature-kit": "GLTF format",
    "city-kit-roads": "GLB format",
}
manifest = []
for pack, model_format in formats.items():
    source = args.source / pack
    destination = args.destination / pack
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / "License.txt", destination / "License.txt")
    for model in sorted((source / "Models" / model_format).glob("*.glb")):
        if args.asset and model.stem not in args.asset:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(model))
        mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
        assert mesh_objects, f"No meshes imported: {model}"
        corners = [obj.matrix_world @ Vector(corner)
                   for obj in mesh_objects for corner in obj.bound_box]
        bounds_min = [min(corner[axis] for corner in corners) for axis in range(3)]
        bounds_max = [max(corner[axis] for corner in corners) for axis in range(3)]
        output = destination / (model.stem + ".usdz")
        bpy.ops.wm.usd_export(
            filepath=str(output), export_materials=True, export_textures_mode="NEW",
            relative_paths=True, convert_orientation=True,
            export_global_up_selection="Y", export_global_forward_selection="NEGATIVE_Z",
            convert_scene_units="METERS",
        )
        assert output.is_file(), f"Export failed: {output}"
        manifest.append({
            "pack": pack, "asset": model.stem,
            "source": str(model.relative_to(args.source)),
            "blenderBoundsMin": bounds_min, "blenderBoundsMax": bounds_max,
            "meshes": len(mesh_objects),
            "materials": len(bpy.data.materials),
            "images": [image.name for image in bpy.data.images],
        })
        print(f"IMPORTED {pack}/{model.stem}: {bounds_min} -> {bounds_max}", flush=True)

manifest_path = args.destination / ("probe.json" if args.asset else "manifest.json")
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Imported {len(manifest)} assets without rescaling.", flush=True)