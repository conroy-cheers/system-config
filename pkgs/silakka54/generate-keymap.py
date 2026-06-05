#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

import yaml


KEY_COUNT = 54
REPORT_MAGIC = b"SL54LYR"
SYNC_MAGIC = b"SL54SYN"

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


KEYCODES = {
    "KC_NO": 0x0000,
    "KC_TRNS": 0x0001,
    "KC_A": 0x0004,
    "KC_B": 0x0005,
    "KC_C": 0x0006,
    "KC_D": 0x0007,
    "KC_E": 0x0008,
    "KC_F": 0x0009,
    "KC_G": 0x000A,
    "KC_H": 0x000B,
    "KC_I": 0x000C,
    "KC_J": 0x000D,
    "KC_K": 0x000E,
    "KC_L": 0x000F,
    "KC_M": 0x0010,
    "KC_N": 0x0011,
    "KC_O": 0x0012,
    "KC_P": 0x0013,
    "KC_Q": 0x0014,
    "KC_R": 0x0015,
    "KC_S": 0x0016,
    "KC_T": 0x0017,
    "KC_U": 0x0018,
    "KC_V": 0x0019,
    "KC_W": 0x001A,
    "KC_X": 0x001B,
    "KC_Y": 0x001C,
    "KC_Z": 0x001D,
    "KC_1": 0x001E,
    "KC_2": 0x001F,
    "KC_3": 0x0020,
    "KC_4": 0x0021,
    "KC_5": 0x0022,
    "KC_6": 0x0023,
    "KC_7": 0x0024,
    "KC_8": 0x0025,
    "KC_9": 0x0026,
    "KC_0": 0x0027,
    "KC_ENT": 0x0028,
    "KC_ESC": 0x0029,
    "KC_BSPC": 0x002A,
    "KC_TAB": 0x002B,
    "KC_SPC": 0x002C,
    "KC_MINS": 0x002D,
    "KC_EQL": 0x002E,
    "KC_LBRC": 0x002F,
    "KC_RBRC": 0x0030,
    "KC_BSLS": 0x0031,
    "KC_SCLN": 0x0033,
    "KC_QUOT": 0x0034,
    "KC_GRV": 0x0035,
    "KC_COMM": 0x0036,
    "KC_DOT": 0x0037,
    "KC_SLSH": 0x0038,
    "KC_CAPS": 0x0039,
    "KC_F1": 0x003A,
    "KC_F2": 0x003B,
    "KC_F3": 0x003C,
    "KC_F4": 0x003D,
    "KC_F5": 0x003E,
    "KC_F6": 0x003F,
    "KC_F7": 0x0040,
    "KC_F8": 0x0041,
    "KC_F9": 0x0042,
    "KC_F10": 0x0043,
    "KC_F11": 0x0044,
    "KC_F12": 0x0045,
    "KC_INS": 0x0049,
    "KC_HOME": 0x004A,
    "KC_PGUP": 0x004B,
    "KC_DEL": 0x004C,
    "KC_END": 0x004D,
    "KC_PGDN": 0x004E,
    "KC_RGHT": 0x004F,
    "KC_RIGHT": 0x004F,
    "KC_LEFT": 0x0050,
    "KC_DOWN": 0x0051,
    "KC_UP": 0x0052,
    "KC_EXEC": 0x0074,
    "KC_HELP": 0x0075,
    "KC_MENU": 0x0076,
    "KC_SLCT": 0x0077,
    "KC_STOP": 0x0078,
    "KC_AGIN": 0x0079,
    "KC_AGAIN": 0x0079,
    "KC_REDO": 0x0079,
    "KC_UNDO": 0x007A,
    "KC_CUT": 0x007B,
    "KC_COPY": 0x007C,
    "KC_PASTE": 0x007D,
    "KC_FIND": 0x007E,
    "KC_APP": 0x0065,
    "KC_MUTE": 0x00A8,
    "KC_VOLU": 0x00A9,
    "KC_VOLD": 0x00AA,
    "KC_MNXT": 0x00AB,
    "KC_MPRV": 0x00AC,
    "KC_MSTP": 0x00AD,
    "KC_MPLY": 0x00AE,
    "KC_LCTL": 0x00E0,
    "KC_LSFT": 0x00E1,
    "KC_LALT": 0x00E2,
    "KC_LGUI": 0x00E3,
    "KC_RCTL": 0x00E4,
    "KC_RSFT": 0x00E5,
    "KC_RALT": 0x00E6,
    "KC_RGUI": 0x00E7,
    "QK_BOOT": 0x7C00,
}

SHIFTED_KEYCODES = {
    "KC_EXLM": "KC_1",
    "KC_AT": "KC_2",
    "KC_HASH": "KC_3",
    "KC_DLR": "KC_4",
    "KC_PERC": "KC_5",
    "KC_CIRC": "KC_6",
    "KC_AMPR": "KC_7",
    "KC_ASTR": "KC_8",
    "KC_LPRN": "KC_9",
    "KC_RPRN": "KC_0",
    "KC_UNDS": "KC_MINS",
    "KC_PLUS": "KC_EQL",
    "KC_LCBR": "KC_LBRC",
    "KC_RCBR": "KC_RBRC",
    "KC_PIPE": "KC_BSLS",
    "KC_COLN": "KC_SCLN",
    "KC_DQUO": "KC_QUOT",
    "KC_LT": "KC_COMM",
    "KC_GT": "KC_DOT",
    "KC_QUES": "KC_SLSH",
    "KC_TILD": "KC_GRV",
}


def via_keycode(code):
    if match := re.fullmatch(r"MO\((_[A-Z0-9_]+)\)", code):
        raise ValueError(f"unresolved layer name in {code!r}")
    if match := re.fullmatch(r"MO\((\d+)\)", code):
        return 0x5220 | int(match.group(1))
    if code in SHIFTED_KEYCODES:
        return 0x0200 | KEYCODES[SHIFTED_KEYCODES[code]]
    if code in KEYCODES:
        return KEYCODES[code]
    raise ValueError(f"no VIA numeric keycode for {code!r}")


def hash_bytes(hash_hex, length=8):
    if not re.fullmatch(r"[0-9a-fA-F]{64}", hash_hex):
        raise ValueError(f"expected sha256 hex hash, got {hash_hex!r}")
    return bytes.fromhex(hash_hex[: length * 2])


def render_layer(name, keys, layer_indices):
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
    return f"    [{c_ident(name)}] = LAYOUT(\n" + ",\n".join(rendered_rows) + "\n    )"


def dynamic_entries(layers, layer_indices, layout):
    entries = []
    for layer_name, keys in layers.items():
        layer = layer_indices[layer_name]
        for index, (key, layout_entry) in enumerate(zip(keys, layout)):
            code = qmk_keycode(key, layer_indices)
            for name, layer_index in layer_indices.items():
                code = code.replace(f"MO({c_ident(name)})", f"MO({layer_index})")
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--keymap", required=True, type=Path)
    parser.add_argument("--keyboard-json", required=True, type=Path)
    parser.add_argument("--output-c", required=True, type=Path)
    parser.add_argument("--output-metadata", required=True, type=Path)
    parser.add_argument("--output-dynamic-keymap", required=True, type=Path)
    parser.add_argument("--output-dynamic-keymap-tsv", required=True, type=Path)
    parser.add_argument("--firmware-abi-hash", required=True)
    parser.add_argument("--keymap-hash")
    args = parser.parse_args()

    data = yaml.safe_load(args.keymap.read_text())
    keyboard = json.loads(args.keyboard_json.read_text())
    layers = data["layers"]
    layer_names = list(layers.keys())
    layer_indices = {name: index for index, name in enumerate(layer_names)}
    keymap_hash = args.keymap_hash or hashlib.sha256(args.keymap.read_bytes()).hexdigest()
    abi_bytes = ", ".join(str(byte) for byte in hash_bytes(args.firmware_abi_hash))
    keymap_bytes = ", ".join(str(byte) for byte in hash_bytes(keymap_hash))

    for name, keys in layers.items():
        if len(keys) != KEY_COUNT:
            raise ValueError(f"layer {name!r} has {len(keys)} keys, expected {KEY_COUNT}")

    layer_enum = ",\n".join(f"    {c_ident(name)} = {index}" for name, index in layer_indices.items())
    rendered_layers = ",\n\n".join(render_layer(name, keys, layer_indices) for name, keys in layers.items())
    magic_bytes = ", ".join(str(byte) for byte in REPORT_MAGIC)
    sync_magic_bytes = ", ".join(str(byte) for byte in SYNC_MAGIC)

    args.output_c.write_text(
        f"""// Generated from keymap.yaml. Do not edit this file by hand.
#include QMK_KEYBOARD_H
#include <string.h>

#ifdef RAW_ENABLE
#    include "raw_hid.h"
#endif

#ifndef RAW_EPSIZE
#    define SILAKKA54_RAW_EPSIZE 32
#else
#    define SILAKKA54_RAW_EPSIZE RAW_EPSIZE
#endif

#define SILAKKA54_SYNC_QUERY 0x54
#define SILAKKA54_SYNC_VERSION 1

enum silakka54_layers {{
{layer_enum}
}};

static const uint8_t silakka54_sync_magic[] = {{{sync_magic_bytes}}};
static const uint8_t silakka54_firmware_abi_hash[] = {{{abi_bytes}}};
static const uint8_t silakka54_keymap_hash[] = {{{keymap_bytes}}};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {{
{rendered_layers}
}};

const char chordal_hold_layout[MATRIX_ROWS][MATRIX_COLS] PROGMEM =
    LAYOUT(
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
        'L', 'L', 'L', 'L', 'L', 'L',  'R', 'R', 'R', 'R', 'R', 'R',
                       'L', 'L', 'L',  'R', 'R', 'R'
    );

static uint8_t reported_layer = 0xFF;

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
    report[7] = 1;
    report[8] = layer;
    raw_hid_send(report, SILAKKA54_RAW_EPSIZE);
#endif
}}

void keyboard_post_init_user(void) {{
    reported_layer = get_highest_layer(layer_state);
    silakka54_send_layer_report(reported_layer);
}}

layer_state_t layer_state_set_user(layer_state_t state) {{
    uint8_t layer = get_highest_layer(state);
    if (layer != reported_layer) {{
        reported_layer = layer;
        silakka54_send_layer_report(layer);
    }}
    return state;
}}

void raw_hid_receive_kb(uint8_t *data, uint8_t length) {{
#ifdef RAW_ENABLE
    if (length < SILAKKA54_RAW_EPSIZE || data[0] != 0x02 || data[1] != SILAKKA54_SYNC_QUERY || data[2] != SILAKKA54_SYNC_VERSION) {{
        return;
    }}

    memset(data, 0, length);
    data[0] = 0x02;
    data[1] = SILAKKA54_SYNC_QUERY;
    data[2] = SILAKKA54_SYNC_VERSION;
    memcpy(data + 3, silakka54_sync_magic, sizeof(silakka54_sync_magic));
    data[10] = SILAKKA54_SYNC_VERSION;
    memcpy(data + 11, silakka54_firmware_abi_hash, sizeof(silakka54_firmware_abi_hash));
    memcpy(data + 19, silakka54_keymap_hash, sizeof(silakka54_keymap_hash));
    data[27] = DYNAMIC_KEYMAP_LAYER_COUNT;
    data[28] = MATRIX_ROWS;
    data[29] = MATRIX_COLS;
#endif
}}
"""
    )

    layout = keyboard["layouts"]["LAYOUT"]["layout"]
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
                "packet_version": 1,
                "sync_magic": SYNC_MAGIC.decode(),
                "sync_version": 1,
                "keymap_hash": keymap_hash,
                "firmware_abi_hash": args.firmware_abi_hash,
                "layers": [{"index": index, "name": name} for name, index in layer_indices.items()],
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
