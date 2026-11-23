#!/usr/bin/env python3
"""Arma godot/game/data/vehicles.json con los 6 autos: geometría MEDIDA del modelo (models/cars/<id>.json) + datos reales del auto.
Parte de una ficha base del kit (gt / muscle / pickup / suv) y pisa lo que cambia. Luego tools/test/perf_test.gd mide 0-100 y velocidad máxima.
Uso: python3 tools/gen_vehicles.py"""
import json, os, copy
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
G = os.path.join(ROOT, 'godot', 'game')
base = json.load(open(os.path.join(ROOT, 'tools', 'kit', 'vehicles_base.json')))

# datos reales (fuentes: fichas de fábrica) — torque en N·m del motor, potencia en kW, relaciones de la caja y del diferencial
## Agarre relativo al del asfalto en tierra / banquina / pasto / barro. Valores razonados con el tipo de goma y tracción de cada auto
## (la tierra compacta da ~50-60 % del agarre del asfalto con gomas de calle; una pick-up con gomas todo terreno y 4x4 conserva ~80 %; los slicks de competición son lo peor)
SURF = {
    "mclaren_f1": (0.50, 0.60, 0.38, 0.26), "mclaren_f1_gtr": (0.42, 0.54, 0.34, 0.22), "aventador_s": (0.52, 0.62, 0.40, 0.28),
    "ranger_limited": (0.84, 0.80, 0.62, 0.52), "rx3_savanna": (0.62, 0.70, 0.46, 0.32), "cls63_amg": (0.58, 0.66, 0.42, 0.30),
}

SPEC = {
    "mclaren_f1": dict(base="gt", mass=1140, wf=0.42, com=0.46, torque=650, idle=900, maxrpm=7500, launch=3600,
        curve=[[0, .42], [900, .62], [2500, .86], [4000, 1], [7000, 1], [7500, .93], [8000, .6]],
        gears=[3.23, 2.19, 1.71, 1.39, 1.16, 0.93], final=3.25, drive="RWD", cx=0.34, mu=1.32, tire_w=0.30, travel=0.13,
        freq=(1.7, 1.9), brake=6600, aero=(0.10, 0.25), steer=0.5, icon="🏎️", tag="Supercar de 1993 · V12 · asiento central", gov=0),
    "mclaren_f1_gtr": dict(base="gt3", mass=1050, wf=0.43, com=0.44, torque=640, idle=1000, maxrpm=7600, launch=4200,
        curve=[[0, .40], [1000, .60], [2800, .88], [4200, 1], [7000, 1], [7600, .92], [8100, .55]],
        gears=[2.90, 1.95, 1.56, 1.28, 1.06, 0.89], final=3.55, drive="RWD", cx=0.40, mu=1.45, tire_w=0.34, travel=0.11,
        freq=(2.1, 2.3), brake=7800, aero=(0.70, 1.45), steer=0.48, icon="🏁", tag="Competición GT · V12 · alerón gigante", gov=0),
    "aventador_s": dict(base="gt", mass=1575, wf=0.43, com=0.47, torque=690, idle=900, maxrpm=8500, launch=5200, ps=1.18, clutch=0.45,
        curve=[[0, .58], [1000, .72], [2500, .88], [4000, .96], [5500, 1], [8000, .98], [8500, .90], [9000, .55]],
        gears=[3.91, 2.44, 1.81, 1.46, 1.19, 0.97, 0.81], final=3.75, drive="AWD", front=0.30, cx=0.53, mu=1.34, tire_w=0.335, travel=0.12,
        freq=(1.8, 2.0), brake=7600, aero=(0.18, 0.45), steer=0.5, icon="🐂", tag="Hiperdeportivo V12 · tracción integral", gov=0),
    "ranger_limited": dict(base="pickup", mass=2300, wf=0.55, com=0.80, torque=600, idle=750, maxrpm=4600, launch=2200,
        curve=[[0, .55], [750, .72], [1750, 1], [2800, 1], [3800, .80], [4400, .60], [4800, .35]],
        gears=[4.69, 3.13, 2.10, 1.67, 1.29, 1.00, 0.84, 0.67], final=3.55, drive="AWD", front=0.5, cx=0.80, mu=0.97, tire_w=0.265, travel=0.33,
        freq=(1.2, 1.15), brake=11500, aero=(0, 0), steer=0.5, icon="🛻", tag="Pick-up 4x4 · diésel V6 turbo", gov=185),
    "rx3_savanna": dict(base="muscle", mass=975, wf=0.52, com=0.47, torque=178, idle=900, maxrpm=7500, launch=3600,
        curve=[[0, .45], [1000, .62], [2500, .84], [4000, 1], [6500, .96], [7500, .80], [8000, .5]],
        gears=[3.38, 2.06, 1.38, 1.0, 0.85], final=4.1, drive="RWD", cx=0.43, mu=1.08, tire_w=0.17, travel=0.14,
        freq=(1.3, 1.4), brake=4300, aero=(0, 0), steer=0.55, icon="🌀", tag="Cupé clásico japonés · motor rotativo", gov=0),
    "cls63_amg": dict(base="gt", mass=1980, wf=0.55, com=0.50, torque=720, idle=750, maxrpm=6500, launch=2600,
        curve=[[0, .55], [750, .70], [1750, 1], [5250, 1], [5800, .93], [6500, .75], [6900, .45]],
        gears=[4.38, 2.86, 1.92, 1.37, 1.0, 0.82, 0.73], final=2.65, drive="AWD", front=0.35, cx=0.42, mu=1.14, tire_w=0.285, travel=0.15,
        freq=(1.45, 1.55), brake=8600, aero=(0.0, 0.0), steer=0.52, icon="🚘", tag="Sedán deportivo AMG · V8 biturbo · tracción total", gov=250),
}

def main():
    out = {}
    for cid, S in SPEC.items():
        meta = json.load(open(os.path.join(G, 'models', 'cars', cid + '.json')))
        v = copy.deepcopy(base[S["base"]])
        L = meta["wheelBase"]
        m = S["mass"]
        v["name"] = meta["name"]
        v["visualType"] = cid
        v["icon"] = S["icon"]
        v["tagline"] = S["tag"]
        v["mass"] = m
        v["weightFront"] = S["wf"]
        v["comHeight"] = S["com"]
        v["wheelBase"] = round(L, 3)
        v["trackF"] = round(meta["trackF"], 3)
        v["trackR"] = round(meta["trackR"], 3)
        v["wheelRadius"] = round(meta["wheelRadius"], 3)
        v["rimRadius"] = round(meta["wheelRadius"] * 0.62, 3)
        v["tireWidth"] = S["tire_w"]
        v["wheelInertia"] = round(0.7 * (m / 100.0) * meta["wheelRadius"] ** 2 * 1.8, 2) if False else round(7 + m / 400.0, 1)
        Izz = m * (L * L + meta["trackF"] ** 2) / 12.0
        v["Izz"] = round(Izz)
        v["Iyy"] = round(Izz * 0.85)
        v["Ixx"] = round(Izz * 0.3)
        v["travel"] = S["travel"]
        v["freqF"], v["freqR"] = S["freq"]
        v["mu"] = S["mu"]
        v["peakTorque"] = S["torque"]
        v["idleRpm"] = S["idle"]
        v["maxRpm"] = S["maxrpm"]
        v["launchRpm"] = S["launch"]
        v["torqueCurve"] = S["curve"]
        v["gears"] = S["gears"]
        v["finalDrive"] = S["final"]
        v["shiftUpRpm"] = round(S["maxrpm"] * 0.93)
        v["shiftDownRpm"] = round(S["launch"] * 0.9)
        v["driveType"] = S["drive"]
        if S["drive"] == "AWD":
            v["frontDriveRatio"] = S["front"]
            v["rearDriveRatio"] = 1 - S["front"]
        elif S["drive"] == "RWD":
            v["frontDriveRatio"], v["rearDriveRatio"] = 0.0, 1.0
        v["dragCoef"] = S["cx"]
        v["brakeTorque"] = S["brake"]
        v["aeroF"], v["aeroR"] = S["aero"]
        v["maxSteer"] = S["steer"]
        v["vGov"] = S["gov"]
        v["engineBrake"] = round(S["torque"] * 0.2)
        v["powerScale"] = S.get("ps", 1)
        d_, sh_, g_, m_ = SURF[cid]
        v["surfGrip"] = {"asphalt": 1, "dirt": d_, "shoulder": sh_, "grass": g_, "outside": 0.4, "mud": m_}
        if "clutch" in S:
            v["clutchTime"] = S["clutch"]
        for k in ("aeroBaseF", "aeroBaseR"):
            v.pop(k, None)
        out[cid] = v
    json.dump(out, open(os.path.join(G, 'data', 'vehicles.json'), 'w'), indent=1, ensure_ascii=False)
    print("vehicles.json:", ", ".join(out))

if __name__ == '__main__':
    main()
