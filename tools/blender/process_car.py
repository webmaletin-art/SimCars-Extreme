"""Procesa un auto original (GLB estilo GTA) y lo deja listo para el juego. Se ejecuta con bpy (Blender 5.x):

    python tools/blender/process_car.py --cars /ruta/a/autos [--out godot/game/models/cars] [id ...]

Qué hace (todo medido sobre la geometría, nada a ojo):
  1. Hornea las transformaciones y borra variantes / piezas internas que no se ven (recetas en recipes.py).
  2. RUEDAS: las que ya vienen se limpian; si el modelo trae una sola (o dos), se COPIA a las cuatro esquinas. La copia del lado opuesto se gira
     180° sobre el eje vertical (no se espeja), así la cara de afuera queda AFUERA y los rayos conservan su sentido.
  3. Apoya el auto en el piso (y = 0 en la base de las cuatro ruedas) y pone el eje delantero a «a» metros del origen (el origen es el centro de
     gravedad: así el modelo coincide con la física de la ficha de vehicles.json).
  4. Reduce triángulos (carrocería = budget; cada rueda ≤ 3.000) y texturas (≤ 1024 px).
  5. Agrupa las piezas que se rompen: part_<nombre>/ok y part_<nombre>/dam, cada pieza con su origen en el centro.
  6. Exporta <id>.glb + <id>.json (medidas reales para la ficha de física, posición del volante, piezas).
"""
import bpy, sys, os, json, math, re
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from recipes import CARS  # noqa: E402

WHEEL_TRIS = 3000
MAX_TEX = 1024


def g2b(v):  # glTF (x, y, z) -> Blender (x, -z, y)
    return Vector((v[0], -v[2], v[1]))


def b2g(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def tris(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def bbox(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = -mn
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            mn = Vector((min(mn.x, p.x), min(mn.y, p.y), min(mn.z, p.z)))
            mx = Vector((max(mx.x, p.x), max(mx.y, p.y), max(mx.z, p.z)))
    return mn, mx


def decimate(obj, target):
    t = tris(obj)
    if t <= target or t < 200:
        return
    ratio = max(0.02, target / t)
    src = obj.copy()  # copia sin tocar: de ella se copian las normales al final (la forma simplificada conserva el sombreado original)
    src.data = obj.data.copy()
    bpy.context.collection.objects.link(src)
    src.hide_render = True
    # el importador de glTF parte los vértices por normal/UV: se sueldan por posición para que la reducción pueda colapsar (los UV quedan en los «loops»)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002)
    bm.to_mesh(obj.data)
    bm.free()
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    md0 = obj.modifiers.new("pl", "DECIMATE")
    md0.decimate_type = "DISSOLVE"
    md0.angle_limit = math.radians(3.0)
    md0.delimit = {"MATERIAL", "UV"}
    bpy.ops.object.modifier_apply(modifier=md0.name)
    if tris(obj) <= target:
        bpy.data.objects.remove(src, do_unlink=True)
        return
    ratio = max(0.02, target / tris(obj))
    md = obj.modifiers.new("dec", "DECIMATE")
    md.decimate_type = "COLLAPSE"
    md.ratio = ratio
    md.use_collapse_triangulate = True
    md.delimit = set()
    md.use_dissolve_boundaries = False
    bpy.ops.object.modifier_apply(modifier=md.name)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
        dt = obj.modifiers.new("nrm", "DATA_TRANSFER")
        dt.object = src
        dt.use_loop_data = True
        dt.data_types_loops = {"CUSTOM_NORMAL"}
        dt.loop_mapping = "POLYINTERP_NEAREST"
        bpy.ops.object.modifier_apply(modifier=dt.name)
    except Exception as e:
        print("normales:", e)
    bpy.data.objects.remove(src, do_unlink=True)


def bake_world(obj):
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.data = obj.data.copy()
    obj.data.transform(mw)
    if mw.determinant() < 0:
        obj.data.flip_normals()
    obj.matrix_world = Matrix.Identity(4)


def move_obj(obj, delta):
    obj.data.transform(Matrix.Translation(delta))


def run(car_id, cars_dir, out_dir, lite=False):
    global WHEEL_TRIS, MAX_TEX
    R = dict(CARS[car_id])
    if lite:  # versión liviana para los autos estacionados / de fondo: ~12.000 triángulos, texturas de 256 px, sin piezas dañadas
        WHEEL_TRIS, MAX_TEX = 450, 256
        R["budget"] = 7000
        R["heavy"] = list(R.get("heavy", [])) + [n for n in R.get("extra_heavy", [])]
    else:
        WHEEL_TRIS, MAX_TEX = 3000, 1024
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(cars_dir, R["src"]))
    scene = bpy.context.scene
    # 1. hornear + borrar vacíos
    meshes = {}
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bake_world(o)
            o.hide_set(False)
            o.hide_viewport = False
            o.hide_render = False
            meshes[o.name] = o
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)

    def drop(name):
        o = meshes.pop(name, None)
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)

    for n in R["drop"]:
        drop(n)

    # piezas asignadas
    assigned = {}
    for pn, d in R["parts"].items():
        for k in ("ok", "dam"):
            for n in d.get(k, []):
                assigned[n] = (pn, k)
    # las dañadas sin dueño se descartan
    for n in list(meshes):
        if re.search(r"_dam( \(\d+\))?$", n) and n not in assigned:
            drop(n)

    # 2. ruedas
    centers = {}
    wheel_objs = {}

    def gcenter(objs):
        mn, mx = bbox(objs)
        return (mn + mx) / 2, mx - mn

    for corner, spec in R["wheels"].items():
        if spec[0] == "obj":
            objs = [meshes.pop(n) for n in spec[1]]
            for o in objs:
                decimate(o, WHEEL_TRIS // max(1, len(objs)))
            wheel_objs[corner] = objs
    for corner, spec in R["wheels"].items():
        if spec[0] == "copy":
            _, src, flip, znew = spec
            src_objs = wheel_objs[src]
            sc, _ = gcenter(src_objs)
            side = 1.0 if corner[1] == "l" else -1.0
            tgt = Vector((side * abs(sc.x), sc.y, sc.z))
            if znew is not None:
                tgt.y = -znew
            T = Matrix.Translation(tgt) @ (Matrix.Rotation(math.pi, 4, "Z") if flip else Matrix.Identity(4)) @ Matrix.Translation(-sc)
            new = []
            for o in src_objs:
                n = o.copy()
                n.data = o.data.copy()
                n.name = f"{o.name}_{corner}"
                bpy.context.collection.objects.link(n)
                n.data.transform(T)
                if T.determinant() < 0:
                    n.data.flip_normals()
                new.append(n)
            wheel_objs[corner] = new
    for corner, objs in wheel_objs.items():
        centers[corner], _ = gcenter(objs)

    # 3. a piso y origen en el centro de gravedad
    def wheel_dims(corner):
        mn, mx = bbox(wheel_objs[corner])
        return mn, mx
    bottoms = [wheel_dims(c)[0].z for c in wheel_objs]
    R_each = {c: (wheel_dims(c)[1].z - wheel_dims(c)[0].z) / 2 for c in wheel_objs}
    ground = sum(bottoms) / 4
    wr = sum(R_each.values()) / 4
    # cada rueda apoyada en el piso con el mismo radio medio
    for c, objs in wheel_objs.items():
        mn, mx = wheel_dims(c)
        cz = (mn.z + mx.z) / 2
        dz = (ground + R_each[c]) - cz  # la rueda queda con su base en el piso (alturas de centro: ground + R)
        for o in objs:
            move_obj(o, Vector((0, 0, dz)))
    for c in list(centers):
        centers[c], _ = gcenter(wheel_objs[c])
    zf = (centers["fl"].y + centers["fr"].y) / 2  # (Blender: adelante = -Y)
    zr = (centers["rl"].y + centers["rr"].y) / 2
    L = zr - zf
    a = L * (1.0 - R["wf"])
    shift = Vector((0, -a - zf, -ground))
    for o in list(meshes.values()) + [x for v in wheel_objs.values() for x in v]:
        move_obj(o, shift)
    for c in centers:
        centers[c] += shift
    wr = sum((wheel_dims(c)[1].z - wheel_dims(c)[0].z) / 2 for c in wheel_objs) / 4
    trackF = centers["fl"].x - centers["fr"].x
    trackR = centers["rl"].x - centers["rr"].x
    # centrar de lado (cada eje simétrico)
    mid = (centers["fl"].x + centers["fr"].x + centers["rl"].x + centers["rr"].x) / 4
    if abs(mid) > 1e-4:
        for o in list(meshes.values()) + [x for v in wheel_objs.values() for x in v]:
            move_obj(o, Vector((-mid, 0, 0)))
        for c in centers:
            centers[c].x -= mid

    # puertas que vienen abiertas en el archivo (tijera/mariposa): se giran sobre su centro hasta que el panel quede vertical y se apoyan al ras de la carrocería
    for dn, x_out in R.get("fix_doors", {}).items():
        for name in R["parts"][dn]["ok"]:
            o = meshes.get(name)
            if o is None:
                continue
            nrm = Vector((0, 0, 0))
            for pl in o.data.polygons:
                nrm += pl.normal * pl.area
            sgn = 1.0 if nrm.x > 0 else -1.0
            ang = math.atan2(nrm.z, abs(nrm.x))
            c, _ = gcenter([o])
            for sign in (1, -1):
                M = Matrix.Translation(c) @ Matrix.Rotation(sign * ang * sgn, 4, "Y") @ Matrix.Translation(-c)
                n2 = M.to_3x3() @ nrm
                if abs(n2.z) < abs(nrm.z) * 0.2:
                    o.data.transform(M)
                    break
            mn_, mx_ = bbox([o])
            dx = (x_out - mx_.x) if sgn > 0 else (-x_out - mn_.x)
            o.data.transform(Matrix.Translation(Vector((dx, 0, 0))))

    # 4. reducir
    heavy = [meshes[n] for n in R.get("heavy", []) if n in meshes]
    for o in heavy:  # interior, chasis y luces: se simplifican mucho (casi no se ven)
        decimate(o, max(300, int(tris(o) * 0.12)))
    rest = [o for n, o in meshes.items() if o not in heavy]
    budget = R["budget"] - sum(tris(o) for o in heavy)
    total = sum(tris(o) for o in rest)
    r = min(1.0, budget / max(1, total))
    print("DEC total", total, "ratio", r)
    for o in rest:
        t = tris(o)
        if t > 400:
            decimate(o, max(300, int(t * r)))
    for img in bpy.data.images:
        if img.size[0] > MAX_TEX or img.size[1] > MAX_TEX:
            f = MAX_TEX / max(img.size)
            img.scale(max(4, int(img.size[0] * f)), max(4, int(img.size[1] * f)))

    # volante
    if R.get("steer"):
        so = [meshes[n] for n in R["steer"] if n in meshes]
        sc_, sd = gcenter(so)
        steer_c = sc_ if so else None
        steer_r = max(sd.x, sd.y, sd.z) / 2 if so else 0.18
        # tras el corrimiento que se hizo antes de calcular (los objetos ya fueron movidos) el centro ya está en coordenadas finales
    else:
        steer_c = g2b(R["steer_xyz"]) + shift + Vector((-mid, 0, 0))
        steer_r = 0.18

    # 5. jerarquía: car / body / part_* / wheel_*
    coll = bpy.context.collection
    root = bpy.data.objects.new("car", None)
    coll.objects.link(root)

    def empty(name, loc, parent):
        bpy.context.view_layer.update()
        e = bpy.data.objects.new(name, None)
        coll.objects.link(e)
        e.parent = parent
        e.location = parent.matrix_world.inverted() @ loc
        return e

    def adopt(o, parent):
        bpy.context.view_layer.update()
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()

    body = empty("body", Vector((0, 0, 0)), root)
    parts_meta = {}
    used = set()
    for pn, d in R["parts"].items():
        oks = [meshes[n] for n in d.get("ok", []) if n in meshes]
        dams = [meshes[n] for n in d.get("dam", []) if n in meshes]
        if not oks:
            continue
        c, sz = gcenter(oks)
        pe = empty("part_" + pn, c, root)
        bpy.context.view_layer.update()
        ok_e = empty("ok", c, pe)
        for o in oks:
            adopt(o, ok_e)
            used.add(o.name)
        if dams:
            dam_e = empty("dam", c, pe)
            for o in dams:
                adopt(o, dam_e)
                used.add(o.name)
        parts_meta[pn] = {"center": b2g(c), "size": [round(abs(sz.x), 3), round(abs(sz.z), 3), round(abs(sz.y), 3)], "has_dam": bool(dams)}
    steer_axis = [0.0, 0.34, -0.94]
    so = [meshes[n] for n in R.get("steer", []) if n in meshes and n not in used]
    if so:
        import numpy as np
        pts = np.array([[(o.matrix_world @ v.co)[i] for i in range(3)] for o in so for v in o.data.vertices])
        c0 = pts.mean(axis=0)
        w, vec = np.linalg.eigh(np.cov((pts - c0).T))
        ax = Vector(vec[:, 0])  # el eje de menor extensión = la normal del aro
        g = Vector(b2g(ax))
        if g.z > 0:
            g = -g
        steer_axis = [round(g.x, 3), round(g.y, 3), round(g.z, 3)]
        se = empty("steer_wheel", steer_c, root)
        for o in so:
            adopt(o, se)
            used.add(o.name)
    for n, o in meshes.items():
        if n not in used:
            adopt(o, body)
    wheel_meta = {}
    for corner, objs in wheel_objs.items():
        we = empty("wheel_" + corner, centers[corner], root)
        bpy.context.view_layer.update()
        for o in objs:
            adopt(o, we)
        mn, mx = bbox(objs)
        wheel_meta[corner] = {"center": b2g(centers[corner]), "radius": round((mx.z - mn.z) / 2, 4), "width": round(mx.x - mn.x, 4)}

    mn, mx = bbox([o for o in bpy.data.objects if o.type == "MESH"])
    meta = {
        "id": car_id, "name": R["name"], "maker": R["maker"], "year": R["year"], "kind": R["kind"],
        "wheelBase": round(L, 4), "trackF": round(trackF, 4), "trackR": round(trackR, 4), "wheelRadius": round(wr, 4),
        "comToFront": round(a, 4), "length": round(mx.y - mn.y, 3), "width": round(mx.x - mn.x, 3), "height": round(mx.z - mn.z, 3),
        "front_z": round(-mn.y, 3), "rear_z": round(-mx.y, 3),
        "drive_side": R["drive_side"], "paint": R.get("paint", []), "steer_center": b2g(steer_c), "steer_radius": round(steer_r, 3), "steer_axis": steer_axis, "has_steer_mesh": bool(so),
        "wheels": wheel_meta, "parts": parts_meta,
    }
    # 6. exportar
    os.makedirs(out_dir, exist_ok=True)
    for o in bpy.data.objects:
        o.select_set(True)
    glb = os.path.join(out_dir, car_id + ("_lite" if lite else "") + ".glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=False, export_yup=True, export_cameras=False, export_lights=False,
                              export_apply=False, export_image_format="AUTO", export_extras=False, export_animations=False)
    meta["tris_total"] = sum(tris(o) for o in bpy.data.objects if o.type == "MESH")
    meta["glb_mb"] = round(os.path.getsize(glb) / 1e6, 2)
    if not lite:
        json.dump(meta, open(os.path.join(out_dir, car_id + ".json"), "w"), indent=1, ensure_ascii=False)
    print("OK", car_id, "tris", meta["tris_total"], "MB", meta["glb_mb"], "L", meta["wheelBase"], "trackF", meta["trackF"], "R", meta["wheelRadius"])


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    cars_dir, out_dir, ids = "", os.path.join(HERE, "..", "..", "godot", "game", "models", "cars"), []
    i = 0
    while i < len(argv):
        if argv[i] == "--cars":
            cars_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--out":
            out_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--lite":
            i += 1
        else:
            ids.append(argv[i])
            i += 1
    lite = "--lite" in argv
    ids = [i for i in ids if not i.startswith("--")]
    for cid in (ids or list(CARS)):
        run(cid, cars_dir, out_dir, lite=lite)
