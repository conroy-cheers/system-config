#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate-keymap.py")
SPEC = importlib.util.spec_from_file_location("generate_keymap", MODULE_PATH)
generate_keymap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generate_keymap)


def layer(name, keys):
    return {"name": name, "id": f"_{name.upper()}", "keys": keys}


class MidiProtocolTests(unittest.TestCase):
    def setUp(self):
        self.base_keys = [
            "LCTL_T(KC_R)",
            "LALT_T(KC_T)",
            "LGUI_T(KC_S)",
            "RGUI_T(KC_H)",
            "RALT_T(KC_A)",
            "RCTL_T(KC_E)",
        ]
        self.layout = [
            {"matrix": [2, 0]},
            {"matrix": [2, 1]},
            {"matrix": [2, 2]},
            {"matrix": [7, 2]},
            {"matrix": [7, 1]},
            {"matrix": [7, 0]},
        ]

    def test_protocol_is_derived_from_home_row_mods_and_layers(self):
        protocol = generate_keymap.midi_protocol(
            [layer("Base", self.base_keys), layer("Num", ["KC_TRNS"])], self.layout
        )
        self.assertEqual(protocol["version"], 1)
        self.assertEqual(protocol["channel"], 16)
        self.assertEqual(
            [candidate["control"] for candidate in protocol["candidate_controls"]],
            [20, 21, 22, 23, 24, 25],
        )
        self.assertEqual(
            [candidate["tap_keycode"] for candidate in protocol["candidate_controls"]],
            ["KC_R", "KC_T", "KC_S", "KC_H", "KC_A", "KC_E"],
        )
        self.assertEqual(
            protocol["layers"],
            [{"program": 0, "name": "Base"}, {"program": 1, "name": "Num"}],
        )

    def test_missing_candidate_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "right Ctrl"):
            generate_keymap.midi_protocol(
                [layer("Base", self.base_keys[:-1])], self.layout[:-1]
            )

    def test_duplicate_candidate_family_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicate left Ctrl"):
            generate_keymap.midi_protocol(
                [layer("Base", self.base_keys + ["LCTL_T(KC_X)"])],
                self.layout + [{"matrix": [2, 3]}],
            )


if __name__ == "__main__":
    unittest.main()
