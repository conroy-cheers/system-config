# Current Layer HID Report v1

This document defines a tiny Raw HID convention for keyboard firmware that wants
to report the currently active keyboard layer to a host-side overlay or status
tool. It is intentionally independent of Silakka54, QMK, Vial, and any specific
keyboard layout.

## Transport

- Reports are sent over a vendor-defined Raw HID interface.
- QMK's default Raw HID usage page and usage ID (`0xFF60`, `0x61`) are
  recommended, but not required.
- Every report uses the endpoint's fixed report length and is padded with zeroes.
  QMK's default `RAW_EPSIZE` is 32 bytes.
- Hosts must accept reports with an optional leading HID report ID byte of `0x00`.

## Packet Format

All multi-byte fields are little-endian. Version 1 uses only single-byte fields.

| Offset | Size | Value | Meaning |
| --- | ---: | --- | --- |
| 0 | 6 | `KBLAYR` | ASCII magic |
| 6 | 1 | `0x01` | Protocol version |
| 7 | 1 | kind | `0x00` query, `0x01` current layer |
| 8 | 1 | layer | Highest active/effective layer, `0..31` |
| 9 | 1 | sequence | Wrapping counter, incremented for every transmitted current-layer report |
| 10..end | n | `0x00` | Reserved, must be zero when sent, ignored by receivers |

## Firmware Behavior

- Firmware should send a `current layer` report after keyboard initialization.
- Firmware must send a `current layer` report whenever the reported layer changes.
- Firmware should answer a host `query` packet with a `current layer` packet.
- Firmware should increment `sequence` for every transmitted `current layer`
  packet, including query responses. Hosts may ignore this field, but it gives
  polling clients a cheap way to detect fresh replies.
- The reported layer should normally be `get_highest_layer(layer_state)` in QMK.
  If a firmware wants the base/default layer to be visible when no momentary or
  toggle layer is active, it may instead report
  `get_highest_layer(layer_state | default_layer_state)`. Implementations should
  document which interpretation they use.
- Hosts should clamp unknown layer numbers to layer 0 when the selected layout
  does not define that layer.

## Minimal Plain-QMK Sketch

```c
#include QMK_KEYBOARD_H
#include "raw_hid.h"

#define CURRENT_LAYER_HID_VERSION 1
static uint8_t current_layer_sequence = 0;
static uint8_t reported_layer = 0xff;

static void send_current_layer(uint8_t layer) {
    uint8_t report[RAW_EPSIZE] = {0};
    memcpy(report, "KBLAYR", 6);
    report[6] = CURRENT_LAYER_HID_VERSION;
    report[7] = 0x01;
    report[8] = layer;
    report[9] = ++current_layer_sequence;
    raw_hid_send(report, RAW_EPSIZE);
}

void keyboard_post_init_user(void) {
    reported_layer = get_highest_layer(layer_state);
    send_current_layer(reported_layer);
}

layer_state_t layer_state_set_user(layer_state_t state) {
    uint8_t layer = get_highest_layer(state);
    if (layer != reported_layer) {
        reported_layer = layer;
        send_current_layer(layer);
    }
    return state;
}

void raw_hid_receive(uint8_t *data, uint8_t length) {
    if (length >= 10 && memcmp(data, "KBLAYR", 6) == 0 && data[6] == 1 && data[7] == 0) {
        send_current_layer(reported_layer);
    }
}
```

## Minimal Vial/VIA Sketch

VIA and Vial keyboards usually already have `VIA_ENABLE = yes`, so `via.c`
owns `raw_hid_receive()`. For commands VIA does not handle, it calls
`raw_hid_receive_kb()` and then sends the modified buffer back to the host.
In that path, do not call `raw_hid_send()` from `raw_hid_receive_kb()`.

```c
#include QMK_KEYBOARD_H
#include "raw_hid.h"

#define CURRENT_LAYER_HID_VERSION 1
static uint8_t current_layer_sequence = 0;
static uint8_t reported_layer = 0xff;

static void fill_current_layer(uint8_t *report, uint8_t length, uint8_t layer) {
    memset(report, 0, length);
    memcpy(report, "KBLAYR", 6);
    report[6] = CURRENT_LAYER_HID_VERSION;
    report[7] = 0x01;
    report[8] = layer;
    report[9] = ++current_layer_sequence;
}

static void send_current_layer(uint8_t layer) {
    uint8_t report[RAW_EPSIZE] = {0};
    fill_current_layer(report, sizeof(report), layer);
    raw_hid_send(report, sizeof(report));
}

void keyboard_post_init_user(void) {
    reported_layer = get_highest_layer(layer_state);
    send_current_layer(reported_layer);
}

layer_state_t layer_state_set_user(layer_state_t state) {
    uint8_t layer = get_highest_layer(state);
    if (layer != reported_layer) {
        reported_layer = layer;
        send_current_layer(layer);
    }
    return state;
}

void raw_hid_receive_kb(uint8_t *data, uint8_t length) {
    if (length >= 10 && memcmp(data, "KBLAYR", 6) == 0 && data[6] == 1 && data[7] == 0) {
        fill_current_layer(data, length, reported_layer);
    }
}
```
