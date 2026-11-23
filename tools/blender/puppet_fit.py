"""MARIONETA del piloto en Blender (bpy): deja al personaje sentado en cada auto a partir de las MARCAS (asiento, pedales, volante, palanca) y calcula el ajuste.

    python tools/blender/puppet_fit.py --chars godot/game/models/characters --markers godot/game/data/cabin_markers.json \
        --out godot/game/data/cabin_fit.json [--renders carpeta] [cls63_amg aventador_s …]

Cómo funciona (es lo que hace Animatica Marionette a mano, pero automático y repetible):
  · construye una marioneta con IK: la mano izquierda y la derecha se «atornillan» al aro del volante (a las 10 y a las 2), el pie derecho a la marca del pedal
    del acelerador, el izquierdo al apoyapié; codos y rodillas se guían con vectores polo;
  · la cadera se coloca sobre la marca del asiento y el torso se inclina;
  · busca (cuadrícula) la combinación de ESCALA del piloto, corrimiento de la cadera e INCLINACIÓN del torso que:
      1) llega a las 4 marcas (error de las manos y los pies),
      2) no hunde los muslos en la almohadilla del asiento,
      3) no hunde la espalda en el respaldo;
  · escribe cabin_fit.json (escala, corrimiento y torso por auto y por piloto + los errores que quedaron) y, si se pide, una imagen de control por auto.
En el juego el piloto sigue con IK en vivo (para que las manos acompañen al volante y los pies a los pedales mientras se maneja): este ajuste le da el punto de partida.
Marco de las marcas = el del auto (+z adelante, +x izquierda, y desde el piso); en Blender se convierte a (x, −z, y)."""
import bpy, sys, os, json, math, itertools
from mathutils import Vector, Matrix

BASE_HEIGHT = 1.86  # la estatura que usa el juego por defecto (RigPilot: escala = estatura·0,80 / distancia cabeza–tobillo)
GRIP = [0.088, math.pi - 0.088]  # ángulos de las manos en el aro: derecha (≈ 3 en punto) e izquierda (≈ 9)
B = "EM3D_Base_"


def g2b(v):
    return Vector((v[0], -v[2], v[1]))


class Puppet:
    def __init__(self, glb):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=glb)
        self.arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
        self.meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        self.pb = self.arm.pose.bones
        rest = {n: self.arm.matrix_world @ self.arm.data.bones[n].head_local for n in (B + "Head", B + "L_Foot", B + "R_Foot")}
        self.base = BASE_HEIGHT * 0.8 / (rest[B + "Head"].z - min(rest[B + "L_Foot"].z, rest[B + "R_Foot"].z))
        self.rest_m = {b.name: b.matrix_local.copy() for b in self.arm.data.bones}
        self.t = {}
        for k in ("hand_L", "hand_R", "foot_L", "foot_R", "pole_hand_L", "pole_hand_R", "pole_knee_L", "pole_knee_R"):
            e = bpy.data.objects.new(k, None)
            bpy.context.collection.objects.link(e)
            self.t[k] = e
        self._ik("L_Forearm", "hand_L", "pole_hand_L", -90)
        self._ik("R_Forearm", "hand_R", "pole_hand_R", -90)
        self._ik("L_Calf", "foot_L", "pole_knee_L", -90)
        self._ik("R_Calf", "foot_R", "pole_knee_R", -90)
        self.show_meshes(False)  # durante la búsqueda no se deforma la malla (mucho más rápido)

    def _ik(self, bone, tgt, pole, ang):
        c = self.pb[B + bone].constraints.new("IK")
        c.target = self.t[tgt]
        c.pole_target = self.t[pole]
        c.pole_angle = math.radians(ang)
        c.chain_count = 2
        c.use_tail = True
        c.use_stretch = False
        c.iterations = 120

    def show_meshes(self, on):
        for m in self.meshes:
            m.hide_viewport = not on
            m.hide_render = not on

    def head(self, name):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = self.arm.evaluated_get(dg)
        return ev.matrix_world @ ev.pose.bones[B + name].head

    def tail(self, name):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = self.arm.evaluated_get(dg)
        return ev.matrix_world @ ev.pose.bones[B + name].tail

    def reset(self):
        for p in self.pb:
            p.rotation_mode = "QUATERNION"
            p.rotation_quaternion = (1, 0, 0, 0)
            p.location = (0, 0, 0)
            p.scale = (1, 1, 1)

    def pose(self, M, scale, hip, lean_deg, tilt_deg):
        """Coloca la marioneta: escala, cadera (en Blender), torso inclinado (grados hacia atrás) y las marcas de las manos y los pies."""
        self.reset()
        self.arm.scale = (self.base * scale,) * 3
        bpy.context.view_layer.update()
        # cadera: se traslada el hueso «Hip» para que su cabeza quede sobre la marca
        hp = self.pb[B + "Hip"]
        cur = self.arm.matrix_world @ hp.head
        rest_world = self.arm.matrix_world @ hp.matrix
        delta = hip - cur
        hp.matrix = self.arm.matrix_world.inverted() @ (Matrix.Translation(delta) @ rest_world)
        bpy.context.view_layer.update()
        # inclinación de la pelvis y del torso hacia atrás (rotación sobre el eje X del auto, en cada hueso del torso)
        for name, k in ((B + "Pelvis", tilt_deg), (B + "Waist", lean_deg / 3.0), (B + "Spine01", lean_deg / 3.0), (B + "Spine02", lean_deg / 3.0)):
            p = self.pb[name]
            head = self.arm.matrix_world @ p.head
            R = Matrix.Translation(head) @ Matrix.Rotation(math.radians(k), 4, "X") @ Matrix.Translation(-head)
            p.matrix = self.arm.matrix_world.inverted() @ (R @ (self.arm.matrix_world @ p.matrix))
            bpy.context.view_layer.update()
        # marcas
        for k, v in M["targets"].items():
            self.t[k].location = v
        bpy.context.view_layer.update()


def targets(m):
    """Las marcas del auto → puntos de las manos, los pies y vectores polo (Blender)."""
    w = m["wheel"]
    S = Vector(w["center"])
    n = Vector(w["axis"]).normalized()
    wX = Vector((0, 1, 0)).cross(n).normalized()
    wY = n.cross(wX)
    r = float(w["radius"])
    T = {}
    for side, ang in (("R", GRIP[0]), ("L", GRIP[1])):
        gp = S + wX * (math.cos(ang) * r) + wY * (math.sin(ang) * r)
        rr = (gp - S).normalized()
        wrist = gp + n * 0.075 + rr * 0.05
        T["hand_" + side] = g2b(wrist)
        sx = 1.0 if side == "L" else -1.0
        T["pole_hand_" + side] = g2b(wrist + Vector((sx * 0.45, -0.35, -0.15)))
    ped = m["pedals"]
    T["foot_R"] = g2b(ped["accel"])
    T["foot_L"] = g2b(ped["rest"])
    seat = Vector(m["seat"]["hip"])
    for side in ("L", "R"):
        sx = 1.0 if side == "L" else -1.0
        mid = (seat + Vector(ped["accel"])) * 0.5
        T["pole_knee_" + side] = g2b(mid + Vector((sx * 0.25, 0.6, 0.15)))
    return {"targets": T, "hip": g2b(seat), "S": S}


def cost(pup, m, M, scale, dz, dy, lean, tilt):
    hip = M["hip"] + Vector((0, -dz, dy))  # (Blender: adelante = −Y)
    pup.pose(M, scale, hip, lean, tilt)
    eh = [(pup.tail("L_Forearm") - M["targets"]["hand_L"]).length, (pup.tail("R_Forearm") - M["targets"]["hand_R"]).length]
    ef = [(pup.tail("L_Calf") - M["targets"]["foot_L"]).length, (pup.tail("R_Calf") - M["targets"]["foot_R"]).length]
    cushion = float(m["seat"]["cushion_top"])
    back_z = float(m["seat"]["back_z"])
    tan_t = math.tan(math.radians(float(m["seat"].get("back_tilt_deg", 14))))
    pen = 0.0
    # muslos: no por debajo de la almohadilla (z del juego = −y de Blender)
    for side in ("L", "R"):
        a, b = pup.head(side + "_Thigh"), pup.head(side + "_Calf")
        for k in range(1, 6):
            p = a.lerp(b, k / 6.0)
            y, z = p.z, -p.y
            if back_z - 0.05 < z < float(m["seat"]["hip"][2]) + 0.42:
                pen += max(0.0, cushion + 0.055 - y)
    # torso: no detrás del respaldo (la superficie se inclina hacia atrás)
    for nm in ("Waist", "Spine01", "Spine02", "Head"):
        p = pup.head(nm)
        y, z = p.z, -p.y
        surf_z = back_z - tan_t * max(0.0, y - cushion)
        pen += max(0.0, surf_z + 0.075 - z)
    c = 4.0 * sum(e * e for e in eh) + 4.0 * sum(e * e for e in ef) + 25.0 * pen * pen + 0.3 * abs(scale - 1.0) + 0.5 * (abs(dz) + abs(dy)) + 0.002 * abs(lean - 6.0)
    return c, eh, ef, pen


def fit_car(pup, car_id, m):
    M = targets(m)
    best = None
    for scale, dz, dy, lean in itertools.product([0.88, 0.92, 0.96, 1.0, 1.04, 1.08, 1.12], [-0.16, -0.10, -0.05, 0.0, 0.05, 0.10, 0.16], [-0.05, -0.025, 0.0, 0.03, 0.06], [0.0, 5.0, 10.0, 15.0, 20.0]):
        c, eh, ef, pen = cost(pup, m, M, scale, dz, dy, lean, 0.0)
        if best is None or c < best[0]:
            best = (c, scale, dz, dy, lean, 0.0, eh, ef, pen)
    # afinado local
    for _ in range(2):
        c0, s0, z0, y0, l0, t0 = best[:6]
        for ds, dzz, dyy, dl, dtl in itertools.product([-0.015, 0, 0.015], [-0.02, 0, 0.02], [-0.015, 0, 0.015], [-2.5, 0, 2.5], [-6.0, 0, 6.0]):
            c, eh, ef, pen = cost(pup, m, M, s0 + ds, z0 + dzz, y0 + dyy, l0 + dl, t0 + dtl)
            if c < best[0]:
                best = (c, s0 + ds, z0 + dzz, y0 + dyy, l0 + dl, t0 + dtl, eh, ef, pen)
    c, scale, dz, dy, lean, tilt, eh, ef, pen = best
    return {"scale": round(scale, 3), "dz": round(dz, 3), "dy": round(dy, 3),
            "lean0": round(-0.10 + math.radians(lean) * 0.35, 3), "lean1": round(0.18 + math.radians(lean) * 0.5, 3), "hip_tilt": round(-0.18 + math.radians(tilt) * 0.5, 3),
            "lean_deg": round(lean, 1), "tilt_deg": round(tilt, 1),
            "err_hands_cm": [round(e * 100, 1) for e in eh], "err_feet_cm": [round(e * 100, 1) for e in ef], "penetration_cm": round(pen * 100, 1), "cost": round(c, 4),
            "ok": bool(max(eh) < 0.09 and max(ef) < 0.09 and pen < 0.06)}


def render(pup, car_id, m, fit, path):
    M = targets(m)
    hip = M["hip"] + Vector((0, -fit["dz"], fit["dy"]))
    pup.show_meshes(True)
    pup.pose(M, fit["scale"], hip, fit["lean_deg"], fit["tilt_deg"])
    before = set(bpy.data.objects)
    # marcas visibles: almohadilla (verde), pedal (rojo), volante (disco azul)
    def box(c, size, col):
        me = bpy.data.meshes.new("b")
        import bmesh
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(c) @ Matrix.Diagonal((size[0], size[1], size[2], 1)))
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new("mk", me)
        bpy.context.collection.objects.link(o)
        mt = bpy.data.materials.new("m")
        mt.use_nodes = True
        nt = mt.node_tree
        nt.nodes.clear()
        e = nt.nodes.new("ShaderNodeEmission")
        e.inputs[0].default_value = (*col, 1)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(e.outputs[0], out.inputs[0])
        o.data.materials.append(mt)
    seat = m["seat"]
    box(g2b([seat["hip"][0], seat["cushion_top"] - 0.02, seat["hip"][2]]), (0.45, 0.5, 0.04), (0, 1, 0))
    box(g2b(m["pedals"]["accel"]), (0.12, 0.08, 0.1), (1, 0, 0))
    w = m["wheel"]
    box(g2b(w["center"]), (0.03, 0.03, 0.03), (0, 0.4, 1))
    box(g2b([seat["hip"][0], 0.0, seat["hip"][2] + 0.5]), (1.4, 3.2, 0.02), (0.3, 0.3, 0.3))
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 6
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 760, 420
    sc.view_settings.view_transform = "Standard"
    wd = bpy.data.worlds.new("w")
    sc.world = wd
    wd.use_nodes = True
    wd.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.85, 0.9, 1)
    wd.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    sun = bpy.data.lights.new("s", "SUN")
    sun.energy = 3
    so = bpy.data.objects.new("s", sun)
    bpy.context.collection.objects.link(so)
    so.rotation_euler = (0.9, 0.2, 0.6)
    cam = bpy.data.cameras.new("c")
    cam.type = "ORTHO"
    cam.ortho_scale = 2.6
    co = bpy.data.objects.new("c", cam)
    bpy.context.collection.objects.link(co)
    sc.camera = co
    ctr = g2b([seat["hip"][0], 0.75, seat["hip"][2] + 0.45])
    co.location = ctr + Vector((6, 0, 0))
    co.rotation_euler = (math.pi / 2, 0, math.pi / 2)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for o in set(bpy.data.objects) - before:  # (se limpian las marcas y la cámara: el siguiente auto parte de cero)
        bpy.data.objects.remove(o, do_unlink=True)


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    chars_dir, markers, out, renders, ids, i = "", "", "", "", [], 0
    while i < len(a):
        if a[i] == "--chars":
            chars_dir = a[i + 1]; i += 2
        elif a[i] == "--markers":
            markers = a[i + 1]; i += 2
        elif a[i] == "--out":
            out = a[i + 1]; i += 2
        elif a[i] == "--renders":
            renders = a[i + 1]; i += 2
        else:
            ids.append(a[i]); i += 1
    M = json.load(open(markers))
    res = json.load(open(out)) if os.path.exists(out) else {}
    for ch in ("aiden", "kate", "mujer_adulta"):
        pup = Puppet(os.path.join(chars_dir, ch + ".glb"))
        for cid in (ids or list(M)):
            f = fit_car(pup, cid, M[cid])
            res.setdefault(cid, {})[ch] = f
            print("FIT", cid, ch, f["scale"], "dz", f["dz"], "dy", f["dy"], "lean", f["lean_deg"], "manos(cm)", f["err_hands_cm"], "pies(cm)", f["err_feet_cm"], "penetración(cm)", f["penetration_cm"], flush=True)
            if renders and ch == "aiden":
                os.makedirs(renders, exist_ok=True)
                render(pup, cid, M[cid], f, os.path.join(renders, cid + ".png"))
                pup.show_meshes(False)
    json.dump(res, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
