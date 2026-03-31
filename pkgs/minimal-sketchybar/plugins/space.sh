#!/usr/bin/env sh

sid="$1"

space_json="$(yabai -m query --spaces 2>/dev/null | jq -cer --argjson sid "$sid" 'map(select(.index == $sid)) | first' 2>/dev/null || true)"

if [ -z "$space_json" ] || [ "$space_json" = "null" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

focused="$(printf '%s' "$space_json" | jq -r '."has-focus"')"
visible="$(printf '%s' "$space_json" | jq -r '."is-visible"')"

label_color="0xffe6e6e6"
background_color="0x00000000"

if [ "$focused" = "true" ]; then
  label_color="0xff111111"
  background_color="0xffe6e6e6"
elif [ "$visible" = "true" ]; then
  label_color="0xffe6e6e6"
  background_color="0x33ffffff"
else
  label_color="0x88e6e6e6"
fi

sketchybar --set "$NAME" \
  drawing=on \
  label="$sid" \
  label.color="$label_color" \
  background.color="$background_color"
