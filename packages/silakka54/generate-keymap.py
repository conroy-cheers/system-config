#!/usr/bin/env python3
import argparse
import json
import re
from pathlib import Path


REPORT_MAGIC = b"KBLAYR"
SYNC_MAGIC = b"SL54SYN"
CURRENT_LAYER_HID_VERSION = 1
CURRENT_LAYER_HID_QUERY = 0
CURRENT_LAYER_HID_REPORT = 1
MIDI_PROTOCOL_VERSION = 1
MIDI_CHANNEL = 15

MIDI_CANDIDATE_CONTROLS = {
    ("left", "Ctrl"): 20,
    ("left", "Alt"): 21,
    ("left", "GUI"): 22,
    ("right", "GUI"): 23,
    ("right", "Alt"): 24,
    ("right", "Ctrl"): 25,
}
MIDI_MODIFIER_CONTROLS = {
    "Ctrl": 30,
    "Alt": 31,
    "GUI": 32,
    "Shift": 33,
}

ALIASES = {
    "___": "KC_TRNS",
    "TRNS": "KC_TRNS",
    "---": "KC_NO",
    "NO": "KC_NO",
    "Esc": "KC_ESC",
    "Tab": "KC_TAB",
    "Ctrl": "KC_LCTL",
    "Shift": "KC_LSFT",
    "GUI": "KC_LGUI",
    "Alt": "KC_LALT",
    "Space": "KC_SPC",
    "Enter": "KC_ENT",
    "Bspc": "KC_BSPC",
    "Del": "KC_DEL",
    "Ins": "KC_INS",
    "Home": "KC_HOME",
    "End": "KC_END",
    "PgUp": "KC_PGUP",
    "PgDn": "KC_PGDN",
    "Left": "KC_LEFT",
    "Down": "KC_DOWN",
    "Up": "KC_UP",
    "Right": "KC_RGHT",
    "Boot": "QK_BOOT",
    "Caps": "KC_CAPS",
    "Menu": "KC_APP",
    "Mute": "KC_MUTE",
    "Vol-": "KC_VOLD",
    "Vol+": "KC_VOLU",
    "Prev": "KC_MPRV",
    "Next": "KC_MNXT",
    "Play": "KC_MPLY",
    ",": "KC_COMM",
    ".": "KC_DOT",
    "/": "KC_SLSH",
    "-": "KC_MINS",
    "'": "KC_QUOT",
    ";": "KC_SCLN",
    "`": "KC_GRV",
    "\\": "KC_BSLS",
    "[": "KC_LBRC",
    "]": "KC_RBRC",
    "=": "KC_EQL",
    "!": "KC_EXLM",
    "@": "KC_AT",
    "#": "KC_HASH",
    "$": "KC_DLR",
    "%": "KC_PERC",
    "^": "KC_CIRC",
    "&": "KC_AMPR",
    "*": "KC_ASTR",
    "(": "KC_LPRN",
    ")": "KC_RPRN",
    "_": "KC_UNDS",
    "+": "KC_PLUS",
    "{": "KC_LCBR",
    "}": "KC_RCBR",
    "|": "KC_PIPE",
    ":": "KC_COLN",
    '"': "KC_DQUO",
    "<": "KC_LT",
    ">": "KC_GT",
    "?": "KC_QUES",
    "~": "KC_TILD",
}

QMK_ALIASES = {
    "KC_REDO": "KC_AGIN",
}

MOD_TAP_MACROS = {
    "LCTL_T": "MOD_LCTL",
    "LSFT_T": "MOD_LSFT",
    "LALT_T": "MOD_LALT",
    "LGUI_T": "MOD_LGUI",
    "RCTL_T": "MOD_RCTL",
    "RSFT_T": "MOD_RSFT",
    "RALT_T": "MOD_RALT",
    "RGUI_T": "MOD_RGUI",
}

MOD_TAP_MODS = {
    "MOD_LCTL": 0x01,
    "MOD_LSFT": 0x02,
    "MOD_LALT": 0x04,
    "MOD_LGUI": 0x08,
    "MOD_RCTL": 0x11,
    "MOD_RSFT": 0x12,
    "MOD_RALT": 0x14,
    "MOD_RGUI": 0x18,
}

MOD_TAP_C_MODS = frozenset(MOD_TAP_MODS)


def c_ident(name):
    return "_" + re.sub(r"[^A-Za-z0-9_]", "_", name).upper()


def qmk_keycode(label, layer_indices):
    label = str(label)
    if label in layer_indices:
        return f"MO({c_ident(label)})"
    if label in ALIASES:
        return ALIASES[label]
    if label in QMK_ALIASES:
        return QMK_ALIASES[label]
    if re.fullmatch(r"[A-Z]", label):
        return f"KC_{label}"
    if re.fullmatch(r"[0-9]", label):
        return f"KC_{label}"
    if re.fullmatch(r"F([1-9]|1[0-9]|2[0-4])", label):
        return f"KC_{label}"
    if label.startswith("KC_") or label.startswith("QK_") or "(" in label:
        return label
    raise ValueError(f"no QMK keycode alias for {label!r}")


KEYCODES = {}


def via_keycode(code):
    if match := re.fullmatch(r"([LR](?:CTL|SFT|ALT|GUI)_T)\(([^()]+)\)", code):
        modifier = MOD_TAP_MACROS[match.group(1)]
        return mod_tap_keycode(modifier, match.group(2).strip())
    if match := re.fullmatch(r"MT\(([^,]+),\s*([^()]+)\)", code):
        return mod_tap_keycode(match.group(1).strip(), match.group(2).strip())
    if match := re.fullmatch(r"LT\((_[A-Z0-9_]+),\s*([^()]+)\)", code):
        raise ValueError(f"unresolved layer name in {code!r}")
    if match := re.fullmatch(r"LT\((\d+),\s*([^()]+)\)", code):
        return layer_tap_keycode(int(match.group(1)), match.group(2).strip())
    if match := re.fullmatch(r"MO\((_[A-Z0-9_]+)\)", code):
        raise ValueError(f"unresolved layer name in {code!r}")
    if match := re.fullmatch(r"MO\((\d+)\)", code):
        return 0x5220 | int(match.group(1))
    if match := re.fullmatch(r"TO\((_[A-Z0-9_]+)\)", code):
        raise ValueError(f"unresolved layer name in {code!r}")
    if match := re.fullmatch(r"TO\((\d+)\)", code):
        layer = int(match.group(1))
        if not 0 <= layer <= 31:
            raise ValueError(f"layer move requires a layer from 0 through 31, got {layer}")
        return 0x5200 | layer
    if code in KEYCODES:
        return KEYCODES[code]
    raise ValueError(f"no VIA numeric keycode for {code!r}")


def mod_tap_keycode(modifier, tap_code):
    mods = 0
    for item in modifier.split("|"):
        item = item.strip()
        if item not in MOD_TAP_MODS:
            raise ValueError(f"unsupported mod-tap modifier {item!r}")
        mods |= MOD_TAP_MODS[item]
    tap = via_keycode(tap_code)
    if tap > 0xFF:
        raise ValueError(f"mod-tap requires a basic tap keycode, got {tap_code!r}")
    return 0x2000 | ((mods & 0x1F) << 8) | tap


def layer_tap_keycode(layer, tap_code):
    if not 0 <= layer <= 15:
        raise ValueError(f"layer-tap requires a layer from 0 through 15, got {layer}")
    tap = via_keycode(tap_code)
    if tap > 0xFF:
        raise ValueError(f"layer-tap requires a basic tap keycode, got {tap_code!r}")
    return 0x4000 | (layer << 8) | tap


def hash_bytes(hash_hex, length=8):
    if not re.fullmatch(r"[0-9a-fA-F]{64}", hash_hex):
        raise ValueError(f"expected sha256 hex hash, got {hash_hex!r}")
    return bytes.fromhex(hash_hex[: length * 2])


def render_layer(designator, keys, layer_indices):
    codes = [qmk_keycode(key, layer_indices) for key in keys]
    rows = [
        codes[0:12],
        codes[12:24],
        codes[24:36],
        codes[36:48],
        codes[48:54],
    ]
    rendered_rows = []
    for row in rows:
        rendered_rows.append("        " + ", ".join(f"{code:<8}" for code in row))
    return f"    [{designator}] = LAYOUT(\n" + ",\n".join(rendered_rows) + "\n    )"


def dynamic_entries(layers, layer_indices, layout):
    entries = []
    for layer_name, keys in layers.items():
        layer = layer_indices[layer_name]
        for index, (key, layout_entry) in enumerate(zip(keys, layout)):
            code = qmk_keycode(key, layer_indices)
            for name, layer_index in layer_indices.items():
                code = code.replace(f"MO({c_ident(name)})", f"MO({layer_index})")
                code = code.replace(f"LT({c_ident(name)},", f"LT({layer_index},")
                code = code.replace(f"TO({c_ident(name)})", f"TO({layer_index})")
            row, col = layout_entry["matrix"]
            entries.append(
                {
                    "layer": layer,
                    "layer_name": layer_name,
                    "index": index,
                    "row": row,
                    "col": col,
                    "label": str(key),
                    "qmk": code,
                    "keycode": via_keycode(code),
                }
            )
    return entries


DEFINE_NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")


def render_config_h(defines):
    lines = [
        "/* Generated from configuration.json. Do not edit. */",
        "#pragma once",
        "",
    ]
    for name, value in defines.items():
        if not DEFINE_NAME.fullmatch(name):
            raise ValueError(f"invalid QMK define name {name!r}")
        if isinstance(value, bool):
            if value:
                lines.append(f"#define {name}")
        elif isinstance(value, int):
            lines.append(f"#define {name} {value}")
        elif isinstance(value, str):
            lines.append(f"#define {name} {json.dumps(value)}")
        else:
            raise ValueError(f"unsupported value for QMK define {name}: {value!r}")
    return "\n".join(lines) + "\n"


def render_rules_mk(rules):
    lines = ["# Generated from configuration.json. Do not edit."]
    for name, value in rules.items():
        if not DEFINE_NAME.fullmatch(name):
            raise ValueError(f"invalid QMK rule name {name!r}")
        if not isinstance(value, bool):
            raise ValueError(f"QMK rule {name} must be boolean")
        lines.append(f"{name} = {'yes' if value else 'no'}")
    return "\n".join(lines) + "\n"


def render_keymap_yaml(layers):
    lines = ["layers:"]
    for layer in layers:
        lines.append(f"  {layer['name']}:")
        lines.extend(f"    - {json.dumps(key)}" for key in layer["keys"])
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def midi_protocol(configured_layers, layout):
    base_layers = [layer for layer in configured_layers if layer.get("name") == "Base"]
    if len(base_layers) != 1:
        raise ValueError("exactly one Base layer is required for MIDI candidate controls")

    candidates = []
    seen_controls = set()
    seen_keycodes = set()
    for index, keycode in enumerate(base_layers[0]["keys"]):
        match = re.fullmatch(r"([LR](CTL|ALT|GUI)_T)\(([^()]+)\)", str(keycode))
        if not match:
            continue
        family = {"CTL": "Ctrl", "ALT": "Alt", "GUI": "GUI"}[match.group(2)]
        matrix_row = layout[index]["matrix"][0]
        side = "left" if matrix_row < 5 else "right"
        identity = (side, family)
        if identity in seen_controls:
            raise ValueError(f"Base layer has duplicate {side} {family} MIDI candidate control")
        if keycode in seen_keycodes:
            raise ValueError(f"Base layer has duplicate MIDI candidate keycode {keycode}")
        seen_controls.add(identity)
        seen_keycodes.add(keycode)
        control = MIDI_CANDIDATE_CONTROLS[identity]
        candidates.append(
            {
                "control": control,
                "side": side,
                "family": family,
                "qmk": keycode,
                "tap_keycode": match.group(3),
            }
        )

    missing = set(MIDI_CANDIDATE_CONTROLS) - seen_controls
    if missing:
        raise ValueError(
            "Base layer is missing MIDI candidate controls: "
            + ", ".join(f"{side} {family}" for side, family in sorted(missing))
        )

    candidates.sort(key=lambda candidate: candidate["control"])
    return {
        "protocol": "silakka54-semantic-midi",
        "version": MIDI_PROTOCOL_VERSION,
        "channel": MIDI_CHANNEL + 1,
        "candidate_controls": candidates,
        "modifier_controls": [
            {"control": control, "family": family}
            for family, control in MIDI_MODIFIER_CONTROLS.items()
        ],
        "layer_message": "program-change",
        "layers": [
            {"program": index, "name": layer["name"]}
            for index, layer in enumerate(configured_layers)
        ],
    }


def render_midi_behavior(protocol):
    candidate_cases = "\n".join(
        f"        case {candidate['qmk']}: control = {candidate['control']}; candidate_index = {index}; break;"
        for index, candidate in enumerate(protocol["candidate_controls"])
    )
    modifier_entries = [
        (30, "MOD_MASK_CTRL"),
        (31, "MOD_MASK_ALT"),
        (32, "MOD_MASK_GUI"),
        (33, "MOD_MASK_SHIFT"),
    ]
    modifier_updates = "\n".join(
        f"    silakka54_update_modifier({index}, {mask}, {control}, mods);"
        for index, (control, mask) in enumerate(modifier_entries)
    )
    snapshot_candidates = "\n".join(
        f"        case {index}: silakka54_midi_cc({candidate['control']}, silakka54_candidate_state[{index}] ? 127 : 0); break;"
        for index, candidate in enumerate(protocol["candidate_controls"])
    )
    snapshot_modifiers = "\n".join(
        f"        case {index + len(protocol['candidate_controls'])}: silakka54_midi_cc({control}, (silakka54_last_mods & {mask}) ? 127 : 0); break;"
        for index, (control, mask) in enumerate(modifier_entries)
    )
    snapshot_layer_index = len(protocol["candidate_controls"]) + len(modifier_entries)
    snapshot_count = snapshot_layer_index + 1

    return f"""#ifdef MIDI_ENABLE
#    include \"qmk_midi.h\"

#    define SILAKKA54_MIDI_CHANNEL {MIDI_CHANNEL}
#    define SILAKKA54_MIDI_SNAPSHOT_COUNT {snapshot_count}

static bool silakka54_candidate_state[{len(protocol['candidate_controls'])}] = {{false}};
static uint8_t silakka54_last_mods = 0;
static uint8_t silakka54_snapshot_index = SILAKKA54_MIDI_SNAPSHOT_COUNT;
static uint32_t silakka54_snapshot_timer = 0;

static bool silakka54_is_midi_sender(void) {{
#    ifdef SPLIT_KEYBOARD
    return is_keyboard_master();
#    else
    return true;
#    endif
}}

static void silakka54_midi_cc(uint8_t control, uint8_t value) {{
    if (silakka54_is_midi_sender()) {{
        midi_send_cc(&midi_device, SILAKKA54_MIDI_CHANNEL, control, value);
    }}
}}

static void silakka54_midi_layer(uint8_t layer) {{
    if (silakka54_is_midi_sender()) {{
        midi_send_programchange(&midi_device, SILAKKA54_MIDI_CHANNEL, layer);
    }}
}}

bool pre_process_record_user(uint16_t keycode, keyrecord_t *record) {{
    uint8_t control = 0;
    uint8_t candidate_index = 0;
    switch (keycode) {{
{candidate_cases}
        default: return true;
    }}
    silakka54_candidate_state[candidate_index] = record->event.pressed;
    silakka54_midi_cc(control, record->event.pressed ? 127 : 0);
    return true;
}}

static void silakka54_update_modifier(uint8_t index, uint8_t mask, uint8_t control, uint8_t mods) {{
    bool previous = (silakka54_last_mods & mask) != 0;
    bool current = (mods & mask) != 0;
    if (previous != current) {{
        silakka54_midi_cc(control, current ? 127 : 0);
    }}
    (void)index;
}}

void housekeeping_task_user(void) {{
    uint8_t mods = get_mods();
{modifier_updates}
    silakka54_last_mods = mods;

    if (timer_elapsed32(silakka54_snapshot_timer) >= 1000) {{
        silakka54_snapshot_timer = timer_read32();
        silakka54_snapshot_index = 0;
    }}
    if (silakka54_snapshot_index >= SILAKKA54_MIDI_SNAPSHOT_COUNT) {{
        return;
    }}
    switch (silakka54_snapshot_index) {{
{snapshot_candidates}
{snapshot_modifiers}
        case {snapshot_layer_index}: silakka54_midi_layer(get_highest_layer(layer_state)); break;
    }}
    ++silakka54_snapshot_index;
}}
#endif"""


def configured_modifiers(tap_hold, name):
    modifiers = tap_hold.get(name, [])
    if not isinstance(modifiers, list) or not all(isinstance(item, str) for item in modifiers):
        raise ValueError(f"qmk.tap_hold.{name} must be an array of QMK modifier names")
    unknown = sorted(set(modifiers) - MOD_TAP_C_MODS)
    if unknown:
        raise ValueError(
            f"qmk.tap_hold.{name} contains unsupported modifiers: {', '.join(unknown)}"
        )
    if len(set(modifiers)) != len(modifiers):
        raise ValueError(f"qmk.tap_hold.{name} contains duplicate modifiers")
    return modifiers


def render_mod_tap_callback(name, modifiers):
    if not modifiers:
        return ""
    cases = "\n".join(f"        case {modifier}:" for modifier in modifiers)
    return f"""bool {name}(uint16_t keycode, keyrecord_t *record) {{
    (void)record;
    if (!IS_QK_MOD_TAP(keycode)) {{
        return false;
    }}
    switch (mod_config(QK_MOD_TAP_GET_MODS(keycode))) {{
{cases}
            return true;
        default:
            return false;
    }}
}}"""


def render_combos(combos, layers, layer_indices):
    if not isinstance(combos, list):
        raise ValueError("qmk.combos must be an array")
    if not combos:
        return ""

    active_keycodes = {
        qmk_keycode(key, layer_indices)
        for keys in layers.values()
        for key in keys
    }
    seen_names = set()
    arrays = []
    entries = []
    for index, combo in enumerate(combos):
        if not isinstance(combo, dict):
            raise ValueError(f"qmk.combos[{index}] must be an object")
        name = combo.get("name")
        keys = combo.get("keys")
        output = combo.get("output")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", name):
            raise ValueError(
                f"qmk.combos[{index}].name must be a lowercase C identifier"
            )
        if name in seen_names:
            raise ValueError(f"duplicate QMK combo name {name!r}")
        seen_names.add(name)
        if not isinstance(keys, list) or len(keys) < 2 or not all(
            isinstance(key, str) for key in keys
        ):
            raise ValueError(f"qmk.combos[{index}].keys must contain at least two keycodes")
        if not isinstance(output, str):
            raise ValueError(f"qmk.combos[{index}].output must be a keycode")

        rendered_keys = [qmk_keycode(key, layer_indices) for key in keys]
        rendered_output = qmk_keycode(output, layer_indices)
        for key in rendered_keys:
            via_keycode(key)
            if key not in active_keycodes:
                raise ValueError(f"QMK combo {name!r} uses keycode absent from the keymap: {key}")
        if len(set(rendered_keys)) != len(rendered_keys):
            raise ValueError(f"QMK combo {name!r} contains duplicate keycodes")
        via_keycode(rendered_output)

        symbol = f"silakka54_combo_{name}_keys"
        arrays.append(
            f"const uint16_t PROGMEM {symbol}[] = "
            f"{{{', '.join(rendered_keys)}, COMBO_END}};"
        )
        entries.append(f"    COMBO({symbol}, {rendered_output})")

    return "\n".join(arrays) + "\n\ncombo_t key_combos[] = {\n" + ",\n".join(entries) + "\n};"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--qmk-catalog", required=True, type=Path)
    parser.add_argument("--info-json", required=True, type=Path)
    parser.add_argument("--output-c", required=True, type=Path)
    parser.add_argument("--output-config-h", required=True, type=Path)
    parser.add_argument("--output-rules-mk", required=True, type=Path)
    parser.add_argument("--output-keymap-yaml", required=True, type=Path)
    parser.add_argument("--output-metadata", required=True, type=Path)
    parser.add_argument("--output-dynamic-keymap", required=True, type=Path)
    parser.add_argument("--output-dynamic-keymap-tsv", required=True, type=Path)
    parser.add_argument("--output-midi-protocol", required=True, type=Path)
    parser.add_argument("--firmware-abi-hash", required=True)
    parser.add_argument("--runtime-hash", required=True)
    parser.add_argument("--defaults-hash", required=True)
    args = parser.parse_args()

    global KEYCODES
    KEYCODES = json.loads(args.qmk_catalog.read_text())["keycodes"]

    data = json.loads(args.config.read_text())
    info = json.loads(args.info_json.read_text())
    layout = info["layouts"]["LAYOUT"]["layout"]
    key_count = len(layout)
    configured_layers = data["via"]["layers"]
    protocol = midi_protocol(configured_layers, layout)
    layers = {layer["name"]: layer["keys"] for layer in configured_layers}
    layer_names = list(layers)
    layer_indices = {name: index for index, name in enumerate(layer_names)}
    layer_ids = {layer["name"]: layer["id"] for layer in configured_layers}
    dynamic_layer_count = int(data["qmk"]["defines"]["DYNAMIC_KEYMAP_LAYER_COUNT"])
    if len(layers) > dynamic_layer_count:
        raise ValueError(
            f"configuration has {len(layers)} layers but DYNAMIC_KEYMAP_LAYER_COUNT is {dynamic_layer_count}"
        )
    for index in range(len(layers), dynamic_layer_count):
        layers[f"Unused {index}"] = ["KC_TRNS"] * key_count
        layer_indices[f"Unused {index}"] = index
        layer_ids[f"Unused {index}"] = str(index)

    keymap_hash = args.defaults_hash
    abi_bytes = ", ".join(str(byte) for byte in hash_bytes(args.firmware_abi_hash))
    runtime_bytes = ", ".join(str(byte) for byte in hash_bytes(args.runtime_hash))
    keymap_bytes = ", ".join(str(byte) for byte in hash_bytes(keymap_hash))

    for name, keys in layers.items():
        if len(keys) != key_count:
            raise ValueError(f"layer {name!r} has {len(keys)} keys, expected {key_count}")

    layer_enum = ",\n".join(
        f"    {layer_ids[name]} = {index}"
        for name, index in layer_indices.items()
        if index < len(configured_layers)
    )
    rendered_layers = ",\n\n".join(
        render_layer(layer_ids[name], keys, layer_indices) for name, keys in layers.items()
    )
    magic_bytes = ", ".join(str(byte) for byte in REPORT_MAGIC)
    sync_magic_bytes = ", ".join(str(byte) for byte in SYNC_MAGIC)

    tap_hold = data["qmk"].get("tap_hold", {})
    if not isinstance(tap_hold, dict):
        raise ValueError("qmk.tap_hold must be an object")
    hold_on_other_key_press_mods = configured_modifiers(
        tap_hold, "hold_on_other_key_press_mods"
    )
    speculative_hold_mods = configured_modifiers(tap_hold, "speculative_hold_mods")
    if hold_on_other_key_press_mods and not data["qmk"]["defines"].get(
        "HOLD_ON_OTHER_KEY_PRESS_PER_KEY"
    ):
        raise ValueError(
            "qmk.tap_hold.hold_on_other_key_press_mods requires "
            "HOLD_ON_OTHER_KEY_PRESS_PER_KEY"
        )
    if speculative_hold_mods and not data["qmk"]["defines"].get("SPECULATIVE_HOLD"):
        raise ValueError("qmk.tap_hold.speculative_hold_mods requires SPECULATIVE_HOLD")
    combos = data["qmk"].get("combos", [])
    if combos and data["qmk"]["rules"].get("COMBO_ENABLE") is not True:
        raise ValueError("qmk.combos requires COMBO_ENABLE")
    custom_behavior = "\n\n".join(
        item
        for item in [
            render_mod_tap_callback(
                "get_hold_on_other_key_press", hold_on_other_key_press_mods
            ),
            render_mod_tap_callback("get_speculative_hold", speculative_hold_mods),
            render_combos(combos, layers, layer_indices),
            render_midi_behavior(protocol),
        ]
        if item
    )

    args.output_config_h.write_text(render_config_h(data["qmk"]["defines"]))
    args.output_rules_mk.write_text(render_rules_mk(data["qmk"]["rules"]))
    args.output_keymap_yaml.write_text(render_keymap_yaml(configured_layers))
    args.output_midi_protocol.write_text(json.dumps(protocol, indent=2) + "\n")

    args.output_c.write_text(
        f"""// Generated from configuration.json. Do not edit this file by hand.
#include QMK_KEYBOARD_H
#include <string.h>

#ifdef RAW_ENABLE
#    include "raw_hid.h"
#endif
#ifdef VIA_ENABLE
#    include "via.h"
#endif

#ifndef RAW_EPSIZE
#    define SILAKKA54_RAW_EPSIZE 32
#else
#    define SILAKKA54_RAW_EPSIZE RAW_EPSIZE
#endif

#define SILAKKA54_SYNC_QUERY 0x54
#define SILAKKA54_SYNC_BOOTLOADER 0x42
#define SILAKKA54_SYNC_LAYER 0x4C
#define SILAKKA54_SYNC_VERSION 2
#define CURRENT_LAYER_HID_VERSION {CURRENT_LAYER_HID_VERSION}
#define CURRENT_LAYER_HID_QUERY {CURRENT_LAYER_HID_QUERY}
#define CURRENT_LAYER_HID_REPORT {CURRENT_LAYER_HID_REPORT}
#define SILAKKA54_KEY_COUNT {key_count}

enum silakka54_layers {{
{layer_enum}
}};

static const uint8_t silakka54_sync_magic[] = {{{sync_magic_bytes}}};
static const uint8_t silakka54_firmware_abi_hash[] = {{{abi_bytes}}};
static const uint8_t silakka54_runtime_hash[] = {{{runtime_bytes}}};
static const uint8_t silakka54_keymap_hash[] = {{{keymap_bytes}}};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {{
{rendered_layers}
}};

{custom_behavior}

const char chordal_hold_layout[MATRIX_ROWS][MATRIX_COLS] PROGMEM =
    LAYOUT(
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
                       'L', 'L', 'L',  'R', 'R', 'R'
    );

static uint8_t reported_layer = 0xFF;
static uint8_t current_layer_hid_sequence = 0;

static void silakka54_send_layer_report(uint8_t layer) {{
#ifdef RAW_ENABLE
#    ifdef SPLIT_KEYBOARD
    if (!is_keyboard_master()) {{
        return;
    }}
#    endif
    uint8_t report[SILAKKA54_RAW_EPSIZE] = {{0}};
    const uint8_t magic[] = {{{magic_bytes}}};
	    for (uint8_t i = 0; i < sizeof(magic); i++) {{
	        report[i] = magic[i];
	    }}
	    report[6] = CURRENT_LAYER_HID_VERSION;
	    report[7] = CURRENT_LAYER_HID_REPORT;
	    report[8] = layer;
	    report[9] = ++current_layer_hid_sequence;
	    raw_hid_send(report, SILAKKA54_RAW_EPSIZE);
#endif
}}

void keyboard_post_init_user(void) {{
    reported_layer = get_highest_layer(layer_state);
    silakka54_send_layer_report(reported_layer);
#ifdef MIDI_ENABLE
    silakka54_last_mods = get_mods();
    silakka54_snapshot_timer = timer_read32();
    silakka54_snapshot_index = 0;
#endif
}}

layer_state_t layer_state_set_user(layer_state_t state) {{
    uint8_t layer = get_highest_layer(state);
    if (layer != reported_layer) {{
        reported_layer = layer;
        silakka54_send_layer_report(layer);
#ifdef MIDI_ENABLE
        silakka54_midi_layer(layer);
#endif
    }}
    return state;
}}

bool via_command_kb(uint8_t *data, uint8_t length) {{
#if defined(RAW_ENABLE) && defined(VIA_ENABLE)
    const uint8_t layer_magic[] = {{{magic_bytes}}};
    if (length >= 10 && memcmp(data, layer_magic, sizeof(layer_magic)) == 0 && data[6] == CURRENT_LAYER_HID_VERSION && data[7] == CURRENT_LAYER_HID_QUERY) {{
        memset(data, 0, length);
        memcpy(data, layer_magic, sizeof(layer_magic));
        data[6] = CURRENT_LAYER_HID_VERSION;
        data[7] = CURRENT_LAYER_HID_REPORT;
        data[8] = reported_layer == 0xFF ? get_highest_layer(layer_state) : reported_layer;
        data[9] = ++current_layer_hid_sequence;
        raw_hid_send(data, length);
        return true;
    }}

    if (length < SILAKKA54_RAW_EPSIZE || data[0] != 0x02 || data[2] != SILAKKA54_SYNC_VERSION) {{
        return false;
    }}

    if (data[1] == SILAKKA54_SYNC_BOOTLOADER) {{
        memset(data, 0, length);
        data[0] = 0x02;
        data[1] = SILAKKA54_SYNC_BOOTLOADER;
        data[2] = SILAKKA54_SYNC_VERSION;
        memcpy(data + 3, silakka54_sync_magic, sizeof(silakka54_sync_magic));
        raw_hid_send(data, length);
        wait_ms(100);
        bootloader_jump();
        return true;
    }}

    if (data[1] == SILAKKA54_SYNC_LAYER) {{
        uint8_t target = data[3];
        bool valid = target < DYNAMIC_KEYMAP_LAYER_COUNT;
        if (valid) {{
            layer_move(target);
        }}
        memset(data, 0, length);
        data[0] = 0x02;
        data[1] = SILAKKA54_SYNC_LAYER;
        data[2] = SILAKKA54_SYNC_VERSION;
        data[3] = target;
        memcpy(data + 4, silakka54_sync_magic, sizeof(silakka54_sync_magic));
        data[11] = valid ? 0 : 1;
        data[12] = get_highest_layer(layer_state);
        raw_hid_send(data, length);
        return true;
    }}

    if (data[1] != SILAKKA54_SYNC_QUERY) {{
        return false;
    }}

    uint8_t page = data[3];
    memset(data, 0, length);
    data[0] = 0x02;
    data[1] = SILAKKA54_SYNC_QUERY;
    data[2] = SILAKKA54_SYNC_VERSION;
    data[3] = page;
    memcpy(data + 4, silakka54_sync_magic, sizeof(silakka54_sync_magic));
    if (page == 0) {{
        data[11] = DYNAMIC_KEYMAP_LAYER_COUNT;
        data[12] = DYNAMIC_KEYMAP_MACRO_COUNT;
        data[13] = MATRIX_ROWS;
        data[14] = MATRIX_COLS;
#    ifdef SPLIT_KEYBOARD
        data[15] = is_keyboard_left() ? 1 : 2;
#    endif
    }} else if (page == 1) {{
        memcpy(data + 11, silakka54_firmware_abi_hash, sizeof(silakka54_firmware_abi_hash));
        memcpy(data + 19, silakka54_runtime_hash, sizeof(silakka54_runtime_hash));
    }} else if (page == 2) {{
        memcpy(data + 11, silakka54_keymap_hash, sizeof(silakka54_keymap_hash));
    }}
    raw_hid_send(data, length);
    return true;
#else
    return false;
#endif
}}
"""
    )

    entries = dynamic_entries(layers, layer_indices, layout)
    args.output_dynamic_keymap.write_text(
        json.dumps(
            {
                "keyboard": "silakka54",
                "layers": [{"index": index, "name": name} for name, index in layer_indices.items()],
                "keymap_hash": keymap_hash,
                "firmware_abi_hash": args.firmware_abi_hash,
                "entries": entries,
            },
            indent=2,
        )
        + "\n"
    )
    args.output_dynamic_keymap_tsv.write_text(
        "layer\trow\tcol\tkeycode\tlayer_name\tlabel\tqmk\n"
        + "\n".join(
            f"{entry['layer']}\t{entry['row']}\t{entry['col']}\t{entry['keycode']}\t{entry['layer_name']}\t{entry['label']}\t{entry['qmk']}"
            for entry in entries
        )
        + "\n"
    )

    args.output_metadata.write_text(
        json.dumps(
	            {
	                "packet_magic": REPORT_MAGIC.decode(),
	                "packet_version": CURRENT_LAYER_HID_VERSION,
	                "packet_kind_query": CURRENT_LAYER_HID_QUERY,
	                "packet_kind_current_layer": CURRENT_LAYER_HID_REPORT,
	                "packet_spec": "current-layer-hid-v1",
	                "reported_layer": "get_highest_layer(layer_state)",
	                "sync_magic": SYNC_MAGIC.decode(),
                "sync_version": 2,
                "keymap_hash": keymap_hash,
                "firmware_abi_hash": args.firmware_abi_hash,
                "runtime_hash": args.runtime_hash,
                "layers": [{"index": index, "name": name} for name, index in layer_indices.items()],
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
