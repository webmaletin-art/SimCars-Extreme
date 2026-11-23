"""Texturas y sprites del juego, hechos en Blender (bpy, Cycles en CPU, pocas muestras): asfalto, tierra con piedras, pasto, hormigón, fachadas,
árboles y arbustos (sprites en cruz, con fondo transparente), pasto, flores y las marcas del estacionamiento. Todo en baja resolución (≤1024 px) para celulares livianos.

    python tools/blender/make_textures.py --out godot/game/tex [asfalto tierra pasto ...]

Cada textura de suelo se hace «tileable» (se mezcla con su copia desplazada medio lado), así no se ven costuras al repetirla."""
import bpy, bmesh, sys, os, math, random
import numpy as np
from mathutils import Vector, Matrix, Euler

OUT = "."
SAMPLES = 34

# ───────────────────────── utilidades de Blender ─────────────────────────
def reset(res=(1024, 1024), transparent=False, samples=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples or SAMPLES
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    return sc

def world_color(col, strength):
    w = bpy.context.scene.world
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*col, 1)
    bg.inputs[1].default_value = strength

def sky_world(strength=1.0):
    w = bpy.context.scene.world
    nt = w.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "SINGLE_SCATTERING"
    sky.sun_elevation = math.radians(50)
    sky.sun_rotation = math.radians(40)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[1].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])

def sun(rot=(0.9, 0.2, 0.7), energy=4.0):
    l = bpy.data.lights.new("sun", "SUN")
    l.energy = energy
    o = bpy.data.objects.new("sun", l)
    bpy.context.collection.objects.link(o)
    o.rotation_euler = rot
    return o

def camera_ortho(loc, rot, scale):
    c = bpy.data.cameras.new("c")
    c.type = "ORTHO"
    c.ortho_scale = scale
    o = bpy.data.objects.new("c", c)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = rot
    bpy.context.scene.camera = o
    return o

def plane(size, loc=(0, 0, 0)):
    me = bpy.data.meshes.new("pl")
    s = size / 2
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    me.update()
    o = bpy.data.objects.new("pl", me)
    bpy.context.collection.objects.link(o)
    o.location = loc
    return o

def mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    return m, nt

def principled(nt, base=(0.5, 0.5, 0.5, 1), rough=0.8):
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.inputs["Roughness"].default_value = rough
    if base is not None:
        p.inputs["Base Color"].default_value = base
    nt.links.new(p.outputs[0], out.inputs[0])
    return p

def ramp(nt, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    cr = r.color_ramp
    while len(cr.elements) > len(stops):
        cr.elements.remove(cr.elements[-1])
    while len(cr.elements) < len(stops):
        cr.elements.new(0.5)
    for e, (pos, col) in zip(cr.elements, stops):
        e.position = pos
        e.color = col
    return r

def noise(nt, scale, detail=6, rough=0.55, coord=None, w=0.0, kind="NOISE"):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    if coord is not None:
        nt.links.new(coord, n.inputs["Vector"])
    return n

def voronoi(nt, scale, coord=None, rnd=1.0, feature="F1"):
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.feature = feature
    v.inputs["Scale"].default_value = scale
    v.inputs["Randomness"].default_value = rnd
    if coord is not None:
        nt.links.new(coord, v.inputs["Vector"])
    return v

def math_node(nt, op, a=None, b=None, clamp=False):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = op
    m.use_clamp = clamp
    if isinstance(a, (int, float)):
        m.inputs[0].default_value = a
    elif a is not None:
        nt.links.new(a, m.inputs[0])
    if isinstance(b, (int, float)):
        m.inputs[1].default_value = b
    elif b is not None:
        nt.links.new(b, m.inputs[1])
    return m

def mix_rgb(nt, fac, a, b, blend="MIX"):
    m = nt.nodes.new("ShaderNodeMixRGB")
    m.blend_type = blend
    if isinstance(fac, (int, float)):
        m.inputs[0].default_value = fac
    else:
        nt.links.new(fac, m.inputs[0])
    for i, x in ((1, a), (2, b)):
        if isinstance(x, tuple):
            m.inputs[i].default_value = x
        else:
            nt.links.new(x, m.inputs[i])
    return m

def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

def tileify(path):
    """vuelve el PNG repetible: se mezcla con su copia desplazada medio lado con una máscara que vale 1 en el centro y 0 en los bordes"""
    from PIL import Image
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    h, w, _ = im.shape
    sh = np.roll(np.roll(im, h // 2, axis=0), w // 2, axis=1)
    y = np.sin(np.linspace(0, math.pi, h, endpoint=False))[:, None]
    x = np.sin(np.linspace(0, math.pi, w, endpoint=False))[None, :]
    m = (y * x)[:, :, None]
    m = m ** 0.8
    out = m * im + (1 - m) * sh
    Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(path)

def grid_ground(mat_obj, area, loc=(0, 0, 0)):
    p = plane(area, loc)
    p.data.materials.append(mat_obj)
    return p

# ───────────────────────── suelos ─────────────────────────
def tex_asfalto(path, res=1024):
    sc = reset((res, res))
    world_color((0.55, 0.6, 0.7), 0.5)
    area = 3.0
    m, nt = mat("asfalto")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    # granulado fino (piedritas) + manchas grandes + fisuras
    vor = voronoi(nt, 220, mp.outputs[0], 1.0)
    vor_big = voronoi(nt, 60, mp.outputs[0], 1.0)
    nz_big = noise(nt, 1.3, 8, 0.6, mp.outputs[0])
    nz_fine = noise(nt, 90, 3, 0.5, mp.outputs[0])
    crack = voronoi(nt, 1.1, mp.outputs[0], 0.9, "DISTANCE_TO_EDGE")
    crack_r = ramp(nt, [(0.0, (0, 0, 0, 1)), (0.02, (0, 0, 0, 1)), (0.055, (1, 1, 1, 1))])
    nt.links.new(crack.outputs["Distance"], crack_r.inputs[0])
    crack_mask = noise(nt, 2.2, 3, 0.5, mp.outputs[0])
    cm_r = ramp(nt, [(0.52, (0, 0, 0, 1)), (0.62, (1, 1, 1, 1))])
    nt.links.new(crack_mask.outputs["Fac"], cm_r.inputs[0])
    crack_final = mix_rgb(nt, cm_r.outputs[0], (1, 1, 1, 1), crack_r.outputs[0])  # 1 = sin fisura
    stone = ramp(nt, [(0.0, (0.020, 0.020, 0.022, 1)), (0.40, (0.040, 0.040, 0.043, 1)), (0.72, (0.085, 0.082, 0.08, 1)), (1.0, (0.16, 0.15, 0.14, 1))])
    nt.links.new(vor.outputs["Distance"], stone.inputs[0])
    patch = ramp(nt, [(0.35, (0.8, 0.8, 0.8, 1)), (0.65, (1.15, 1.15, 1.15, 1))])
    nt.links.new(nz_big.outputs["Fac"], patch.inputs[0])
    col1 = mix_rgb(nt, 1.0, stone.outputs[0], patch.outputs[0], "MULTIPLY")
    col2 = mix_rgb(nt, 1.0, col1.outputs[0], crack_final.outputs[0], "MULTIPLY")
    # desgaste claro por zonas
    wear = ramp(nt, [(0.55, (0, 0, 0, 1)), (0.8, (1, 1, 1, 1))])
    nt.links.new(nz_big.outputs["Fac"], wear.inputs[0])
    col3 = mix_rgb(nt, wear.outputs[0], col2.outputs[0], (0.17, 0.17, 0.175, 1))
    col3.inputs[0].default_value = 0.0
    nt.links.new(wear.outputs[0], col3.inputs[0])
    nt.links.new(math_node(nt, "MULTIPLY", wear.outputs[0], 0.18).outputs[0], col3.inputs[0])
    p = principled(nt, None, 0.88)
    nt.links.new(col3.outputs[0], p.inputs["Base Color"])
    hv = math_node(nt, "ADD", vor.outputs["Distance"], nz_fine.outputs["Fac"])
    hv2 = math_node(nt, "MULTIPLY", crack_final.outputs[0], hv.outputs[0])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.9
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(hv2.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], p.inputs["Normal"])
    mp.inputs["Scale"].default_value = (1, 1, 1)
    g = grid_ground(m, area)
    sun((0.75, 0.15, 0.5), 2.4)
    camera_ortho((0, 0, 3), (0, 0, 0), area)
    render(path)
    tileify(path)

def tex_tierra(path, res=1024):
    sc = reset((res, res))
    world_color((0.7, 0.72, 0.8), 0.5)
    area = 3.0
    m, nt = mat("tierra")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz1 = noise(nt, 3.0, 8, 0.65, tc.outputs["Object"])
    nz2 = noise(nt, 45.0, 5, 0.6, tc.outputs["Object"])
    vor = voronoi(nt, 120, tc.outputs["Object"])
    base = ramp(nt, [(0.0, (0.10, 0.060, 0.032, 1)), (0.5, (0.17, 0.105, 0.06, 1)), (1.0, (0.24, 0.155, 0.09, 1))])
    nt.links.new(nz1.outputs["Fac"], base.inputs[0])
    speck = ramp(nt, [(0.55, (1, 1, 1, 1)), (0.8, (1.35, 1.3, 1.2, 1))])
    nt.links.new(vor.outputs["Distance"], speck.inputs[0])
    c = mix_rgb(nt, 1.0, base.outputs[0], speck.outputs[0], "MULTIPLY")
    p = principled(nt, None, 0.95)
    nt.links.new(c.outputs[0], p.inputs["Base Color"])
    h = math_node(nt, "ADD", nz2.outputs["Fac"], vor.outputs["Distance"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(h.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], p.inputs["Normal"])
    g = grid_ground(m, area)
    # piedras: esferas aplastadas con relieve, repartidas al azar (tamaños de 2 a 9 cm), con sombra real
    rnd = random.Random(5)
    stone_m, snt = mat("piedra")
    stc = snt.nodes.new("ShaderNodeTexCoord")
    sn = noise(snt, 18, 6, 0.6, stc.outputs["Object"])
    sr = ramp(snt, [(0.0, (0.07, 0.065, 0.06, 1)), (0.6, (0.14, 0.13, 0.115, 1)), (1.0, (0.22, 0.2, 0.18, 1))])
    snt.links.new(sn.outputs["Fac"], sr.inputs[0])
    sp = principled(snt, None, 0.9)
    snt.links.new(sr.outputs[0], sp.inputs["Base Color"])
    sb = snt.nodes.new("ShaderNodeBump")
    sb.inputs["Strength"].default_value = 0.8
    snt.links.new(sn.outputs["Fac"], sb.inputs["Height"])
    snt.links.new(sb.outputs[0], sp.inputs["Normal"])
    bm = bmesh.new()
    for i in range(230):
        r = rnd.choice([0.012, 0.016, 0.02, 0.025, 0.03, 0.04, 0.05, 0.07]) * rnd.uniform(0.8, 1.2)
        x, y = rnd.uniform(-area / 2, area / 2), rnd.uniform(-area / 2, area / 2)
        mt = Matrix.Translation((x, y, r * 0.3)) @ Matrix.Rotation(rnd.uniform(0, 6.28), 4, "Z") @ Matrix.Diagonal((r * rnd.uniform(1.0, 1.5), r * rnd.uniform(0.8, 1.2), r * 0.7, 1))
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0, matrix=mt)
    me = bpy.data.meshes.new("stones")
    bm.to_mesh(me)
    bm.free()
    for p_ in me.polygons:
        p_.use_smooth = True
    so = bpy.data.objects.new("stones", me)
    bpy.context.collection.objects.link(so)
    so.data.materials.append(stone_m)
    sun((0.8, 0.1, 0.9), 2.6)
    camera_ortho((0, 0, 3), (0, 0, 0), area)
    render(path)
    tileify(path)

def tex_pasto(path, res=1024):
    sc = reset((res, res))
    world_color((0.7, 0.8, 0.95), 1.0)
    area = 3.0
    m, nt = mat("pasto")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz1 = noise(nt, 4.0, 8, 0.6, tc.outputs["Object"])
    nz2 = noise(nt, 60.0, 4, 0.5, tc.outputs["Object"])
    vor = voronoi(nt, 260, tc.outputs["Object"])
    base = ramp(nt, [(0.0, (0.07, 0.17, 0.04, 1)), (0.5, (0.14, 0.30, 0.07, 1)), (1.0, (0.25, 0.42, 0.10, 1))])
    nt.links.new(nz1.outputs["Fac"], base.inputs[0])
    blades = ramp(nt, [(0.0, (0.6, 0.6, 0.6, 1)), (0.7, (1.0, 1.0, 1.0, 1)), (1.0, (1.5, 1.55, 1.2, 1))])
    nt.links.new(vor.outputs["Distance"], blades.inputs[0])
    dry = ramp(nt, [(0.62, (0, 0, 0, 1)), (0.85, (1, 1, 1, 1))])
    nt.links.new(nz2.outputs["Fac"], dry.inputs[0])
    c = mix_rgb(nt, 1.0, base.outputs[0], blades.outputs[0], "MULTIPLY")
    c2 = mix_rgb(nt, dry.outputs[0], c.outputs[0], (0.35, 0.33, 0.12, 1))
    nt.links.new(math_node(nt, "MULTIPLY", dry.outputs[0], 0.35).outputs[0], c2.inputs[0])
    p = principled(nt, None, 0.9)
    nt.links.new(c2.outputs[0], p.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.02
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], p.inputs["Normal"])
    grid_ground(m, area)
    sun((0.8, 0.1, 0.9), 3.8)
    camera_ortho((0, 0, 3), (0, 0, 0), area)
    render(path)
    tileify(path)

def tex_hormigon(path, res=512):
    sc = reset((res, res))
    world_color((0.7, 0.75, 0.85), 1.0)
    area = 2.0
    m, nt = mat("hormigon")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz1 = noise(nt, 3.5, 7, 0.6, tc.outputs["Object"])
    nz2 = noise(nt, 70, 4, 0.5, tc.outputs["Object"])
    vor = voronoi(nt, 150, tc.outputs["Object"])
    base = ramp(nt, [(0.0, (0.34, 0.34, 0.33, 1)), (1.0, (0.55, 0.55, 0.53, 1))])
    nt.links.new(nz1.outputs["Fac"], base.inputs[0])
    pores = ramp(nt, [(0.0, (0.55, 0.55, 0.55, 1)), (0.15, (1, 1, 1, 1))])
    nt.links.new(vor.outputs["Distance"], pores.inputs[0])
    c = mix_rgb(nt, 1.0, base.outputs[0], pores.outputs[0], "MULTIPLY")
    p = principled(nt, None, 0.9)
    nt.links.new(c.outputs[0], p.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    nt.links.new(nz2.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], p.inputs["Normal"])
    grid_ground(m, area)
    sun((0.8, 0.1, 0.9), 3.5)
    camera_ortho((0, 0, 3), (0, 0, 0), area)
    render(path)
    tileify(path)

def tex_carton(path, res=512):
    """textura de papel / cartón para los edificios de fondo (papercraft): fibras, manchas y borde gastado"""
    sc = reset((res, res))
    world_color((0.9, 0.9, 0.95), 1.1)
    area = 2.0
    m, nt = mat("carton")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1, 40, 1)
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    fib = noise(nt, 18, 5, 0.6, mp.outputs[0])
    nz = noise(nt, 2.5, 6, 0.6, tc.outputs["Object"])
    base = ramp(nt, [(0.0, (0.60, 0.50, 0.38, 1)), (1.0, (0.78, 0.68, 0.52, 1))])
    nt.links.new(nz.outputs["Fac"], base.inputs[0])
    c = mix_rgb(nt, 0.45, base.outputs[0], fib.outputs["Color"], "MULTIPLY")
    p = principled(nt, None, 0.95)
    nt.links.new(c.outputs[0], p.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.4
    nt.links.new(fib.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], p.inputs["Normal"])
    grid_ground(m, area)
    sun((0.5, 0.1, 0.7), 2.5)
    camera_ortho((0, 0, 3), (0, 0, 0), area)
    render(path)
    tileify(path)

# ───────────────────────── fachadas de los edificios de fondo ─────────────────────────
def tex_fachada(path, seed, wall=(0.70, 0.62, 0.52), win=(0.10, 0.18, 0.25), cols=6, rows=8, res=(512, 768), shop=False):
    rnd = random.Random(seed)
    sc = reset(res)
    sky_world(0.6)
    w, h = 6.0, 9.0
    # pared
    m, nt = mat("pared")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = noise(nt, 6, 6, 0.6, tc.outputs["Object"])
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 18
    brick.inputs["Color1"].default_value = (*wall, 1)
    brick.inputs["Color2"].default_value = (wall[0] * 0.85, wall[1] * 0.85, wall[2] * 0.85, 1)
    brick.inputs["Mortar"].default_value = (0.5, 0.5, 0.48, 1)
    nt.links.new(tc.outputs["Object"], brick.inputs["Vector"])
    c = mix_rgb(nt, 0.35, brick.outputs["Color"], nz.outputs["Color"], "MULTIPLY")
    p = principled(nt, None, 0.9)
    nt.links.new(c.outputs[0], p.inputs["Base Color"])
    bm = nt.nodes.new("ShaderNodeBump")
    bm.inputs["Strength"].default_value = 0.5
    nt.links.new(brick.outputs["Fac"], bm.inputs["Height"])
    nt.links.new(bm.outputs[0], p.inputs["Normal"])
    bm_ = bmesh.new()
    bmesh.ops.create_grid(bm_, x_segments=1, y_segments=1, size=0.5, matrix=Matrix.Diagonal((w, h, 1, 1)) @ Matrix.Rotation(math.pi / 2, 4, "X") if False else Matrix.Identity(4))
    bm_.free()
    # el muro es un plano vertical (X ancho, Z alto) mirando a -Y
    me = bpy.data.meshes.new("muro")
    me.from_pydata([(-w / 2, 0, 0), (w / 2, 0, 0), (w / 2, 0, h), (-w / 2, 0, h)], [], [(0, 3, 2, 1)])
    uv = me.uv_layers.new()
    muro = bpy.data.objects.new("muro", me)
    bpy.context.collection.objects.link(muro)
    muro.data.materials.append(m)
    # ventanas
    wm, wnt = mat("vidrio")
    wp = principled(wnt, (*win, 1), 0.08)
    wp.inputs["Metallic"].default_value = 0.0
    wp.inputs["Specular IOR Level"].default_value = 0.9
    lit, lnt = mat("luz")
    le = lnt.nodes.new("ShaderNodeEmission")
    le.inputs[0].default_value = (1.0, 0.85, 0.5, 1)
    le.inputs[1].default_value = 3.0
    lo = lnt.nodes.new("ShaderNodeOutputMaterial")
    lnt.links.new(le.outputs[0], lo.inputs[0])
    fm, fnt = mat("marco")
    principled(fnt, (0.85, 0.85, 0.82, 1), 0.6)
    top = h - (1.6 if shop else 0.0)
    r0 = 1.2 if shop else 0.8
    for r in range(rows):
        for cidx in range(cols):
            cx = -w / 2 + (cidx + 0.5) * (w / cols)
            cz = r0 + 0.6 + r * ((top - r0 - 0.5) / rows)
            ww, wh = w / cols * 0.55, (top - r0 - 0.5) / rows * 0.62
            for (mm, dx, dz, sw, sh, dy) in ((fm, 0, 0, ww + 0.14, wh + 0.14, -0.02), (lit if rnd.random() < 0.22 else wm, 0, 0, ww, wh, -0.05)):
                q = bpy.data.meshes.new("q")
                q.from_pydata([(-sw / 2, 0, -sh / 2), (sw / 2, 0, -sh / 2), (sw / 2, 0, sh / 2), (-sw / 2, 0, sh / 2)], [], [(0, 3, 2, 1)])
                qo = bpy.data.objects.new("q", q)
                bpy.context.collection.objects.link(qo)
                qo.location = (cx, dy, cz)
                qo.data.materials.append(mm)
    if shop:  # vidriera + cortina comercial en la planta baja
        sm, snt = mat("local")
        principled(snt, (rnd.uniform(0.3, 0.8), rnd.uniform(0.2, 0.6), rnd.uniform(0.2, 0.5), 1), 0.7)
        q = bpy.data.meshes.new("q")
        q.from_pydata([(-w / 2 + 0.3, 0, 0.1), (w / 2 - 0.3, 0, 0.1), (w / 2 - 0.3, 0, 1.0), (-w / 2 + 0.3, 0, 1.0)], [], [(0, 3, 2, 1)])
        qo = bpy.data.objects.new("q", q)
        bpy.context.collection.objects.link(qo)
        qo.location.y = -0.03
        qo.data.materials.append(wm)
        q2 = bpy.data.meshes.new("q2")
        q2.from_pydata([(-w / 2, 0, 1.15), (w / 2, 0, 1.15), (w / 2, 0, 1.75), (-w / 2, 0, 1.75)], [], [(0, 3, 2, 1)])
        q2o = bpy.data.objects.new("q2", q2)
        bpy.context.collection.objects.link(q2o)
        q2o.location.y = -0.04
        q2o.data.materials.append(sm)
    sun((1.0, 0.2, 0.3), 2.5)
    camera_ortho((0, -10, h / 2), (math.pi / 2, 0, 0), h)
    sc.render.resolution_x, sc.render.resolution_y = res
    cam = sc.camera.data
    cam.ortho_scale = h
    render(path)

# ───────────────────────── vegetación (sprites con fondo transparente) ─────────────────────────
def leaf_mesh(rnd, blobs, n, size, cols, flat=0.0):
    """muchas hojitas (rombos con una pequeña curva) agrupadas en bolas; color por vértice"""
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("col")
    for (c, r) in blobs:
        for _ in range(n):
            # punto dentro de la bola, con tendencia a la superficie (la copa es hueca por dentro)
            v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1) * (1 - flat))).normalized() * (r * (0.55 + 0.45 * rnd.random() ** 0.5))
            p = Vector(c) + v
            nrm = v.normalized() if v.length > 1e-4 else Vector((0, 0, 1))
            a = nrm.cross(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))).normalized()
            b = nrm.cross(a)
            s = size * rnd.uniform(0.7, 1.4)
            pts = [p - b * s * 0.9, p + a * s * 0.5 + nrm * s * 0.1, p + b * s * 0.9 + nrm * s * 0.2, p - a * s * 0.5 + nrm * s * 0.1]
            vs = [bm.verts.new(q) for q in pts]
            f = bm.faces.new(vs)
            col = rnd.choice(cols)
            k = rnd.uniform(0.75, 1.25) * (0.8 + 0.4 * ((p.z - (c[2] - r)) / (2 * r)))
            for l in f.loops:
                l[layer] = (col[0] * k, col[1] * k, col[2] * k, 1)
    me = bpy.data.meshes.new("leaves")
    bm.to_mesh(me)
    bm.free()
    return me

def foliage_material():
    m, nt = mat("hoja")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "col"
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.inputs["Roughness"].default_value = 0.7
    p.inputs["Specular IOR Level"].default_value = 0.1
    nt.links.new(vc.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(vc.outputs["Color"], p.inputs["Subsurface Radius"]) if False else None
    nt.links.new(p.outputs[0], out.inputs[0])
    return m

def bark_material(col=(0.075, 0.045, 0.028)):
    m, nt = mat("corteza")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (14, 14, 2)
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    nz = noise(nt, 6, 6, 0.6, mp.outputs[0])
    r = ramp(nt, [(0.0, (col[0] * 0.5, col[1] * 0.5, col[2] * 0.5, 1)), (1.0, (col[0] * 1.5, col[1] * 1.5, col[2] * 1.5, 1))])
    nt.links.new(nz.outputs["Fac"], r.inputs[0])
    p = principled(nt, None, 0.95)
    nt.links.new(r.outputs[0], p.inputs["Base Color"])
    bm = nt.nodes.new("ShaderNodeBump")
    bm.inputs["Strength"].default_value = 1.0
    nt.links.new(nz.outputs["Fac"], bm.inputs["Height"])
    nt.links.new(bm.outputs[0], p.inputs["Normal"])
    return m

def tube(bm, a, b, ra, rb, seg=8):
    """tronco/rama: cono truncado entre a y b"""
    d = (Vector(b) - Vector(a))
    L = d.length
    z = d.normalized()
    x = z.cross(Vector((0, 0, 1)) if abs(z.z) < 0.99 else Vector((1, 0, 0))).normalized()
    y = z.cross(x)
    ring_a, ring_b = [], []
    for i in range(seg):
        t = 2 * math.pi * i / seg
        dirv = x * math.cos(t) + y * math.sin(t)
        ring_a.append(bm.verts.new(Vector(a) + dirv * ra))
        ring_b.append(bm.verts.new(Vector(b) + dirv * rb))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new([ring_a[i], ring_a[j], ring_b[j], ring_b[i]])

def render_tree(path, builder, size=(512, 768), height=8.0, seed=1):
    rnd = random.Random(seed)
    sc = reset(size, transparent=True, samples=48)
    sky_world(0.8)
    sun((0.9, 0.3, 0.8), 2.4)
    bm = bmesh.new()
    cols, blobs, trunk = builder(rnd, bm)
    me = bpy.data.meshes.new("trunk")
    bm.to_mesh(me)
    bm.free()
    for f in me.polygons:
        f.use_smooth = True
    to = bpy.data.objects.new("trunk", me)
    bpy.context.collection.objects.link(to)
    to.data.materials.append(bark_material())
    lm = leaf_mesh(rnd, blobs["blobs"], blobs["n"], blobs["size"], cols, blobs.get("flat", 0.0))
    lo = bpy.data.objects.new("leaves", lm)
    bpy.context.collection.objects.link(lo)
    lo.data.materials.append(foliage_material())
    ar = size[0] / size[1]
    cam = camera_ortho((0, -30, height / 2), (math.pi / 2, 0, 0), height * 1.04)
    cam.data.shift_y = 0.0
    sc.render.resolution_x, sc.render.resolution_y = size
    render(path)

def build_round(rnd, bm):
    tube(bm, (0, 0, 0), (0.05, 0, 2.6), 0.28, 0.15, 10)
    tube(bm, (0.05, 0, 2.2), (-1.0, 0.2, 4.2), 0.12, 0.05, 6)
    tube(bm, (0.05, 0, 2.5), (1.1, -0.2, 4.4), 0.12, 0.05, 6)
    tube(bm, (0.05, 0, 2.6), (0.0, 0.1, 4.8), 0.14, 0.05, 6)
    cols = [(0.10, 0.28, 0.06), (0.16, 0.38, 0.08), (0.22, 0.45, 0.10), (0.13, 0.32, 0.07)]
    blobs = [((0, 0, 5.0), 1.7), ((-1.3, 0.3, 4.4), 1.3), ((1.4, -0.2, 4.6), 1.35), ((0.2, 0.2, 6.2), 1.2), ((-0.6, -0.4, 5.6), 1.2), ((0.9, 0.3, 5.8), 1.1)]
    return cols, {"blobs": blobs, "n": 520, "size": 0.26}, None

def build_conifer(rnd, bm):
    tube(bm, (0, 0, 0), (0, 0, 7.4), 0.22, 0.04, 8)
    cols = [(0.04, 0.17, 0.07), (0.07, 0.24, 0.10), (0.10, 0.30, 0.13)]
    blobs = []
    for i in range(9):
        z = 1.2 + i * 0.68
        r = max(0.25, 1.65 * (1 - i / 9.4))
        blobs.append(((0, 0, z), r))
    return cols, {"blobs": blobs, "n": 150, "size": 0.2, "flat": 0.6}, None

def build_poplar(rnd, bm):
    tube(bm, (0, 0, 0), (0, 0, 3.0), 0.2, 0.1, 8)
    cols = [(0.16, 0.34, 0.07), (0.24, 0.44, 0.09), (0.30, 0.50, 0.12)]
    blobs = [((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), 2.8 + i * 0.75), 0.95 - abs(i - 3.5) * 0.06) for i in range(9)]
    return cols, {"blobs": blobs, "n": 190, "size": 0.2}, None

def build_autumn(rnd, bm):
    tube(bm, (0, 0, 0), (0.0, 0, 2.2), 0.24, 0.13, 10)
    tube(bm, (0, 0, 1.9), (-1.2, 0, 3.6), 0.11, 0.04, 6)
    tube(bm, (0, 0, 2.0), (1.2, 0, 3.9), 0.11, 0.04, 6)
    cols = [(0.62, 0.30, 0.05), (0.78, 0.45, 0.07), (0.55, 0.18, 0.04), (0.70, 0.55, 0.10)]
    blobs = [((0, 0, 4.3), 1.7), ((-1.5, 0, 3.9), 1.2), ((1.5, 0, 4.2), 1.3), ((0, 0, 5.6), 1.1)]
    return cols, {"blobs": blobs, "n": 420, "size": 0.25}, None

def recolor(builder, cols, scale_blobs=1.0):
    def b(rnd, bm):
        c, bl, t = builder(rnd, bm)
        return cols, bl, t
    return b

def tex_valla(path, W=3.0, H=1.2, res=(768, 308)):
    """cerco de madera (tramo de 3 m que se repite): dos tablones horizontales y un poste; fondo transparente"""
    sc = reset(res, transparent=True, samples=40)
    sky_world(0.9)
    sun((0.9, 0.3, 0.8), 3.0)
    wm = bark_material((0.30, 0.19, 0.10))
    def box(c, size):
        me = bpy.data.meshes.new("b")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(c) @ Matrix.Diagonal((size[0], size[1], size[2], 1)))
        bm.to_mesh(me); bm.free()
        for p_ in me.polygons: p_.use_smooth = False
        o = bpy.data.objects.new("b", me); bpy.context.collection.objects.link(o); o.data.materials.append(wm)
    box((0.3, 0, 0.55), (0.14, 0.14, 1.1))            # poste
    box((0.3, 0, 1.12), (0.20, 0.16, 0.05))           # tapa
    box((W / 2, -0.08, 0.86), (W, 0.05, 0.20))        # tablón de arriba
    box((W / 2, -0.08, 0.50), (W, 0.05, 0.20))        # tablón del medio
    box((W / 2, -0.08, 0.16), (W, 0.05, 0.14))        # tablón de abajo
    camera_ortho((W / 2, -10, H / 2 - 0.0), (math.pi / 2, 0, 0), W)
    cam = sc.camera.data
    cam.sensor_fit = "HORIZONTAL"
    cam.ortho_scale = W
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.camera.location = (W / 2, -10, H / 2 + 0.0)
    render(path)

def render_bush(path, seed, cols, size=(512, 384), spread=1.0, n=380, flowers=None):
    rnd = random.Random(seed)
    sc = reset(size, transparent=True, samples=40)
    sky_world(0.8)
    sun((0.9, 0.3, 0.8), 2.4)
    blobs = [((rnd.uniform(-1.0, 1.0) * spread, rnd.uniform(-0.3, 0.3), 0.7 + rnd.uniform(0, 0.6)), rnd.uniform(0.7, 1.05)) for _ in range(6)]
    lm = leaf_mesh(rnd, blobs, n // 2, 0.2, cols, 0.2)
    lo = bpy.data.objects.new("leaves", lm)
    bpy.context.collection.objects.link(lo)
    lo.data.materials.append(foliage_material())
    if flowers:
        fm, fnt = mat("flor")
        fp = principled(fnt, (*flowers, 1), 0.6)
        bm = bmesh.new()
        for _ in range(60):
            c, r = rnd.choice(blobs)
            v = Vector((rnd.gauss(0, 1), rnd.gauss(0, 0.3), abs(rnd.gauss(0, 1)))).normalized() * r * 0.98
            p = Vector(c) + v
            bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.07, matrix=Matrix.Translation(p))
        me = bpy.data.meshes.new("fl")
        bm.to_mesh(me)
        bm.free()
        fo = bpy.data.objects.new("fl", me)
        bpy.context.collection.objects.link(fo)
        fo.data.materials.append(fm)
    cam = camera_ortho((0, -30, 1.0), (math.pi / 2, 0, 0), 2.7)
    sc.render.resolution_x, sc.render.resolution_y = size
    render(path)

def render_grass(path, seed, size=(256, 256), tall=0.55, col=(0.2, 0.45, 0.1), dry=False):
    rnd = random.Random(seed)
    sc = reset(size, transparent=True, samples=36)
    sky_world(0.8)
    sun((0.9, 0.3, 0.8), 2.5)
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("col")
    for _ in range(70):
        x = rnd.gauss(0, 0.16)
        y = rnd.gauss(0, 0.04)
        hgt = tall * rnd.uniform(0.45, 1.0)
        lean = rnd.uniform(-0.18, 0.18)
        w = 0.02
        pts = []
        for k in range(5):
            t = k / 4
            px = x + lean * t * t * hgt + math.sin(t * 2 + x * 10) * 0.01
            pz = hgt * t
            ww = w * (1 - t * 0.9)
            pts.append((Vector((px - ww, y, pz)), Vector((px + ww, y, pz))))
        vs = [(bm.verts.new(a), bm.verts.new(b)) for a, b in pts]
        for k in range(4):
            f = bm.faces.new([vs[k][0], vs[k][1], vs[k + 1][1], vs[k + 1][0]])
            for l in f.loops:
                tt = (k + 1) / 4
                kk = 0.6 + 0.7 * tt
                if dry:
                    c = (0.55 * kk, 0.45 * kk, 0.16 * kk)
                else:
                    c = (col[0] * kk * rnd.uniform(0.9, 1.1), col[1] * kk * rnd.uniform(0.9, 1.1), col[2] * kk)
                l[layer] = (*c, 1)
    me = bpy.data.meshes.new("g")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("g", me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(foliage_material())
    camera_ortho((0, -10, tall * 0.5), (math.pi / 2, 0, 0), tall * 1.15)
    sc.render.resolution_x, sc.render.resolution_y = size
    render(path)

def render_flower(path, seed, petal, center=(0.9, 0.65, 0.05), size=(128, 192), petals=8, tall=0.35):
    rnd = random.Random(seed)
    sc = reset(size, transparent=True, samples=36)
    sky_world(1.2)
    sun((0.9, 0.3, 0.8), 3.0)
    stem_m, snt = mat("tallo")
    principled(snt, (0.12, 0.3, 0.06, 1), 0.7)
    pm, pnt = mat("petalo")
    principled(pnt, (*petal, 1), 0.5)
    cm, cnt = mat("centro")
    principled(cnt, (*center, 1), 0.6)
    bm = bmesh.new()
    tube(bm, (0, 0, 0), (0.02, 0, tall), 0.012, 0.008, 5)
    for lf in range(2):  # hojitas
        z = tall * (0.2 + 0.2 * lf)
        s = -1 if lf else 1
        vs = [bm.verts.new(v) for v in [(0, 0, z), (s * 0.05, 0, z + 0.03), (s * 0.12, 0, z + 0.08), (s * 0.05, 0.005, z + 0.01)]]
        bm.faces.new(vs)
    me = bpy.data.meshes.new("s")
    bm.to_mesh(me)
    bm.free()
    so = bpy.data.objects.new("s", me)
    bpy.context.collection.objects.link(so)
    so.data.materials.append(stem_m)
    pb = bmesh.new()
    for i in range(petals):
        a = 2 * math.pi * i / petals
        c, s = math.cos(a), math.sin(a)
        L, W = 0.07, 0.03
        base = Vector((0.02, 0, tall))
        # pétalo = rombo contenido en el plano de la flor (mira de frente: plano XZ), levemente curvado
        d = Vector((c, 0, s))
        n = Vector((-s, 0, c))
        vs = [pb.verts.new(base), pb.verts.new(base + d * L * 0.5 + n * W * 0.5 + Vector((0, -0.01, 0))), pb.verts.new(base + d * L), pb.verts.new(base + d * L * 0.5 - n * W * 0.5 + Vector((0, -0.01, 0)))]
        pb.faces.new(vs)
    pe = bpy.data.meshes.new("p")
    pb.to_mesh(pe)
    pb.free()
    po = bpy.data.objects.new("p", pe)
    bpy.context.collection.objects.link(po)
    po.data.materials.append(pm)
    cb = bmesh.new()
    bmesh.ops.create_icosphere(cb, subdivisions=2, radius=0.022, matrix=Matrix.Translation((0.02, -0.012, tall)))
    ce = bpy.data.meshes.new("c")
    cb.to_mesh(ce)
    cb.free()
    co = bpy.data.objects.new("c", ce)
    bpy.context.collection.objects.link(co)
    co.data.materials.append(cm)
    camera_ortho((0, -10, tall * 0.55), (math.pi / 2, 0, 0), tall * 1.2)
    sc.render.resolution_x, sc.render.resolution_y = size
    render(path)

# ───────────────────────── marcas del estacionamiento ─────────────────────────
def tex_marcas(path, W=100.0, H=70.0, ppm=20, bays=None):
    """pintura vial desgastada sobre fondo transparente. Vista desde arriba: +X a la derecha, +Z hacia ABAJO (como mira el juego); cubre 100×70 m."""
    res = (int(W * ppm), int(H * ppm))
    sc = reset(res, transparent=True, samples=8)
    world_color((1, 1, 1), 1.0)
    # emisión pura (sin sombras ni luces): el color pintado se ve igual en todas partes
    pm, pnt = mat("pintura")
    nz = noise(pnt, 40, 6, 0.6, pnt.nodes.new("ShaderNodeTexCoord").outputs["Object"])
    wear = ramp(pnt, [(0.40, (0.2, 0.2, 0.2, 1)), (0.58, (1, 1, 1, 1))])
    pnt.links.new(nz.outputs["Fac"], wear.inputs[0])
    tr = pnt.nodes.new("ShaderNodeBsdfTransparent")
    em = pnt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (0.92, 0.92, 0.88, 1)
    mixs = pnt.nodes.new("ShaderNodeMixShader")
    pnt.links.new(wear.outputs[0], mixs.inputs[0])
    pnt.links.new(tr.outputs[0], mixs.inputs[1])
    pnt.links.new(em.outputs[0], mixs.inputs[2])
    o = pnt.nodes.new("ShaderNodeOutputMaterial")
    pnt.links.new(mixs.outputs[0], o.inputs[0])
    ym, ynt = mat("amarilla")
    ynz = noise(ynt, 40, 6, 0.6, ynt.nodes.new("ShaderNodeTexCoord").outputs["Object"])
    ywear = ramp(ynt, [(0.40, (0.2, 0.2, 0.2, 1)), (0.58, (1, 1, 1, 1))])
    ynt.links.new(ynz.outputs["Fac"], ywear.inputs[0])
    ytr = ynt.nodes.new("ShaderNodeBsdfTransparent")
    yem = ynt.nodes.new("ShaderNodeEmission")
    yem.inputs[0].default_value = (0.95, 0.72, 0.05, 1)
    ymix = ynt.nodes.new("ShaderNodeMixShader")
    ynt.links.new(ywear.outputs[0], ymix.inputs[0])
    ynt.links.new(ytr.outputs[0], ymix.inputs[1])
    ynt.links.new(yem.outputs[0], ymix.inputs[2])
    yo = ynt.nodes.new("ShaderNodeOutputMaterial")
    ynt.links.new(ymix.outputs[0], yo.inputs[0])
    bm_w = bmesh.new()
    bm_y = bmesh.new()

    def rect(bm, x0, z0, x1, z1):
        # coordenadas del lote (x, z) → plano de Blender (x, -z): +Z del juego hacia abajo en la imagen
        vs = [bm.verts.new((x0, -z0, 0)), bm.verts.new((x1, -z0, 0)), bm.verts.new((x1, -z1, 0)), bm.verts.new((x0, -z1, 0))]
        bm.faces.new(vs)

    def line(bm, x0, z0, x1, z1, wdt=0.12):
        d = Vector((x1 - x0, z1 - z0))
        n = Vector((-d.y, d.x)).normalized() * wdt / 2
        vs = [bm.verts.new((x0 - n.x, -(z0 - n.y), 0)), bm.verts.new((x1 - n.x, -(z1 - n.y), 0)), bm.verts.new((x1 + n.x, -(z1 + n.y), 0)), bm.verts.new((x0 + n.x, -(z0 + n.y), 0))]
        bm.faces.new(vs)

    # bahías de estacionamiento (fila norte, 12 plazas de 2,6 × 5,2 m)
    for i in range(13):
        x = -42 + i * 2.7
        line(bm_w, x, 24.0, x, 29.2)
    line(bm_w, -42, 24.0, -42 + 12 * 2.7, 24.0)
    # fila sur de bahías en 45°
    for i in range(10):
        x = -42 + i * 3.0
        line(bm_w, x, -12.0, x + 3.4, -17.5)
    # carril central amarillo discontinuo
    xx = -48
    while xx < 8:
        line(bm_y, xx, 11.0, xx + 2.4, 11.0, 0.14)
        xx += 4.6
    # paso peatonal (cebra)
    for i in range(9):
        z = -7.5 + i * 0.7
        rect(bm_w, -2.0, z, 3.0, z + 0.4)
    # flechas
    def arrow(bm, cx, cz, ang=0.0, s=1.0):
        pts = [(0, -1.6), (0.7, -0.5), (0.25, -0.5), (0.25, 1.6), (-0.25, 1.6), (-0.25, -0.5), (-0.7, -0.5)]
        ca, sa = math.cos(ang), math.sin(ang)
        vs = [bm.verts.new((cx + (x * ca - z * sa) * s, -(cz + (x * sa + z * ca) * s), 0)) for x, z in pts]
        try:
            bmesh.ops.contextual_create(bm, geom=vs)
        except Exception:
            pass
    arrow(bm_w, -30, 6, math.pi, 1.0)
    arrow(bm_w, -22, 16, 0.0, 1.0)
    arrow(bm_w, 10, -22, -math.pi / 2, 1.0)
    # bordes y carteles de zona de pruebas (líneas amarillas)
    line(bm_y, 8.5, -33, 8.5, 0, 0.18)
    # recuadro de largada
    for pt in [(-6, -29), (6, -29)]:
        line(bm_w, pt[0], pt[1], pt[0], pt[1] + 6, 0.12)
    line(bm_w, -6, -29, 6, -29, 0.12)
    for bm, m in ((bm_w, pm), (bm_y, ym)):
        me = bpy.data.meshes.new("mk")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("mk", me)
        bpy.context.collection.objects.link(ob)
        ob.data.materials.append(m)
    camera_ortho((0, 0, 20), (0, 0, 0), W)
    sc.render.resolution_x, sc.render.resolution_y = res
    # el encuadre horizontal manda: ortho_scale = ancho
    bpy.context.scene.camera.data.ortho_scale = W
    bpy.context.scene.camera.data.sensor_fit = "HORIZONTAL"
    render(path)

def tex_cielo(path, res=(1024, 512)):
    sc = reset(res, samples=16)
    sky_world(1.0)
    w = sc.world.node_tree.nodes["Sky Texture"]
    w.sun_elevation = math.radians(38)
    w.altitude = 50
    w.air_density = 1.0
    cam = bpy.data.cameras.new("pano")
    cam.type = "PANO"
    try:
        cam.panorama_type = "EQUIRECTANGULAR"
    except Exception:
        cam.cycles.panorama_type = "EQUIRECTANGULAR"
    co = bpy.data.objects.new("pano", cam)
    bpy.context.collection.objects.link(co)
    co.rotation_euler = (math.pi / 2, 0, 0)
    sc.camera = co
    sc.render.image_settings.file_format = "PNG"
    render(path)

TASKS = {}

def main():
    global OUT
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    names = []
    i = 0
    while i < len(a):
        if a[i] == "--out":
            OUT = a[i + 1]
            i += 2
        else:
            names.append(a[i])
            i += 1
    os.makedirs(OUT, exist_ok=True)
    P = lambda n: os.path.join(OUT, n)
    jobs = {
        "asfalto": lambda: tex_asfalto(P("asfalto.png")),
        "tierra": lambda: tex_tierra(P("tierra.png")),
        "pasto": lambda: tex_pasto(P("pasto.png")),
        "hormigon": lambda: tex_hormigon(P("hormigon.png")),
        "carton": lambda: tex_carton(P("carton.png")),
        "marcas": lambda: tex_marcas(P("marcas.png")),
        "fachadas": lambda: [tex_fachada(P("fachada_a.png"), 1, (0.72, 0.60, 0.48), (0.10, 0.18, 0.26), shop=True), tex_fachada(P("fachada_b.png"), 2, (0.62, 0.64, 0.66), (0.08, 0.16, 0.2), 5, 9),
                              tex_fachada(P("fachada_c.png"), 3, (0.76, 0.70, 0.62), (0.12, 0.2, 0.28), 7, 7, shop=True), tex_fachada(P("fachada_d.png"), 4, (0.58, 0.40, 0.34), (0.1, 0.16, 0.2), 6, 8)],
        "arboles": lambda: [render_tree(P("arbol_redondo.png"), build_round, (512, 768), 8.0, 1), render_tree(P("arbol_cipres.png"), build_conifer, (384, 768), 8.0, 2),
                            render_tree(P("arbol_alamo.png"), build_poplar, (320, 768), 8.0, 3), render_tree(P("arbol_otono.png"), build_autumn, (512, 640), 7.0, 4)],
        "arboles2": lambda: [render_tree(P("arbol_amarillo.png"), recolor(build_round, [(0.85, 0.72, 0.08), (0.95, 0.82, 0.14), (0.75, 0.6, 0.05)]), (512, 768), 8.0, 11),
                             render_tree(P("arbol_rojo.png"), recolor(build_round, [(0.62, 0.07, 0.05), (0.78, 0.12, 0.06), (0.5, 0.05, 0.05)]), (512, 768), 8.0, 12),
                             render_tree(P("arbol_rosa.png"), recolor(build_round, [(0.95, 0.55, 0.7), (0.98, 0.7, 0.8), (0.9, 0.42, 0.62)]), (512, 768), 8.0, 13),
                             render_tree(P("arbol_violeta.png"), recolor(build_autumn, [(0.45, 0.2, 0.7), (0.6, 0.35, 0.82), (0.35, 0.12, 0.6)]), (512, 640), 7.0, 14),
                             render_tree(P("arbol_cipres_azul.png"), recolor(build_conifer, [(0.1, 0.3, 0.38), (0.15, 0.4, 0.48), (0.2, 0.48, 0.55)]), (384, 768), 8.0, 15),
                             render_tree(P("arbol_alamo_amarillo.png"), recolor(build_poplar, [(0.9, 0.75, 0.1), (0.95, 0.85, 0.2)]), (320, 768), 8.0, 16)],
        "valla": lambda: tex_valla(P("valla.png")),
        "arbustos": lambda: [render_bush(P("arbusto_verde.png"), 5, [(0.10, 0.30, 0.07), (0.16, 0.40, 0.09), (0.2, 0.46, 0.12)]),
                             render_bush(P("arbusto_flores_rosa.png"), 6, [(0.10, 0.30, 0.07), (0.16, 0.40, 0.09)], flowers=(0.9, 0.25, 0.45)),
                             render_bush(P("arbusto_flores_amarillo.png"), 7, [(0.12, 0.32, 0.07), (0.18, 0.42, 0.09)], flowers=(0.98, 0.82, 0.12))],
        "pasto_sprite": lambda: [render_grass(P("pasto_mata.png"), 1), render_grass(P("pasto_alto.png"), 2, (256, 384), 0.9, (0.22, 0.46, 0.1)), render_grass(P("pasto_seco.png"), 3, (256, 256), 0.6, dry=True)],
        "flores": lambda: [render_flower(P("flor_blanca.png"), 1, (0.97, 0.97, 0.95)), render_flower(P("flor_amarilla.png"), 2, (0.98, 0.8, 0.1), (0.5, 0.3, 0.05)),
                           render_flower(P("flor_roja.png"), 3, (0.85, 0.1, 0.1), (0.1, 0.05, 0.02), petals=6), render_flower(P("flor_violeta.png"), 4, (0.55, 0.3, 0.85), (0.95, 0.85, 0.2), petals=7)],
        "cielo": lambda: tex_cielo(P("cielo.png")),
    }
    for n in (names or list(jobs)):
        print("== ", n, flush=True)
        jobs[n]()

main()
