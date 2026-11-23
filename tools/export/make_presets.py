#!/usr/bin/env python3
"""Escribe godot/export_presets.cfg con los 3 presets del juego (lo corre la compilación antes de exportar; también sirve en la PC):
  · «Android Light»: el APK liviano = el motor + la pantalla de arranque (bootstrap). Al abrirse baja el resto. Firmado SIEMPRE con la misma llave.
  · «Content»: content.pck = el juego sin los modelos (código, escenario, texturas, sonidos, interfaz).
  · «Cars»: cars.pck = los autos y los pilotos (godot/game/models/). Pesa más y cambia poco: el teléfono lo vuelve a bajar sólo si cambió.
Uso: python3 tools/export/make_presets.py [--version-code N] [--version-name X]"""
import os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
G = os.path.join(ROOT, 'godot')

def android_options(code, name, pkg="com.simcars.extreme", app="SimCars Extreme"):
    return f'''custom_template/debug=""
custom_template/release=""
gradle_build/use_gradle_build=false
gradle_build/export_format=0
gradle_build/min_sdk=""
gradle_build/target_sdk=""
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
version/code={code}
version/name="{name}"
package/unique_name="{pkg}"
package/name="{app}"
package/signed=true
package/app_category=2
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_app_library=true
package/show_as_launcher_app=false
launcher_icons/main_192x192="res://store/icon_192.png"
launcher_icons/adaptive_foreground_432x432="res://store/adaptive_foreground_432.png"
launcher_icons/adaptive_background_432x432="res://store/adaptive_background_432.png"
graphics/opengl_debug=false
xr_features/xr_mode=0
gesture/swipe_to_dismiss=false
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_data_backup/allow=false
command_line/extra_args=""
apk_expansion/enable=false
permissions/internet=true
permissions/access_network_state=true
permissions/vibrate=true
'''

def preset(i, name, runnable, flt, include, exclude, path, files="", code=1, vname="0.1"):
    s = f'''[preset.{i}]

name="{name}"
platform="Android"
runnable={str(runnable).lower()}
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="{flt}"
'''
    if files:
        s += f'export_files=PackedStringArray({files})\n'
    s += f'''include_filter="{include}"
exclude_filter="{exclude}"
export_path="{path}"
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.{i}.options]

''' + android_options(code, vname)
    return s

def main():
    code, vname = 1, "0.1"
    a = sys.argv[1:]
    if "--version-code" in a:
        code = int(a[a.index("--version-code") + 1])
    if "--version-name" in a:
        vname = a[a.index("--version-name") + 1]
    models = []
    for d, _, fs in os.walk(os.path.join(G, 'game', 'models')):
        for f in sorted(fs):
            if f.endswith('.glb'):
                models.append('"res://' + os.path.relpath(os.path.join(d, f), G).replace(os.sep, '/') + '"')
    out = "\n".join([
        preset(0, "Android Light", True, "all_resources", "", "game/*, demo/*, tests/*, keystore/*, referencia/*", "../build/simcars-liviano.apk", code=code, vname=vname),
        preset(1, "Content", False, "all_resources", "*.json, *.txt", "bootstrap/*, demo/*, tests/*, keystore/*, game/models/*, store/*", "../build/content.pck", code=code, vname=vname),
        preset(2, "Cars", False, "resources", "game/models/*/*.json", "", "../build/cars.pck", files=", ".join(models), code=code, vname=vname),
    ])
    open(os.path.join(G, 'export_presets.cfg'), 'w').write(out)
    print("export_presets.cfg: %d modelos en cars.pck · versión %s (%d)" % (len(models), vname, code))

if __name__ == '__main__':
    main()
