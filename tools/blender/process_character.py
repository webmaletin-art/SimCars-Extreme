"""Prepara un personaje (Character Creator → GLB de «A la deriva») para el juego. Se ejecuta con bpy:
    python tools/blender/process_character.py --src <carpeta con Aiden/Aiden.glb …> --out godot/game/models/characters [Aiden Kate Mujer_adulta]
  · aplica rotación y escala (el esqueleto queda en metros, +Y arriba, mirando a +Z como un modelo de Mixamo);
  · borra las formas de la cara (122 shape keys: pesan y el juego no las usa), el icosaedro auxiliar y los trozos transparentes de la cara;
  · reduce triángulos (cuerpo, pelo, traje) y texturas a 1024 px (4 MB en vez de 35 MB);
  · exporta <Nombre>.glb y <Nombre>.json (altura real)."""
import bpy, sys, os, json, math
import bmesh
from mathutils import Vector

TARGET = {"EM3D_Base_Body": 11000, "Slicked_Back_Side": 5000, "TRAJE_MONO": 5000, "Female_Flat": 800, "EM3D_Base_Teeth": 600, "COLLAR": 400, "TRAJE_BOTAS": 400}
DROP = ["Icosphere", "EM3D_Base_Tongue", "EM3D_Base_TearLine", "EM3D_Base_EyeOEM3Dlusion"]

def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)

def decimate(o, target):
    t = tris(o)
    if t <= target:
        return
    bm = bmesh.new(); bm.from_mesh(o.data); bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002); bm.to_mesh(o.data); bm.free()
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects: x.select_set(False)
    o.select_set(True)
    md = o.modifiers.new("d", "DECIMATE"); md.decimate_type = "COLLAPSE"; md.ratio = max(0.03, target / tris(o)); md.delimit = set(); md.use_collapse_triangulate = True
    # el modificador de armadura va antes: se mueve el decimado al principio para que no deforme
    bpy.ops.object.modifier_move_to_index(modifier=md.name, index=0)
    bpy.ops.object.modifier_apply(modifier=md.name)

def run(name, src_dir, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src_dir, name, name + ".glb"))
    for o in list(bpy.data.objects):
        if o.type == "MESH" and any(o.name.startswith(d) for d in DROP):
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    # colores del traje (el GLB original los perdió: viajaban sólo en el .blend)
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type != "BSDF_PRINCIPLED":
                continue
            if m.name.startswith("traje_tela"):
                n.inputs["Base Color"].default_value = (0.035, 0.055, 0.095, 1)
                n.inputs["Roughness"].default_value = 0.55
            elif m.name.startswith("traje_luz"):
                n.inputs["Base Color"].default_value = (0, 0, 0, 1)
                n.inputs["Emission Color"].default_value = (0.15, 0.65, 1.0, 1)
                n.inputs["Emission Strength"].default_value = 2.5
            elif m.name.startswith("traje_bota"):
                n.inputs["Base Color"].default_value = (0.03, 0.032, 0.04, 1)
    # el cuerpo desnudo queda tapado por el traje: sólo se conservan cabeza, cuello y manos (si no, la piel asoma por el traje al simplificar)
    for o in meshes:
        if o.name == "EM3D_Base_Body":
            keep_names = ("Head", "Jaw", "Eye", "Neck", "Facial", "Teeth", "Tongue", "Hand", "Index", "Mid", "Ring", "Pinky", "Thumb")
            bm = bmesh.new(); bm.from_mesh(o.data)
            dl = bm.verts.layers.deform.verify()
            names = {vg.index: vg.name for vg in o.vertex_groups}
            keep = set()
            for v in bm.verts:
                w = v[dl]
                if not w:
                    continue
                top = max(w.items(), key=lambda kv: kv[1])[0]
                nm = names.get(top, "")
                if any(k in nm for k in keep_names) and "Twist" not in nm.replace("NeckTwist", "Neck"):
                    keep.add(v.index)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if any(v.index not in keep for v in f.verts)], context="FACES")
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
            bm.to_mesh(o.data); bm.free()
    for o in meshes:
        if o.data.shape_keys:
            o.shape_key_clear()
    # aplicar transformaciones (esqueleto en metros)
    for o in bpy.data.objects: o.select_set(False)
    for o in bpy.data.objects:
        if o.type in ("MESH", "ARMATURE"):
            o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in meshes:
        hit = False
        for key, t in TARGET.items():
            if o.name.startswith(key):
                decimate(o, t)
                hit = True
        if not hit and tris(o) > 7000:  # cualquier otra malla grande (pelo y ropa cambian de nombre en cada personaje)
            decimate(o, 5000 if "Hair" in o.name or "hair" in o.name else 6000)
    for img in bpy.data.images:
        if max(img.size) > 1024:
            f = 1024 / max(img.size); img.scale(max(4, int(img.size[0] * f)), max(4, int(img.size[1] * f)))
    mn = Vector((1e9,) * 3); mx = -mn
    for o in meshes:
        if o.name in bpy.data.objects:
            for c in o.bound_box:
                p = o.matrix_world @ Vector(c)
                mn = Vector(map(min, mn, p)); mx = Vector(map(max, mx, p))
    os.makedirs(out_dir, exist_ok=True)
    glb = os.path.join(out_dir, name.lower() + ".glb")
    for o in bpy.data.objects: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True, export_cameras=False, export_lights=False, export_animations=False,
                              export_morph=False, export_skins=True, export_image_format="AUTO")
    meta = {"id": name.lower(), "height": round(mx.z - mn.z, 3), "tris": sum(tris(o) for o in bpy.data.objects if o.type == "MESH"), "mb": round(os.path.getsize(glb) / 1e6, 2)}
    json.dump(meta, open(os.path.join(out_dir, name.lower() + ".json"), "w"))
    print("OK", meta)

if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src, out, names, i = "", "", [], 0
    while i < len(a):
        if a[i] == "--src": src = a[i + 1]; i += 2
        elif a[i] == "--out": out = a[i + 1]; i += 2
        else: names.append(a[i]); i += 1
    for n in names or ["Aiden", "Kate", "Mujer_adulta"]:
        run(n, src, out)
