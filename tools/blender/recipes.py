"""Recetas de cada auto para process_car.py (se ejecuta dentro de Blender / bpy).

Convención de los GLB originales (formato GTA): el auto mira a +Z (glTF), la IZQUIERDA es +X, el origen está en el centro del auto.
  corner:  fl = delantera izquierda (+X, adelante) · fr = delantera derecha (-X) · rl / rr = traseras.

Campos:
  id, name (nombre real), maker, year, kind          datos para el menú
  src                                                 archivo GLB original (carpeta de autos)
  drop                                                nombres de objetos que se borran (variantes, ocultos, piezas internas que no se ven)
  wheels   corner -> ("obj", [objetos])               rueda que ya viene en el modelo
                   -> ("copy", corner_origen, girar, z_nuevo|None)   rueda copiada de otra (girar = rotarla 180° sobre el eje vertical para
                                                       que la cara de afuera mire hacia afuera del lado opuesto; z_nuevo = otro eje)
  parts    nombre -> {"ok": [objetos], "dam": [objetos]}   piezas que se rompen / se caen (ok = sana, dam = dañada, opcional)
  steer    objetos del volante (para ubicar las manos del piloto)  ·  steer_xyz (glTF) si no hay objeto
  wf       peso adelante (0..1)  ·  wheelbase_override  ·  budget (triángulos de la carrocería)  ·  drive_side  "L" | "R" | "C"
"""

CARS = {
    # ───────────────────────────── McLaren F1 (de calle) ─────────────────────────────
    "mclaren_f1": dict(
        name="McLaren F1", maker="McLaren", year=1993, kind="supercar",
        src="supergt_2.glb",
        drop=[],
        wheels={"fl": ("obj", ["Wheel FL"]), "fr": ("obj", ["Wheel FR"]), "rl": ("obj", ["Wheel RL"]), "rr": ("obj", ["Wheel RR"])},
        parts={
            "bump_front": {"ok": ["bump_front_ok"], "dam": ["bump_front_dam"]},
            "bump_rear": {"ok": ["bump_rear_ok", "exhaust_ok"], "dam": ["bump_rear_dam"]},
            "plate_rear": {"ok": ["plate_rear_ok"], "dam": ["plate_rear_dam"]},
            "bonnet": {"ok": ["bonnet_ok"], "dam": ["bonnet_dam"]},
            "boot": {"ok": ["boot_ok"], "dam": ["boot_dam"]},
            "windscreen": {"ok": ["windscreen_ok"], "dam": ["windscreen_dam"]},
            "door_lf": {"ok": ["door_lf_ok"], "dam": ["door_lf_dam"]},
            "door_rf": {"ok": ["door_rf_ok"], "dam": ["door_rf_dam"]},
        },
        steer=[], steer_xyz=(0.0, 0.12, 0.62), drive_side="C", paint=["remaphotrinabody256"],
        wf=0.42, budget=26000,
    ),
    # ───────────────────────────── McLaren F1 GTR (variante «LM») ─────────────────────────────
    "mclaren_f1_gtr": dict(
        name="McLaren F1 GTR", maker="McLaren", year=1995, kind="race",
        src="mclaren F1.glb",
        # el archivo trae las dos versiones (F1 de calle y GTR/LM) una arriba de la otra: nos quedamos con la GTR (las que llevan «(2)» o «[LM]»)
        drop=["Danos", "suspension", "storage", "engine", "chassis_a",
              "tahook", "speedook", "oilook", "petrolook", "tempook",
              "fender[F1]", "f_steer[F1]", "interiors[F1]", "wheel[F1]", "wheel[F1] (2)",
              "bonnet_ok", "bonnet_dam", "bump_front_ok", "bump_front_dam", "bump_rear_ok", "bump_rear_dam",
              "door_lr_ok", "door_lr_dam", "door_rr_ok", "door_rr_dam"],
        wheels={"fr": ("obj", ["wheel[LM]"]), "rr": ("obj", ["wheel[LM] (2)"]),
                "fl": ("copy", "fr", True, None), "rl": ("copy", "rr", True, None)},
        parts={
            "bonnet": {"ok": ["bonnet_ok (2)"], "dam": ["bonnet_dam (2)"]},
            "bump_front": {"ok": ["bump_front_ok (2)"], "dam": ["bump_front_dam (2)"]},
            "bump_rear": {"ok": ["bump_rear_ok (2)", "exhaust_ok"], "dam": ["bump_rear_dam (2)"]},
            "boot": {"ok": ["boot_ok", "tunk_ok", "f_spoiler[LM]", "f_an4b=ax-25s5"], "dam": ["boot_dam"]},
            "windscreen": {"ok": ["windscreen_ok"], "dam": ["windscreen_dam"]},
            "door_lf": {"ok": ["door_lf_ok"], "dam": ["door_lf_dam"]},
            "door_rf": {"ok": ["door_rf_ok"], "dam": ["door_rf_dam"]},
            "door_lr": {"ok": ["door_lr_ok (2)"], "dam": ["door_lr_dam (2)"]},
            "door_rr": {"ok": ["door_rr_ok (2)"], "dam": ["door_rr_dam (2)"]},
        },
        steer=["f_steer[LM]"], drive_side="C", paint=["remap"],
        wf=0.42, budget=34000,
    ),
    # ───────────────────────────── Lamborghini Aventador S ─────────────────────────────
    "aventador_s": dict(
        name="Lamborghini Aventador S", maker="Lamborghini", year=2017, kind="supercar",
        src="elegy.glb",
        drop=["Danos", "SideSkirts2 (2)", "SideSkirts2 (3)"],
        wheels={"fl": ("obj", ["Wheel FL"]), "fr": ("obj", ["Wheel FR"]), "rl": ("obj", ["Wheel RL"]), "rr": ("obj", ["Wheel RR"])},
        parts={
            "bump_front": {"ok": ["bump_front_ok"], "dam": ["bump_front_dam"]},
            "bump_rear": {"ok": ["bump_rear_ok", "Exhaust0"], "dam": ["bump_rear_dam"]},
            "bonnet": {"ok": ["Bonnets_ok"], "dam": []},
            "boot": {"ok": ["Boot_ok", "Spoilers2"], "dam": []},
            "windscreen": {"ok": ["windscreen_ok"], "dam": []},
            "door_lf": {"ok": ["door_lf_ok"], "dam": []},
            "door_rf": {"ok": ["door_rf_ok"], "dam": []},
        },
        steer=[], steer_xyz=(0.36, 0.25, 0.51), drive_side="L", paint=["remap"],
        fix_doors={"door_lf": 1.00, "door_rf": 1.00},
        wf=0.43, budget=46000,
    ),
    # ───────────────────────────── Ford Ranger Limited (2023) ─────────────────────────────
    "ranger_limited": dict(
        name="Ford Ranger Limited", maker="Ford", year=2023, kind="pickup",
        src="huntley.glb",
        drop=["Danos", "FR1", "FR2", "PackLTD", "Piso", "Guardabarros", "InteriorCaja"],
        # el modelo trae UNA sola rueda (delantera derecha, «LTD+-20»): se copia a las cuatro (eje trasero a 3,27 m: pasoruedas de atrás)
        wheels={"fr": ("obj", ["LTD+-20"]),
                "fl": ("copy", "fr", True, None), "rr": ("copy", "fr", False, -1.72), "rl": ("copy", "fr", True, -1.72)},
        parts={
            "bonnet": {"ok": ["bonnet_ok"], "dam": []},
            "boot": {"ok": ["boot_ok"], "dam": []},
            "bump_front": {"ok": ["Barra", "Parilla_black", "BordeParilla"], "dam": []},
            "bump_rear": {"ok": ["bump_rear_ok"], "dam": []},
            "door_lf": {"ok": ["door_lf_ok"], "dam": []},
            "door_rf": {"ok": ["door_rf_ok"], "dam": []},
            "door_lr": {"ok": ["door_lr_ok"], "dam": []},
            "door_rr": {"ok": ["door_rr_ok"], "dam": []},
        },
        steer=["Volante"], drive_side="L", paint=["Color_3CFF00"],
        wf=0.54, budget=60000, wheelbase_override=3.27,
    ),
    # ───────────────────────────── Mazda RX-3 Savanna ─────────────────────────────
    "rx3_savanna": dict(
        name="Mazda RX-3 Savanna", maker="Mazda", year=1973, kind="classic",
        src="hustler.glb",
        drop=["undercarriage", "lightshidhead", "svet1", "svet2", "svet3"],
        wheels={"fl": ("obj", ["Wheel FL"]), "fr": ("obj", ["Wheel FR"]), "rl": ("obj", ["Wheel RL"]), "rr": ("obj", ["Wheel RR"])},
        parts={
            "bonnet": {"ok": ["hood"], "dam": []},
            "boot": {"ok": ["trunk", "wing"], "dam": []},
            "bump_front": {"ok": ["bumperF", "plate_F"], "dam": []},
            "bump_rear": {"ok": ["bumperR", "plate", "exhaust_oki"], "dam": []},
            "windscreen": {"ok": ["glassF"], "dam": []},
            "door_lf": {"ok": ["dver L", "VN (2)", "obsh", "glassLF"], "dam": []},
            "door_rf": {"ok": ["Dver R", "VN (3)", "obsh (2)", "glassRF"], "dam": []},
        },
        steer=["rul"], drive_side="R", paint=["remap_kuzov"],
        wf=0.54, budget=52000,
    ),
    # ───────────────────────────── Mercedes-Benz CLS 63 AMG ─────────────────────────────
    "cls63_amg": dict(
        name="Mercedes-Benz CLS 63 AMG", maker="Mercedes-Benz", year=2015, kind="sedan",
        src="Cls63.glb",
        drop=["exhaust_ok", "engined", "engine_badge", "cockpit"],
        # una sola rueda en el archivo («Mesh 001», delantera derecha): se copia a las cuatro; eje trasero a 2,945 m
        wheels={"fr": ("obj", ["Mesh 001"]),
                "fl": ("copy", "fr", True, None), "rr": ("copy", "fr", False, -1.63), "rl": ("copy", "fr", True, -1.63)},
        parts={
            "bonnet": {"ok": ["bonnet", "bonnet_badge"], "dam": []},
            "boot": {"ok": ["boot"], "dam": []},
            "bump_front": {"ok": ["bumper_front", "bumper_front_grille"], "dam": []},
            "bump_rear": {"ok": ["bumper_rear", "bumper_rear_glass"], "dam": []},
            "windscreen": {"ok": ["windscreen (2)"], "dam": []},
            "door_lf": {"ok": ["door_dside_f", "door_dside_f_a"], "dam": []},
            "door_lr": {"ok": ["door_dside_r", "door_dside_r (2)"], "dam": []},
            "door_rf": {"ok": ["door_pside_f"], "dam": []},
            "door_rr": {"ok": ["door_pside_r", "door_pside_r (2)"], "dam": []},
        },
        steer=["steeringwheel", "steeringwheel_alpha"], drive_side="L", paint=["remap_body"],
        heavy=["interior", "interior_alpha", "lights_ok", "chassis"],
        wf=0.52, budget=100000, wheelbase_override=2.945,
    ),
}
