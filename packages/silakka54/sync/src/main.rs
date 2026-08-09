use hidapi::{HidApi, HidDevice};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::CString;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::thread;
use std::time::{Duration, Instant};

const VID: u16 = 0xfeed;
const PID: u16 = 0x1212;
const RAW_USAGE_PAGE: u16 = 0xff60;
const RAW_USAGE: u16 = 0x0061;
const MANIFEST_PATH: &str = "@manifest_path@";
const FIRMWARE_LEFT_PATH: &str = "@firmware_left_path@";
const FIRMWARE_RIGHT_PATH: &str = "@firmware_right_path@";
const CONFIGURATION_PATH: &str = "@configuration_path@";
const QMK_CATALOG_PATH: &str = "@qmk_catalog_path@";
const DYNAMIC_KEYMAP_TSV: &str = "@dynamic_keymap_tsv@";
const EXPECTED_ABI_HASH: &str = "@firmware_abi_hash@";
const EXPECTED_RUNTIME_HASH: &str = "@runtime_hash@";
const EXPECTED_KEYMAP_HASH: &str = "@keymap_hash@";
const REPORT_LEN: usize = 32;

const ID_GET_PROTOCOL_VERSION: u8 = 0x01;
const ID_GET_KEYBOARD_VALUE: u8 = 0x02;
const ID_SET_KEYBOARD_VALUE: u8 = 0x03;
const ID_DYNAMIC_KEYMAP_GET_KEYCODE: u8 = 0x04;
const ID_DYNAMIC_KEYMAP_SET_KEYCODE: u8 = 0x05;
const ID_DYNAMIC_KEYMAP_MACRO_GET_COUNT: u8 = 0x0c;
const ID_DYNAMIC_KEYMAP_MACRO_GET_BUFFER_SIZE: u8 = 0x0d;
const ID_DYNAMIC_KEYMAP_MACRO_GET_BUFFER: u8 = 0x0e;
const ID_DYNAMIC_KEYMAP_MACRO_SET_BUFFER: u8 = 0x0f;
const ID_LAYOUT_OPTIONS: u8 = 0x02;
const SILAKKA54_SYNC_QUERY: u8 = 0x54;
const SILAKKA54_SYNC_BOOTLOADER: u8 = 0x42;
const SILAKKA54_SYNC_VERSION: u8 = 2;
const SILAKKA54_SYNC_MAGIC: &[u8] = b"SL54SYN";

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
enum KeyboardHalf {
    Left,
    Right,
}

impl KeyboardHalf {
    fn label(self) -> &'static str {
        match self {
            Self::Left => "left",
            Self::Right => "right",
        }
    }

    fn firmware_path(self) -> &'static str {
        match self {
            Self::Left => FIRMWARE_LEFT_PATH,
            Self::Right => FIRMWARE_RIGHT_PATH,
        }
    }
}

#[derive(Clone, Debug)]
struct KeyEntry {
    layer: u8,
    row: u8,
    col: u8,
    keycode: u16,
    label: String,
    qmk: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct Configuration {
    schema_version: u32,
    via: ViaConfiguration,
    qmk: QmkConfiguration,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
struct ViaConfiguration {
    layers: Vec<ConfiguredLayer>,
    #[serde(default)]
    layout_options: u32,
    #[serde(default)]
    macros: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
struct ConfiguredLayer {
    id: String,
    name: String,
    keys: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
struct QmkConfiguration {
    defines: BTreeMap<String, Value>,
    rules: BTreeMap<String, bool>,
    #[serde(default)]
    tap_hold: TapHoldConfiguration,
    #[serde(default)]
    combos: Vec<ComboConfiguration>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
struct TapHoldConfiguration {
    #[serde(default)]
    hold_on_other_key_press_mods: Vec<String>,
    #[serde(default)]
    speculative_hold_mods: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
struct ComboConfiguration {
    name: String,
    keys: Vec<String>,
    output: String,
}

#[derive(Debug, Deserialize)]
struct QmkCatalog {
    qmk_revision: String,
    keycodes: BTreeMap<String, u16>,
    options: BTreeMap<String, Value>,
}

#[derive(Clone, Debug)]
struct DeviceDescriptor {
    path: CString,
    display_name: String,
}

impl DeviceDescriptor {
    fn id(&self) -> Vec<u8> {
        self.path.as_bytes().to_vec()
    }
}

#[derive(Debug, Serialize)]
struct FirmwareStatus {
    abi_hash_prefix: String,
    runtime_hash_prefix: String,
    keymap_hash_prefix: String,
    layer_count: u8,
    macro_count: u8,
    rows: u8,
    cols: u8,
    half: Option<KeyboardHalf>,
}

#[derive(Debug, Serialize)]
struct DeviceStatus {
    name: String,
    via_protocol: Option<u16>,
    firmware: Option<FirmwareStatus>,
    keymap_drift: Option<usize>,
    via_state_drift: Option<Vec<String>>,
    error: Option<String>,
}

trait HidTransport {
    fn write(&self, data: &[u8]) -> Result<usize, String>;
    fn read_timeout(&self, data: &mut [u8], timeout_ms: i32) -> Result<usize, String>;
}

impl HidTransport for HidDevice {
    fn write(&self, data: &[u8]) -> Result<usize, String> {
        HidDevice::write(self, data).map_err(|error| error.to_string())
    }

    fn read_timeout(&self, data: &mut [u8], timeout_ms: i32) -> Result<usize, String> {
        HidDevice::read_timeout(self, data, timeout_ms).map_err(|error| error.to_string())
    }
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_else(|| "status".to_string());
    let remaining: Vec<_> = args.collect();
    let result = match command.as_str() {
        "status" => parse_status_args(&remaining).and_then(status_command),
        "apply" | "sync-keymap" => {
            parse_config_arg(&remaining).and_then(sync_keymap_command_with_config)
        }
        "config" => config_command(&remaining),
        "flash" | "flash-firmware" => parse_flash_args(remaining.into_iter())
            .and_then(|(yes, half)| flash_firmware_command(yes, half)),
        "hotplug" => hotplug_command(),
        "watch" => watch_command(),
        "--help" | "-h" | "help" => {
            print_help();
            Ok(())
        }
        other => Err(format!("unknown command: {other}")),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("silakka54-sync: {error}");
            ExitCode::from(1)
        }
    }
}

fn print_help() {
    println!("Usage: silakka54-sync <command> [options]");
    println!("  status [--config FILE]       Show live, runtime, and recovery-default state");
    println!("  apply [--config FILE]        Apply and verify standard VIA keymap state");
    println!("  config validate [--config FILE]");
    println!("  config options [--search TERM] [--json]");
    println!("  config diff [--config FILE]");
    println!("  config snapshot-live [--config FILE] [--output FILE]");
    println!("  flash --left|--right [--yes]");
    println!("  hotplug | watch");
}

struct StatusArgs {
    config: PathBuf,
    json: bool,
    check: bool,
}

fn parse_status_args(args: &[String]) -> Result<StatusArgs, String> {
    let mut parsed = StatusArgs {
        config: PathBuf::from(CONFIGURATION_PATH),
        json: false,
        check: false,
    };
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--config" => {
                index += 1;
                parsed.config = PathBuf::from(args.get(index).ok_or("--config requires a path")?);
            }
            "--json" => parsed.json = true,
            "--check" => parsed.check = true,
            option => return Err(format!("unknown option: {option}")),
        }
        index += 1;
    }
    Ok(parsed)
}

fn parse_config_arg(args: &[String]) -> Result<PathBuf, String> {
    let mut path = PathBuf::from(CONFIGURATION_PATH);
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--config" => {
                index += 1;
                let value = args.get(index).ok_or("--config requires a path")?;
                path = PathBuf::from(value);
            }
            option => return Err(format!("unknown option: {option}")),
        }
        index += 1;
    }
    Ok(path)
}

fn config_command(args: &[String]) -> Result<(), String> {
    let (subcommand, rest) = args
        .split_first()
        .ok_or("config requires validate, options, or diff")?;
    match subcommand.as_str() {
        "validate" => {
            let path = parse_config_arg(rest)?;
            let config = load_configuration(&path)?;
            validate_configuration(&config, &load_catalog()?)?;
            configuration_entries(&path)?;
            println!("{} is valid", path.display());
            Ok(())
        }
        "options" => config_options_command(rest),
        "diff" => {
            let path = parse_config_arg(rest)?;
            let candidate = load_configuration(&path)?;
            validate_configuration(&candidate, &load_catalog()?)?;
            let packaged = load_configuration(Path::new(CONFIGURATION_PATH))?;
            if candidate.via == packaged.via {
                println!("Live VIA state: unchanged from packaged configuration");
            } else {
                println!("Live VIA state: changed; apply can update it without flashing");
            }
            if candidate.qmk == packaged.qmk {
                println!("QMK firmware settings: unchanged");
            } else {
                println!("QMK firmware settings: changed; rebuild and flash required");
            }
            Ok(())
        }
        "snapshot-live" => snapshot_live_command(rest),
        other => Err(format!("unknown config command: {other}")),
    }
}

fn config_options_command(args: &[String]) -> Result<(), String> {
    let mut search = None;
    let mut json = false;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--search" => {
                index += 1;
                search = Some(
                    args.get(index)
                        .ok_or("--search requires a value")?
                        .to_ascii_uppercase(),
                );
            }
            "--json" => json = true,
            option => return Err(format!("unknown config options option: {option}")),
        }
        index += 1;
    }
    let catalog = load_catalog()?;
    let selected: BTreeMap<_, _> = catalog
        .options
        .iter()
        .filter(|(name, _)| search.as_ref().is_none_or(|term| name.contains(term)))
        .map(|(name, metadata)| (name.clone(), metadata.clone()))
        .collect();
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&selected).map_err(|error| error.to_string())?
        );
    } else {
        println!("QMK {} ({} options)", catalog.qmk_revision, selected.len());
        for (name, metadata) in selected {
            let kind = metadata
                .get("kind")
                .and_then(Value::as_str)
                .unwrap_or("define");
            let value_type = metadata
                .get("type")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            println!("{name:<40} {kind:<7} {value_type}");
        }
    }
    Ok(())
}

fn snapshot_live_command(args: &[String]) -> Result<(), String> {
    let mut config_path = PathBuf::from(CONFIGURATION_PATH);
    let mut output_path = None;
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--config" => {
                index += 1;
                config_path = PathBuf::from(args.get(index).ok_or("--config requires a path")?);
            }
            "--output" => {
                index += 1;
                output_path = Some(PathBuf::from(
                    args.get(index).ok_or("--output requires a path")?,
                ));
            }
            option => return Err(format!("unknown snapshot-live option: {option}")),
        }
        index += 1;
    }

    let mut config = load_configuration(&config_path)?;
    let entries = configuration_entries(&config_path)?;
    let catalog = load_catalog()?;
    let devices = via_devices()?;
    let descriptor = match devices.as_slice() {
        [descriptor] => descriptor,
        [] => return Err("no connected VIA-capable Silakka54 device".to_string()),
        _ => {
            return Err(
                "multiple Silakka54 devices are connected; snapshot-live requires exactly one"
                    .to_string(),
            );
        }
    };
    let device = open_hid(descriptor)?;
    let firmware = firmware_status(&device)?;
    if firmware.abi_hash_prefix != hash_prefix(EXPECTED_ABI_HASH) {
        return Err(
            "connected firmware ABI is incompatible; flash before snapshotting".to_string(),
        );
    }

    let layer_ids: Vec<_> = config
        .via
        .layers
        .iter()
        .map(|layer| layer.id.clone())
        .collect();
    let mut live_layers = Vec::with_capacity(config.via.layers.len());
    for (layer_index, layer) in config.via.layers.iter().enumerate() {
        let mut keys = Vec::with_capacity(layer.keys.len());
        for entry in entries
            .iter()
            .filter(|entry| usize::from(entry.layer) == layer_index)
        {
            keys.push(describe_keycode(
                get_keycode(&device, entry)?,
                &layer_ids,
                &catalog.keycodes,
            )?);
        }
        if keys.len() != layer.keys.len() {
            return Err(format!(
                "live layer {} has an unexpected matrix shape",
                layer.name
            ));
        }
        live_layers.push(keys);
    }
    for (layer, keys) in config.via.layers.iter_mut().zip(live_layers) {
        layer.keys = keys;
    }
    config.via.layout_options = get_layout_options(&device)?;
    let macro_capacity = macro_capacity(&device)?;
    let macro_size = macro_buffer_size(&device)?;
    config.via.macros =
        decode_macro_buffer(&get_macro_buffer(&device, macro_size)?, macro_capacity)?;
    validate_configuration(&config, &catalog)?;

    let rendered = serde_json::to_string_pretty(&config).map_err(|error| error.to_string())? + "\n";
    if let Some(path) = output_path {
        let temporary = path.with_extension("json.tmp");
        fs::write(&temporary, rendered)
            .map_err(|error| format!("failed to write {}: {error}", temporary.display()))?;
        fs::rename(&temporary, &path)
            .map_err(|error| format!("failed to replace {}: {error}", path.display()))?;
        println!("Wrote live VIA state to {}", path.display());
    } else {
        print!("{rendered}");
    }
    Ok(())
}

fn decode_macro_buffer(buffer: &[u8], capacity: u8) -> Result<Vec<String>, String> {
    let mut macros: Vec<_> = buffer
        .split(|byte| *byte == 0)
        .take(usize::from(capacity))
        .map(|value| {
            std::str::from_utf8(value)
                .map(str::to_string)
                .map_err(|_| "live VIA macro buffer contains non-UTF-8 data".to_string())
        })
        .collect::<Result<_, _>>()?;
    while macros.last().is_some_and(String::is_empty) {
        macros.pop();
    }
    Ok(macros)
}

fn describe_keycode(
    keycode: u16,
    layer_ids: &[String],
    keycodes: &BTreeMap<String, u16>,
) -> Result<String, String> {
    if (0x5220..=0x522f).contains(&keycode) {
        let layer = usize::from(keycode - 0x5220);
        return layer_ids
            .get(layer)
            .map(|id| format!("MO({id})"))
            .ok_or_else(|| format!("live keycode references unknown layer {layer}"));
    }
    if keycode & 0xf000 == 0x4000 {
        let layer = usize::from((keycode >> 8) & 0x0f);
        let tap = preferred_keycode_name(keycode & 0xff, keycodes)?;
        let layer = layer_ids
            .get(layer)
            .ok_or_else(|| format!("live layer-tap references unknown layer {layer}"))?;
        return Ok(format!("LT({layer}, {tap})"));
    }
    if keycode & 0xe000 == 0x2000 {
        let mods = (keycode >> 8) & 0x1f;
        let tap = preferred_keycode_name(keycode & 0xff, keycodes)?;
        let simple = match mods {
            0x01 => Some("LCTL_T"),
            0x02 => Some("LSFT_T"),
            0x04 => Some("LALT_T"),
            0x08 => Some("LGUI_T"),
            0x11 => Some("RCTL_T"),
            0x12 => Some("RSFT_T"),
            0x14 => Some("RALT_T"),
            0x18 => Some("RGUI_T"),
            _ => None,
        };
        if let Some(function) = simple {
            return Ok(format!("{function}({tap})"));
        }
        let mut names = Vec::new();
        for (mask, left, right) in [
            (0x01, "MOD_LCTL", "MOD_RCTL"),
            (0x02, "MOD_LSFT", "MOD_RSFT"),
            (0x04, "MOD_LALT", "MOD_RALT"),
            (0x08, "MOD_LGUI", "MOD_RGUI"),
        ] {
            if mods & mask != 0 {
                names.push(if mods & 0x10 != 0 { right } else { left });
            }
        }
        return Ok(format!("MT({}, {tap})", names.join("|")));
    }
    preferred_keycode_name(keycode, keycodes)
}

fn preferred_keycode_name(
    keycode: u16,
    keycodes: &BTreeMap<String, u16>,
) -> Result<String, String> {
    keycodes
        .iter()
        .filter(|(_, value)| **value == keycode)
        .min_by_key(|(name, _)| {
            (
                !name.starts_with("KC_"),
                name.contains("RIGHT"),
                name.len(),
                name.as_str(),
            )
        })
        .map(|(name, _)| name.clone())
        .ok_or_else(|| format!("live VIA keycode 0x{keycode:04x} is absent from pinned QMK"))
}

fn load_configuration(path: &Path) -> Result<Configuration, String> {
    let contents = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    serde_json::from_str(&contents)
        .map_err(|error| format!("invalid configuration {}: {error}", path.display()))
}

fn load_catalog() -> Result<QmkCatalog, String> {
    let contents = fs::read_to_string(QMK_CATALOG_PATH)
        .map_err(|error| format!("failed to read QMK catalog {QMK_CATALOG_PATH}: {error}"))?;
    serde_json::from_str(&contents).map_err(|error| format!("invalid QMK catalog: {error}"))
}

fn configuration_define_u8(config: &Configuration, name: &str) -> Result<u8, String> {
    config
        .qmk
        .defines
        .get(name)
        .and_then(Value::as_u64)
        .and_then(|value| u8::try_from(value).ok())
        .ok_or_else(|| format!("qmk.defines.{name} must be an integer from 0 through 255"))
}

fn validate_configuration(config: &Configuration, catalog: &QmkCatalog) -> Result<(), String> {
    if config.schema_version != 1 {
        return Err(format!(
            "unsupported configuration schema {}, expected 1",
            config.schema_version
        ));
    }
    let layer_count = configuration_define_u8(config, "DYNAMIC_KEYMAP_LAYER_COUNT")?;
    let macro_count = configuration_define_u8(config, "DYNAMIC_KEYMAP_MACRO_COUNT")?;
    if config.via.layers.is_empty() || config.via.layers.len() > usize::from(layer_count) {
        return Err(format!(
            "via.layers must contain 1 through {layer_count} layers"
        ));
    }
    if config.via.macros.len() > usize::from(macro_count) {
        return Err(format!(
            "via.macros has {} entries but firmware capacity is {macro_count}",
            config.via.macros.len()
        ));
    }
    for (index, value) in config.via.macros.iter().enumerate() {
        if !value.is_ascii() || value.as_bytes().contains(&0) {
            return Err(format!(
                "via.macros[{index}] must be ASCII text without NUL bytes"
            ));
        }
    }
    let mut ids = BTreeSet::new();
    let mut names = BTreeSet::new();
    for layer in &config.via.layers {
        if layer.keys.len() != 54 {
            return Err(format!(
                "layer {} has {} keys, expected 54",
                layer.name,
                layer.keys.len()
            ));
        }
        if !ids.insert(layer.id.as_str()) {
            return Err(format!("duplicate layer id: {}", layer.id));
        }
        if !layer.id.starts_with('_')
            || !layer
                .id
                .chars()
                .all(|ch| ch == '_' || ch.is_ascii_uppercase() || ch.is_ascii_digit())
        {
            return Err(format!(
                "layer id {} must be an uppercase QMK identifier beginning with _",
                layer.id
            ));
        }
        if !names.insert(layer.name.as_str()) {
            return Err(format!("duplicate layer name: {}", layer.name));
        }
    }
    for (name, value) in &config.qmk.defines {
        let metadata = catalog.options.get(name).ok_or_else(|| {
            format!("QMK define {name} is absent from the pinned upstream catalog")
        })?;
        if metadata.get("kind").and_then(Value::as_str) != Some("define") {
            return Err(format!(
                "QMK option {name} belongs in qmk.rules, not qmk.defines"
            ));
        }
        if !(value.is_boolean()
            || value.is_string()
            || value.as_i64().is_some()
            || value.as_u64().is_some())
        {
            return Err(format!(
                "qmk.defines.{name} must be a boolean, integer, or string"
            ));
        }
    }
    for name in config.qmk.rules.keys() {
        let metadata = catalog
            .options
            .get(name)
            .ok_or_else(|| format!("QMK rule {name} is absent from the pinned upstream catalog"))?;
        if metadata.get("kind").and_then(Value::as_str) != Some("rule") {
            return Err(format!(
                "QMK option {name} belongs in qmk.defines, not qmk.rules"
            ));
        }
    }
    for required in ["VIA_ENABLE", "RAW_ENABLE"] {
        if config.qmk.rules.get(required) != Some(&true) {
            return Err(format!("qmk.rules.{required} must remain enabled"));
        }
    }
    let tapping = config
        .qmk
        .defines
        .get("TAPPING_TERM")
        .and_then(Value::as_u64);
    let quick = config
        .qmk
        .defines
        .get("QUICK_TAP_TERM")
        .and_then(Value::as_u64);
    if matches!((quick, tapping), (Some(quick), Some(tapping)) if quick > tapping) {
        return Err("QUICK_TAP_TERM cannot exceed TAPPING_TERM".to_string());
    }

    let supported_modifiers = [
        "MOD_LCTL", "MOD_LSFT", "MOD_LALT", "MOD_LGUI", "MOD_RCTL", "MOD_RSFT", "MOD_RALT",
        "MOD_RGUI",
    ];
    for (field, modifiers, required_define) in [
        (
            "hold_on_other_key_press_mods",
            &config.qmk.tap_hold.hold_on_other_key_press_mods,
            "HOLD_ON_OTHER_KEY_PRESS_PER_KEY",
        ),
        (
            "speculative_hold_mods",
            &config.qmk.tap_hold.speculative_hold_mods,
            "SPECULATIVE_HOLD",
        ),
    ] {
        let mut unique = BTreeSet::new();
        for modifier in modifiers {
            if !supported_modifiers.contains(&modifier.as_str()) {
                return Err(format!(
                    "qmk.tap_hold.{field} contains unsupported modifier {modifier}"
                ));
            }
            if !unique.insert(modifier) {
                return Err(format!(
                    "qmk.tap_hold.{field} contains duplicate modifier {modifier}"
                ));
            }
        }
        if !modifiers.is_empty()
            && config
                .qmk
                .defines
                .get(required_define)
                .and_then(Value::as_bool)
                != Some(true)
        {
            return Err(format!(
                "qmk.tap_hold.{field} requires qmk.defines.{required_define}=true"
            ));
        }
    }

    if !config.qmk.combos.is_empty() && config.qmk.rules.get("COMBO_ENABLE") != Some(&true) {
        return Err("qmk.combos requires qmk.rules.COMBO_ENABLE=true".to_string());
    }
    let layer_ids: BTreeMap<_, _> = config
        .via
        .layers
        .iter()
        .enumerate()
        .flat_map(|(index, layer)| {
            [
                (layer.id.as_str(), index as u8),
                (layer.name.as_str(), index as u8),
            ]
        })
        .collect();
    let active_keycodes: BTreeSet<_> = config
        .via
        .layers
        .iter()
        .flat_map(|layer| &layer.keys)
        .map(|key| resolve_keycode(key, &layer_ids, &catalog.keycodes))
        .collect::<Result<_, _>>()?;
    let mut combo_names = BTreeSet::new();
    for combo in &config.qmk.combos {
        let mut name_chars = combo.name.chars();
        let valid_name = name_chars.next().is_some_and(|ch| ch.is_ascii_lowercase())
            && name_chars.all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_');
        if !valid_name {
            return Err(format!(
                "qmk combo name {:?} must be a lowercase C identifier",
                combo.name
            ));
        }
        if !combo_names.insert(combo.name.as_str()) {
            return Err(format!("duplicate QMK combo name: {}", combo.name));
        }
        if combo.keys.len() < 2 {
            return Err(format!(
                "QMK combo {} must contain at least two keys",
                combo.name
            ));
        }
        let keys: BTreeSet<_> = combo
            .keys
            .iter()
            .map(|key| resolve_keycode(key, &layer_ids, &catalog.keycodes))
            .collect::<Result<_, _>>()?;
        if keys.len() != combo.keys.len() {
            return Err(format!(
                "QMK combo {} contains duplicate keycodes",
                combo.name
            ));
        }
        for key in keys {
            if !active_keycodes.contains(&key) {
                return Err(format!(
                    "QMK combo {} uses a keycode absent from the keymap: 0x{key:04x}",
                    combo.name
                ));
            }
        }
        resolve_keycode(&combo.output, &layer_ids, &catalog.keycodes)?;
    }
    Ok(())
}

fn configuration_entries(path: &Path) -> Result<Vec<KeyEntry>, String> {
    let config = load_configuration(path)?;
    let catalog = load_catalog()?;
    validate_configuration(&config, &catalog)?;
    let packaged = read_keymap_entries()?;
    let positions: Vec<_> = packaged
        .iter()
        .filter(|entry| entry.layer == 0)
        .map(|entry| (entry.row, entry.col))
        .collect();
    if positions.len() != 54 {
        return Err("packaged layout does not contain 54 matrix positions".to_string());
    }
    let capacity = configuration_define_u8(&config, "DYNAMIC_KEYMAP_LAYER_COUNT")?;
    let layer_ids: BTreeMap<_, _> = config
        .via
        .layers
        .iter()
        .enumerate()
        .flat_map(|(index, layer)| {
            [
                (layer.id.as_str(), index as u8),
                (layer.name.as_str(), index as u8),
            ]
        })
        .collect();
    let mut entries = Vec::with_capacity(usize::from(capacity) * 54);
    for layer_index in 0..capacity {
        let configured = config.via.layers.get(usize::from(layer_index));
        for (index, (row, col)) in positions.iter().copied().enumerate() {
            let qmk = configured
                .map(|layer| layer.keys[index].as_str())
                .unwrap_or("KC_TRNS");
            entries.push(KeyEntry {
                layer: layer_index,
                row,
                col,
                keycode: resolve_keycode(qmk, &layer_ids, &catalog.keycodes)?,
                label: qmk.to_string(),
                qmk: qmk.to_string(),
            });
        }
    }
    Ok(entries)
}

fn resolve_keycode(
    expression: &str,
    layer_ids: &BTreeMap<&str, u8>,
    keycodes: &BTreeMap<String, u16>,
) -> Result<u16, String> {
    if let Some(value) = keycodes.get(expression) {
        return Ok(*value);
    }
    // The configuration format intentionally accepts a layer's display name as
    // a concise momentary-layer key, matching generate-keymap.py.
    if let Some(layer) = layer_ids.get(expression) {
        return Ok(0x5220 | u16::from(*layer));
    }
    let (function, arguments) = expression
        .split_once('(')
        .and_then(|(function, rest)| rest.strip_suffix(')').map(|rest| (function, rest)))
        .ok_or_else(|| format!("unknown QMK keycode: {expression}"))?;
    let arguments: Vec<_> = arguments.split(',').map(str::trim).collect();
    let layer = |value: &str| {
        layer_ids
            .get(value)
            .copied()
            .or_else(|| value.parse::<u8>().ok())
            .ok_or_else(|| format!("unknown layer in {expression}: {value}"))
    };
    match (function, arguments.as_slice()) {
        ("MO", [target]) => Ok(0x5220 | u16::from(layer(target)?)),
        ("LT", [target, tap]) => {
            let tap = resolve_keycode(tap, layer_ids, keycodes)?;
            if tap > 0xff {
                return Err(format!("layer-tap tap key must be basic: {expression}"));
            }
            Ok(0x4000 | (u16::from(layer(target)?) << 8) | tap)
        }
        ("MT", [modifier, tap]) => mod_tap_keycode(modifier, tap, expression, layer_ids, keycodes),
        (macro_name, [tap]) if macro_name.ends_with("_T") => {
            let modifier = match macro_name {
                "LCTL_T" => "MOD_LCTL",
                "LSFT_T" => "MOD_LSFT",
                "LALT_T" => "MOD_LALT",
                "LGUI_T" => "MOD_LGUI",
                "RCTL_T" => "MOD_RCTL",
                "RSFT_T" => "MOD_RSFT",
                "RALT_T" => "MOD_RALT",
                "RGUI_T" => "MOD_RGUI",
                _ => return Err(format!("unsupported QMK keycode: {expression}")),
            };
            mod_tap_keycode(modifier, tap, expression, layer_ids, keycodes)
        }
        _ => Err(format!("unsupported QMK keycode: {expression}")),
    }
}

fn mod_tap_keycode(
    modifier: &str,
    tap: &str,
    expression: &str,
    layer_ids: &BTreeMap<&str, u8>,
    keycodes: &BTreeMap<String, u16>,
) -> Result<u16, String> {
    let mut mods = 0u16;
    for modifier in modifier.split('|').map(str::trim) {
        mods |= match modifier {
            "MOD_LCTL" => 0x01,
            "MOD_LSFT" => 0x02,
            "MOD_LALT" => 0x04,
            "MOD_LGUI" => 0x08,
            "MOD_RCTL" => 0x11,
            "MOD_RSFT" => 0x12,
            "MOD_RALT" => 0x14,
            "MOD_RGUI" => 0x18,
            _ => return Err(format!("unsupported modifier in {expression}: {modifier}")),
        };
    }
    let tap = resolve_keycode(tap, layer_ids, keycodes)?;
    if tap > 0xff {
        return Err(format!("mod-tap tap key must be basic: {expression}"));
    }
    Ok(0x2000 | ((mods & 0x1f) << 8) | tap)
}

fn parse_flash_args(
    args: impl Iterator<Item = String>,
) -> Result<(bool, Option<KeyboardHalf>), String> {
    let mut yes = false;
    let mut half = None;
    for arg in args {
        match arg.as_str() {
            "--yes" | "-y" => yes = true,
            "--left" => set_flash_half(&mut half, KeyboardHalf::Left)?,
            "--right" => set_flash_half(&mut half, KeyboardHalf::Right)?,
            _ => return Err(format!("unknown flash-firmware option: {arg}")),
        }
    }
    Ok((yes, half))
}

fn set_flash_half(selected: &mut Option<KeyboardHalf>, half: KeyboardHalf) -> Result<(), String> {
    if selected.is_some_and(|selected| selected != half) {
        return Err("choose only one of --left or --right".to_string());
    }
    *selected = Some(half);
    Ok(())
}

fn status_command(args: StatusArgs) -> Result<(), String> {
    let config = load_configuration(&args.config)?;
    let entries = configuration_entries(&args.config)?;
    let statuses = collect_statuses_for(&entries, &config.via)?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "configuration": &args.config,
                "expected": {
                    "firmware_abi_hash": EXPECTED_ABI_HASH,
                    "runtime_hash": EXPECTED_RUNTIME_HASH,
                    "factory_defaults_hash": EXPECTED_KEYMAP_HASH,
                },
                "devices": &statuses,
            }))
            .map_err(|error| error.to_string())?
        );
    } else if statuses.is_empty() {
        println!("Silakka54: no connected raw HID devices for {VID:04x}:{PID:04x}");
    } else {
        println!("Silakka54 manifest: {MANIFEST_PATH}");
        println!("Configuration: {}", args.config.display());
        println!("Expected firmware ABI: {EXPECTED_ABI_HASH}");
        println!("Expected runtime: {EXPECTED_RUNTIME_HASH}");
        println!("Expected factory defaults: {EXPECTED_KEYMAP_HASH}");
        for status in &statuses {
            print_device_status(status);
        }
    }
    if args.check {
        if statuses.is_empty() {
            return Err("no Silakka54 device is connected".to_string());
        }
        if statuses.iter().any(|status| {
            !firmware_is_current(status) || live_state_is_stale(status) || status.error.is_some()
        }) {
            return Err("one or more Silakka54 devices are stale or unavailable".to_string());
        }
    }
    Ok(())
}

fn hotplug_command() -> Result<(), String> {
    let statuses = collect_statuses()?;
    if statuses.is_empty() {
        return Ok(());
    }

    if statuses.iter().any(live_state_is_stale) {
        sync_keymap_command()?;
    }

    if statuses.iter().any(firmware_is_stale) {
        request_user_prompt()?;
    }

    Ok(())
}

fn watch_command() -> Result<(), String> {
    let mut previous = BTreeSet::new();
    loop {
        match via_devices() {
            Ok(devices) => {
                let current: BTreeSet<_> = devices.iter().map(DeviceDescriptor::id).collect();
                if should_reconcile(&previous, &current) {
                    thread::sleep(Duration::from_millis(500));
                    if let Err(error) = hotplug_command() {
                        eprintln!("silakka54-sync: hotplug reconciliation failed: {error}");
                    }
                }
                previous = current;
            }
            Err(error) => eprintln!("silakka54-sync: HID enumeration failed: {error}"),
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn should_reconcile(previous: &BTreeSet<Vec<u8>>, current: &BTreeSet<Vec<u8>>) -> bool {
    !current.is_empty() && current.iter().any(|id| !previous.contains(id))
}

fn sync_keymap_command() -> Result<(), String> {
    sync_keymap_command_with_config(PathBuf::from(CONFIGURATION_PATH))
}

fn sync_keymap_command_with_config(config_path: PathBuf) -> Result<(), String> {
    let candidate = load_configuration(&config_path)?;
    let entries = configuration_entries(&config_path)?;
    let devices = via_devices()?;
    if devices.is_empty() {
        println!("Silakka54: no connected VIA-capable HID devices for {VID:04x}:{PID:04x}");
        return Ok(());
    }

    let mut changed_total = 0usize;
    let mut failures = Vec::new();
    for descriptor in devices {
        let compatibility = open_hid(&descriptor)
            .and_then(|device| firmware_status(&device))
            .is_ok_and(|firmware| firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH));
        if !compatibility {
            failures.push(format!(
                "{}: firmware ABI is incompatible; flash before applying live state",
                descriptor.display_name
            ));
            continue;
        }
        match sync_keymap_for_device(&descriptor, &entries) {
            Ok(changed) => {
                changed_total += changed;
                if changed == 0 {
                    println!("{}: keymap already current", descriptor.display_name);
                } else {
                    println!(
                        "{}: wrote {changed} differing keycodes",
                        descriptor.display_name
                    );
                }
                match open_hid(&descriptor)
                    .and_then(|device| sync_via_state_for_device(&device, &candidate.via))
                {
                    Ok(extras) if !extras.is_empty() => {
                        println!(
                            "{}: updated {}",
                            descriptor.display_name,
                            extras.join(" and ")
                        );
                    }
                    Ok(_) => {}
                    Err(error) => failures.push(format!(
                        "{}: VIA state sync failed: {error}",
                        descriptor.display_name
                    )),
                }
            }
            Err(error) => failures.push(format!(
                "{}: keymap sync failed: {error}",
                descriptor.display_name
            )),
        }
    }

    if changed_total > 0 {
        println!("Silakka54 dynamic keymap synced ({changed_total} keycodes changed).");
    }
    if !failures.is_empty() {
        return Err(failures.join("\n"));
    }
    let packaged = load_configuration(Path::new(CONFIGURATION_PATH))?;
    if candidate.qmk != packaged.qmk {
        println!("QMK firmware settings differ from the packaged build; rebuild and flash are still required.");
    }
    Ok(())
}

fn flash_firmware_command(yes: bool, half: Option<KeyboardHalf>) -> Result<(), String> {
    let half = match half {
        Some(half) => half,
        None => match ask_keyboard_half()? {
            Some(half) => half,
            None => return Ok(()),
        },
    };

    let confirmation = format!(
        "Flash the USB-connected physical {} half with the packaged UF2? [y/N] ",
        half.label()
    );
    if !yes && !ask_yes_no(&confirmation)? {
        return Ok(());
    }

    let mounts_before = bootloader_mounts();
    if request_silakka54_bootloader_jump(half)? {
        match wait_for_new_bootloader_mount(&mounts_before, Duration::from_secs(30)) {
            Ok(mount) => return copy_firmware_and_verify(&mount, half),
            Err(error) => eprintln!("Silakka54 bootloader jump did not produce RPI-RP2: {error}"),
        }
    }

    let mount = wait_for_bootloader_mount(Duration::from_secs(120))?;
    copy_firmware_and_verify(&mount, half)
}

fn request_silakka54_bootloader_jump(half: KeyboardHalf) -> Result<bool, String> {
    let mut candidates = Vec::new();
    let mut identified_other_half = false;
    for descriptor in via_devices()? {
        let device = match open_hid(&descriptor) {
            Ok(device) => device,
            Err(error) => {
                eprintln!(
                    "{}: could not open HID device: {error}",
                    descriptor.display_name
                );
                continue;
            }
        };
        match firmware_status(&device).and_then(|status| {
            status
                .half
                .ok_or_else(|| "firmware did not report its physical half".to_string())
        }) {
            Ok(reported) if reported == half => candidates.push((descriptor, device)),
            Ok(_) => identified_other_half = true,
            Err(error) => eprintln!("{}: {error}", descriptor.display_name),
        }
    }
    if candidates.len() > 1 {
        return Err(format!(
            "multiple connected devices report as the {} half; disconnect all but one",
            half.label()
        ));
    }
    let Some((descriptor, device)) = candidates.pop() else {
        if identified_other_half {
            return Err(format!(
                "the connected keyboard reports the opposite physical half; refusing {} firmware",
                half.label()
            ));
        }
        return Ok(false);
    };
    silakka54_bootloader_jump(&device)?;
    eprintln!(
        "{}: requested Silakka54 bootloader jump for the {} half",
        descriptor.display_name,
        half.label()
    );
    Ok(true)
}

fn copy_firmware_and_verify(mount: &Path, half: KeyboardHalf) -> Result<(), String> {
    let firmware_path = half.firmware_path();
    let target = mount.join(
        Path::new(firmware_path)
            .file_name()
            .ok_or_else(|| "firmware path has no file name".to_string())?,
    );
    fs::copy(firmware_path, &target)
        .map_err(|error| format!("failed to copy UF2 to {}: {error}", target.display()))?;
    sync_firmware_copy(&target)?;
    println!(
        "Copied {}-half firmware UF2 to {}",
        half.label(),
        target.display()
    );

    let deadline = Instant::now() + Duration::from_secs(60);
    while Instant::now() < deadline {
        thread::sleep(Duration::from_secs(1));
        match collect_statuses() {
            Ok(statuses)
                if statuses.iter().any(|status| {
                    firmware_is_current(status)
                        && status.firmware.as_ref().and_then(|firmware| firmware.half) == Some(half)
                }) =>
            {
                println!(
                    "Silakka54 {}-half firmware verified after reconnect.",
                    half.label()
                );
                return Ok(());
            }
            Ok(_) => {}
            Err(error) => eprintln!("Waiting for Silakka54 to reconnect: {error}"),
        }
    }

    Err("firmware was copied, but the keyboard did not reconnect with the expected ABI".to_string())
}

fn sync_firmware_copy(target: &Path) -> Result<(), String> {
    match File::open(target).and_then(|file| file.sync_all()) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(format!("failed to flush {}: {error}", target.display())),
    }

    let status = Command::new("sync")
        .status()
        .map_err(|error| format!("failed to flush firmware volume: {error}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("sync exited with {status}"))
    }
}

fn collect_statuses() -> Result<Vec<DeviceStatus>, String> {
    let config = load_configuration(Path::new(CONFIGURATION_PATH))?;
    let entries = configuration_entries(Path::new(CONFIGURATION_PATH))?;
    collect_statuses_for(&entries, &config.via)
}

fn collect_statuses_for(
    entries: &[KeyEntry],
    desired: &ViaConfiguration,
) -> Result<Vec<DeviceStatus>, String> {
    raw_hid_devices()?
        .iter()
        .map(|descriptor| Ok(device_status(descriptor, entries, desired)))
        .collect()
}

fn device_status(
    descriptor: &DeviceDescriptor,
    entries: &[KeyEntry],
    desired: &ViaConfiguration,
) -> DeviceStatus {
    let mut status = DeviceStatus {
        name: descriptor.display_name.clone(),
        via_protocol: None,
        firmware: None,
        keymap_drift: None,
        via_state_drift: None,
        error: None,
    };

    let device = match open_hid(descriptor) {
        Ok(device) => device,
        Err(error) => {
            status.error = Some(error);
            return status;
        }
    };

    status.via_protocol = via_protocol(&device).ok();
    if status.via_protocol.is_some() {
        status.firmware = firmware_status(&device).ok();
    }

    if status
        .firmware
        .as_ref()
        .is_some_and(|firmware| firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH))
    {
        status.keymap_drift = keymap_drift_for_device(&device, entries).ok();
        status.via_state_drift = via_state_drift_for_device(&device, desired).ok();
    }

    status
}

fn print_device_status(status: &DeviceStatus) {
    println!("Device: {}", status.name);
    if let Some(error) = &status.error {
        println!("  error: {error}");
        return;
    }
    match status.via_protocol {
        Some(version) => println!("  VIA protocol: 0x{version:04x}"),
        None => println!("  VIA protocol: unavailable (non-VIA HID interface)"),
    }
    match &status.firmware {
        Some(firmware) => {
            let abi_state = if firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH) {
                "current"
            } else {
                "stale"
            };
            println!("  firmware ABI: {} ({abi_state})", firmware.abi_hash_prefix);
            let runtime_state =
                if firmware.runtime_hash_prefix == hash_prefix(EXPECTED_RUNTIME_HASH) {
                    "current"
                } else {
                    "flash required"
                };
            let defaults_state = if firmware.keymap_hash_prefix == hash_prefix(EXPECTED_KEYMAP_HASH)
            {
                "current"
            } else {
                "optional reflash"
            };
            println!(
                "  runtime firmware: {} ({runtime_state})",
                firmware.runtime_hash_prefix
            );
            println!(
                "  factory defaults: {} ({defaults_state})",
                firmware.keymap_hash_prefix
            );
            println!(
                "  dynamic storage: {} layers, {} macros, {} rows, {} cols",
                firmware.layer_count, firmware.macro_count, firmware.rows, firmware.cols
            );
            if let Some(half) = firmware.half {
                println!("  physical half: {}", half.label());
            }
        }
        None if status.via_protocol.is_some() => {
            println!("  firmware ABI: unavailable; full flash required")
        }
        None => println!("  firmware ABI: not checked"),
    }
    match status.keymap_drift {
        Some(0) => println!("  dynamic keymap: current"),
        Some(count) => println!("  dynamic keymap: stale ({count} keycodes differ)"),
        None => println!("  dynamic keymap: not checked"),
    }
    match &status.via_state_drift {
        Some(drift) if drift.is_empty() => println!("  layout options/macros: current"),
        Some(drift) => println!("  layout options/macros: stale ({})", drift.join(", ")),
        None => println!("  layout options/macros: not checked"),
    }
}

fn live_state_is_stale(status: &DeviceStatus) -> bool {
    firmware_is_compatible(status)
        && (status.keymap_drift.unwrap_or(0) > 0
            || status
                .via_state_drift
                .as_ref()
                .is_some_and(|drift| !drift.is_empty()))
}

fn firmware_is_compatible(status: &DeviceStatus) -> bool {
    status
        .firmware
        .as_ref()
        .is_some_and(|firmware| firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH))
}

fn firmware_is_current(status: &DeviceStatus) -> bool {
    status.firmware.as_ref().is_some_and(|firmware| {
        firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH)
            && firmware.runtime_hash_prefix == hash_prefix(EXPECTED_RUNTIME_HASH)
    })
}

fn firmware_is_stale(status: &DeviceStatus) -> bool {
    status.error.is_none() && status.via_protocol.is_some() && !firmware_is_current(status)
}

fn raw_hid_devices() -> Result<Vec<DeviceDescriptor>, String> {
    let api = HidApi::new().map_err(|error| format!("failed to initialize HIDAPI: {error}"))?;
    let matching: Vec<_> = api
        .device_list()
        .filter(|device| device.vendor_id() == VID && device.product_id() == PID)
        .collect();
    let has_usage_match = matching
        .iter()
        .any(|device| device.usage_page() == RAW_USAGE_PAGE && device.usage() == RAW_USAGE);

    let mut devices: Vec<_> = matching
        .into_iter()
        .filter(|device| {
            !has_usage_match
                || (device.usage_page() == RAW_USAGE_PAGE && device.usage() == RAW_USAGE)
        })
        .map(|device| {
            let product = device.product_string().unwrap_or("Silakka54");
            DeviceDescriptor {
                path: device.path().to_owned(),
                display_name: format!(
                    "{} (interface {}, {})",
                    product,
                    device.interface_number(),
                    device.path().to_string_lossy()
                ),
            }
        })
        .collect();
    devices.sort_by(|left, right| left.path.as_bytes().cmp(right.path.as_bytes()));
    Ok(devices)
}

fn via_devices() -> Result<Vec<DeviceDescriptor>, String> {
    Ok(raw_hid_devices()?
        .into_iter()
        .filter(|descriptor| {
            open_hid(descriptor)
                .and_then(|device| via_protocol(&device))
                .is_ok()
        })
        .collect())
}

fn open_hid(descriptor: &DeviceDescriptor) -> Result<HidDevice, String> {
    HidApi::new()
        .map_err(|error| format!("failed to initialize HIDAPI: {error}"))?
        .open_path(&descriptor.path)
        .map_err(|error| error.to_string())
}

fn via_protocol(device: &dyn HidTransport) -> Result<u16, String> {
    let response = raw_transaction(
        device,
        command_report(ID_GET_PROTOCOL_VERSION),
        ID_GET_PROTOCOL_VERSION,
        Duration::from_secs(1),
    )?;
    Ok(u16::from_be_bytes([response[1], response[2]]))
}

fn firmware_status(device: &dyn HidTransport) -> Result<FirmwareStatus, String> {
    let capabilities = firmware_status_page(device, 0)?;
    let hashes = firmware_status_page(device, 1)?;
    let defaults = firmware_status_page(device, 2)?;
    Ok(FirmwareStatus {
        abi_hash_prefix: bytes_to_hex(&hashes[11..19]),
        runtime_hash_prefix: bytes_to_hex(&hashes[19..27]),
        keymap_hash_prefix: bytes_to_hex(&defaults[11..19]),
        layer_count: capabilities[11],
        macro_count: capabilities[12],
        rows: capabilities[13],
        cols: capabilities[14],
        half: match capabilities[15] {
            1 => Some(KeyboardHalf::Left),
            2 => Some(KeyboardHalf::Right),
            _ => None,
        },
    })
}

fn firmware_status_page(device: &dyn HidTransport, page: u8) -> Result<[u8; REPORT_LEN], String> {
    let mut report = command_report(ID_GET_KEYBOARD_VALUE);
    report[1] = SILAKKA54_SYNC_QUERY;
    report[2] = SILAKKA54_SYNC_VERSION;
    report[3] = page;
    let response = raw_transaction(
        device,
        report,
        ID_GET_KEYBOARD_VALUE,
        Duration::from_secs(1),
    )?;
    if response[1] != SILAKKA54_SYNC_QUERY
        || response[2] != SILAKKA54_SYNC_VERSION
        || response[3] != page
    {
        return Err("firmware did not answer Silakka54 sync query".to_string());
    }
    if &response[4..11] != SILAKKA54_SYNC_MAGIC {
        return Err("firmware sync magic mismatch".to_string());
    }
    Ok(response)
}

fn silakka54_bootloader_jump(device: &dyn HidTransport) -> Result<(), String> {
    let mut report = command_report(ID_GET_KEYBOARD_VALUE);
    report[1] = SILAKKA54_SYNC_BOOTLOADER;
    report[2] = SILAKKA54_SYNC_VERSION;
    let response = raw_transaction(
        device,
        report,
        ID_GET_KEYBOARD_VALUE,
        Duration::from_millis(1000),
    )?;
    if response[1] != SILAKKA54_SYNC_BOOTLOADER || response[2] != SILAKKA54_SYNC_VERSION {
        return Err("firmware did not acknowledge Silakka54 bootloader jump".to_string());
    }
    if &response[3..10] != SILAKKA54_SYNC_MAGIC {
        return Err("firmware sync magic mismatch".to_string());
    }
    Ok(())
}

fn get_layout_options(device: &dyn HidTransport) -> Result<u32, String> {
    let mut report = command_report(ID_GET_KEYBOARD_VALUE);
    report[1] = ID_LAYOUT_OPTIONS;
    let response = raw_transaction(
        device,
        report,
        ID_GET_KEYBOARD_VALUE,
        Duration::from_secs(1),
    )?;
    Ok(u32::from_be_bytes([
        response[2],
        response[3],
        response[4],
        response[5],
    ]))
}

fn set_layout_options(device: &dyn HidTransport, value: u32) -> Result<(), String> {
    let mut report = command_report(ID_SET_KEYBOARD_VALUE);
    report[1] = ID_LAYOUT_OPTIONS;
    report[2..6].copy_from_slice(&value.to_be_bytes());
    raw_transaction(
        device,
        report,
        ID_SET_KEYBOARD_VALUE,
        Duration::from_secs(1),
    )
    .map(|_| ())
}

fn macro_capacity(device: &dyn HidTransport) -> Result<u8, String> {
    let response = raw_transaction(
        device,
        command_report(ID_DYNAMIC_KEYMAP_MACRO_GET_COUNT),
        ID_DYNAMIC_KEYMAP_MACRO_GET_COUNT,
        Duration::from_secs(1),
    )?;
    Ok(response[1])
}

fn macro_buffer_size(device: &dyn HidTransport) -> Result<usize, String> {
    let response = raw_transaction(
        device,
        command_report(ID_DYNAMIC_KEYMAP_MACRO_GET_BUFFER_SIZE),
        ID_DYNAMIC_KEYMAP_MACRO_GET_BUFFER_SIZE,
        Duration::from_secs(1),
    )?;
    Ok(usize::from(u16::from_be_bytes([response[1], response[2]])))
}

fn get_macro_buffer(device: &dyn HidTransport, size: usize) -> Result<Vec<u8>, String> {
    let mut buffer = vec![0; size];
    for offset in (0..size).step_by(28) {
        let chunk_size = (size - offset).min(28);
        let offset = u16::try_from(offset).map_err(|_| "VIA macro buffer exceeds 65535 bytes")?;
        let mut report = command_report(ID_DYNAMIC_KEYMAP_MACRO_GET_BUFFER);
        report[1..3].copy_from_slice(&offset.to_be_bytes());
        report[3] = chunk_size as u8;
        let response = raw_transaction(
            device,
            report,
            ID_DYNAMIC_KEYMAP_MACRO_GET_BUFFER,
            Duration::from_secs(1),
        )?;
        let start = usize::from(offset);
        buffer[start..start + chunk_size].copy_from_slice(&response[4..4 + chunk_size]);
    }
    Ok(buffer)
}

fn set_macro_buffer(device: &dyn HidTransport, buffer: &[u8]) -> Result<(), String> {
    for offset in (0..buffer.len()).step_by(28) {
        let chunk_size = (buffer.len() - offset).min(28);
        let encoded_offset =
            u16::try_from(offset).map_err(|_| "VIA macro buffer exceeds 65535 bytes")?;
        let mut report = command_report(ID_DYNAMIC_KEYMAP_MACRO_SET_BUFFER);
        report[1..3].copy_from_slice(&encoded_offset.to_be_bytes());
        report[3] = chunk_size as u8;
        report[4..4 + chunk_size].copy_from_slice(&buffer[offset..offset + chunk_size]);
        raw_transaction(
            device,
            report,
            ID_DYNAMIC_KEYMAP_MACRO_SET_BUFFER,
            Duration::from_secs(1),
        )?;
    }
    Ok(())
}

fn desired_macro_buffer(
    macros: &[String],
    capacity: u8,
    buffer_size: usize,
) -> Result<Vec<u8>, String> {
    if macros.len() > usize::from(capacity) {
        return Err(format!(
            "configuration has {} macros but connected firmware supports {capacity}",
            macros.len()
        ));
    }
    let mut output = vec![0; buffer_size];
    let mut cursor = 0;
    for (index, value) in macros.iter().enumerate() {
        let required = value.len() + 1;
        if cursor + required > output.len() {
            return Err(format!(
                "via.macros[{index}] exceeds the connected firmware's {buffer_size}-byte macro buffer"
            ));
        }
        output[cursor..cursor + value.len()].copy_from_slice(value.as_bytes());
        cursor += required;
    }
    Ok(output)
}

fn via_state_drift_for_device(
    device: &dyn HidTransport,
    desired: &ViaConfiguration,
) -> Result<Vec<String>, String> {
    let mut drift = Vec::new();
    let layout = get_layout_options(device)?;
    if layout != desired.layout_options {
        drift.push(format!(
            "layout options 0x{layout:08x} != 0x{:08x}",
            desired.layout_options
        ));
    }
    let capacity = macro_capacity(device)?;
    let size = macro_buffer_size(device)?;
    let expected = desired_macro_buffer(&desired.macros, capacity, size)?;
    if get_macro_buffer(device, size)? != expected {
        drift.push("macro buffer differs".to_string());
    }
    Ok(drift)
}

fn sync_via_state_for_device(
    device: &dyn HidTransport,
    desired: &ViaConfiguration,
) -> Result<Vec<String>, String> {
    let mut changed = Vec::new();
    if get_layout_options(device)? != desired.layout_options {
        set_layout_options(device, desired.layout_options)?;
        if get_layout_options(device)? != desired.layout_options {
            return Err("layout options did not verify after write".to_string());
        }
        changed.push("layout options".to_string());
    }

    let capacity = macro_capacity(device)?;
    let size = macro_buffer_size(device)?;
    let expected = desired_macro_buffer(&desired.macros, capacity, size)?;
    if get_macro_buffer(device, size)? != expected {
        set_macro_buffer(device, &expected)?;
        if get_macro_buffer(device, size)? != expected {
            return Err("macro buffer did not verify after write".to_string());
        }
        changed.push("macros".to_string());
    }
    Ok(changed)
}

fn get_keycode(device: &dyn HidTransport, entry: &KeyEntry) -> Result<u16, String> {
    let mut report = command_report(ID_DYNAMIC_KEYMAP_GET_KEYCODE);
    report[1] = entry.layer;
    report[2] = entry.row;
    report[3] = entry.col;
    let response = raw_transaction(
        device,
        report,
        ID_DYNAMIC_KEYMAP_GET_KEYCODE,
        Duration::from_secs(1),
    )?;
    Ok(u16::from_be_bytes([response[4], response[5]]))
}

fn set_keycode(device: &dyn HidTransport, entry: &KeyEntry) -> Result<(), String> {
    let mut report = command_report(ID_DYNAMIC_KEYMAP_SET_KEYCODE);
    report[1] = entry.layer;
    report[2] = entry.row;
    report[3] = entry.col;
    report[4] = (entry.keycode >> 8) as u8;
    report[5] = (entry.keycode & 0xff) as u8;
    raw_transaction(
        device,
        report,
        ID_DYNAMIC_KEYMAP_SET_KEYCODE,
        Duration::from_secs(1),
    )
    .map(|_| ())
}

fn command_report(command_id: u8) -> [u8; REPORT_LEN] {
    let mut report = [0u8; REPORT_LEN];
    report[0] = command_id;
    report
}

fn raw_transaction(
    device: &dyn HidTransport,
    report: [u8; REPORT_LEN],
    expected_command: u8,
    timeout: Duration,
) -> Result<[u8; REPORT_LEN], String> {
    let mut output = [0u8; REPORT_LEN + 1];
    output[1..].copy_from_slice(&report);
    device
        .write(&output)
        .map_err(|error| format!("HID write failed: {error}"))?;

    let deadline = Instant::now() + timeout;
    let mut buffer = [0u8; REPORT_LEN + 1];
    while Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let timeout_ms = remaining.min(Duration::from_millis(100)).as_millis().max(1) as i32;
        let len = device
            .read_timeout(&mut buffer, timeout_ms)
            .map_err(|error| format!("HID read failed: {error}"))?;
        if len == 0 {
            continue;
        }
        let normalized = normalize_report(&buffer[..len]);
        if normalized.len() >= REPORT_LEN && normalized[0] == expected_command {
            let mut response = [0u8; REPORT_LEN];
            response.copy_from_slice(&normalized[..REPORT_LEN]);
            return Ok(response);
        }
    }

    Err(format!(
        "timed out waiting for HID response 0x{expected_command:02x}"
    ))
}

fn normalize_report(buffer: &[u8]) -> &[u8] {
    if buffer.len() > REPORT_LEN && buffer.first() == Some(&0) {
        &buffer[1..]
    } else {
        buffer
    }
}

fn read_keymap_entries() -> Result<Vec<KeyEntry>, String> {
    let contents = fs::read_to_string(DYNAMIC_KEYMAP_TSV)
        .map_err(|error| format!("failed to read {DYNAMIC_KEYMAP_TSV}: {error}"))?;
    let mut entries = Vec::new();
    let mut seen = BTreeMap::new();
    for (line_number, line) in contents.lines().enumerate() {
        if line_number == 0 || line.trim().is_empty() {
            continue;
        }
        let fields: Vec<_> = line.split('\t').collect();
        if fields.len() != 7 {
            return Err(format!(
                "{DYNAMIC_KEYMAP_TSV}:{}: expected 7 tab-separated fields",
                line_number + 1
            ));
        }
        let entry = KeyEntry {
            layer: parse_u8(fields[0], line_number + 1)?,
            row: parse_u8(fields[1], line_number + 1)?,
            col: parse_u8(fields[2], line_number + 1)?,
            keycode: fields[3].parse().map_err(|_| {
                format!("{DYNAMIC_KEYMAP_TSV}:{}: invalid keycode", line_number + 1)
            })?,
            label: fields[5].to_string(),
            qmk: fields[6].to_string(),
        };
        let key = (entry.layer, entry.row, entry.col);
        if seen.insert(key, line_number + 1).is_some() {
            return Err(format!(
                "{DYNAMIC_KEYMAP_TSV}:{}: duplicate layer,row,col entry",
                line_number + 1
            ));
        }
        entries.push(entry);
    }
    Ok(entries)
}

fn parse_u8(value: &str, line_number: usize) -> Result<u8, String> {
    value
        .parse()
        .map_err(|_| format!("{DYNAMIC_KEYMAP_TSV}:{line_number}: invalid u8 value"))
}

fn keymap_drift_for_device(
    device: &dyn HidTransport,
    entries: &[KeyEntry],
) -> Result<usize, String> {
    let mut drift = 0usize;
    for entry in entries {
        if get_keycode(device, entry)? != entry.keycode {
            drift += 1;
        }
    }
    Ok(drift)
}

fn sync_keymap_for_device(
    descriptor: &DeviceDescriptor,
    entries: &[KeyEntry],
) -> Result<usize, String> {
    let device = open_hid(descriptor)?;
    let firmware = firmware_status(&device)?;
    if firmware.abi_hash_prefix != hash_prefix(EXPECTED_ABI_HASH) {
        return Err(format!(
            "firmware ABI {} does not match expected {}; not writing dynamic keymap",
            firmware.abi_hash_prefix,
            hash_prefix(EXPECTED_ABI_HASH)
        ));
    }

    let mut changed = 0usize;
    for entry in entries {
        let current = get_keycode(&device, entry)?;
        if current != entry.keycode {
            eprintln!(
                "{}: L{} R{} C{} {} {}: 0x{current:04x} -> 0x{:04x}",
                descriptor.display_name,
                entry.layer,
                entry.row,
                entry.col,
                entry.label,
                entry.qmk,
                entry.keycode
            );
            set_keycode(&device, entry)?;
            changed += 1;
        }
    }
    Ok(changed)
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn hash_prefix(hash: &str) -> String {
    hash.chars()
        .take(16)
        .collect::<String>()
        .to_ascii_lowercase()
}

fn is_interactive() -> bool {
    use std::io::IsTerminal;
    io::stdin().is_terminal() && io::stdout().is_terminal()
}

fn ask_yes_no(prompt: &str) -> Result<bool, String> {
    if !is_interactive() {
        return Ok(false);
    }
    eprint!("{prompt}");
    io::stderr().flush().map_err(|error| error.to_string())?;
    let mut answer = String::new();
    io::stdin()
        .read_line(&mut answer)
        .map_err(|error| format!("failed to read answer: {error}"))?;
    Ok(matches!(answer.trim(), "y" | "Y" | "yes" | "YES" | "Yes"))
}

fn ask_keyboard_half() -> Result<Option<KeyboardHalf>, String> {
    if !is_interactive() {
        return Err("specify the physical half with --left or --right".to_string());
    }
    eprint!("Flash which physical half? [l/r/N] ");
    io::stderr().flush().map_err(|error| error.to_string())?;
    let mut answer = String::new();
    io::stdin()
        .read_line(&mut answer)
        .map_err(|error| format!("failed to read answer: {error}"))?;
    match answer.trim().to_ascii_lowercase().as_str() {
        "l" | "left" => Ok(Some(KeyboardHalf::Left)),
        "r" | "right" => Ok(Some(KeyboardHalf::Right)),
        _ => Ok(None),
    }
}

#[cfg(target_os = "linux")]
fn request_user_prompt() -> Result<(), String> {
    let message = "Silakka54 firmware settings changed. Run `rebuild`, then flash the connected half explicitly.";
    if Command::new("notify-send")
        .args(["Silakka54 firmware update", message])
        .status()
        .is_err()
    {
        eprintln!("{message}");
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn request_user_prompt() -> Result<(), String> {
    let script = r#"display notification "Run rebuild, then flash the connected half explicitly." with title "Silakka54 firmware update""#;
    if Command::new("/usr/bin/osascript")
        .args(["-e", script])
        .status()
        .is_err()
    {
        eprintln!("Silakka54 firmware settings changed; rebuild and flash explicitly.");
    }
    Ok(())
}

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn request_user_prompt() -> Result<(), String> {
    Err("firmware prompts are unsupported on this platform".to_string())
}

fn wait_for_bootloader_mount(timeout: Duration) -> Result<PathBuf, String> {
    eprintln!("Waiting for RPI-RP2 bootloader mount. Put the connected Silakka54 half into bootloader mode if needed.");
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let mounts: Vec<_> = bootloader_mounts().into_iter().collect();
        match mounts.as_slice() {
            [path] => return Ok(path.clone()),
            [] => {}
            _ => {
                return Err(
                    "multiple RPI-RP2 mounts are present; refusing an ambiguous flash".to_string(),
                );
            }
        }
        thread::sleep(Duration::from_secs(1));
    }
    Err("timed out waiting for RPI-RP2 bootloader mount".to_string())
}

fn wait_for_new_bootloader_mount(
    previous: &BTreeSet<PathBuf>,
    timeout: Duration,
) -> Result<PathBuf, String> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        let new: Vec<_> = bootloader_mounts().difference(previous).cloned().collect();
        match new.as_slice() {
            [path] => return Ok(path.clone()),
            [] => thread::sleep(Duration::from_secs(1)),
            _ => {
                return Err(
                    "multiple new RPI-RP2 mounts appeared; refusing an ambiguous flash".to_string(),
                )
            }
        }
    }
    Err("timed out waiting for a new RPI-RP2 bootloader mount".to_string())
}

fn bootloader_mounts() -> BTreeSet<PathBuf> {
    let mut candidates = vec![
        PathBuf::from("/mnt/RPI-RP2"),
        PathBuf::from("/Volumes/RPI-RP2"),
    ];
    if let Some(user) = std::env::var_os("USER") {
        candidates.push(PathBuf::from("/run/media").join(&user).join("RPI-RP2"));
        candidates.push(PathBuf::from("/media").join(user).join("RPI-RP2"));
    }
    let mut mounts: BTreeSet<_> = candidates
        .into_iter()
        .filter(|path| is_bootloader_mount(path))
        .collect();

    if let Ok(contents) = fs::read_to_string("/proc/mounts") {
        for line in contents.lines() {
            if let Some(mount) = line.split_whitespace().nth(1) {
                let path = PathBuf::from(mount.replace("\\040", " "));
                if is_bootloader_mount(&path) {
                    mounts.insert(path);
                }
            }
        }
    }
    mounts
}

#[cfg(test)]
fn find_existing_mount<'a>(paths: impl Iterator<Item = &'a PathBuf>) -> Option<PathBuf> {
    paths
        .filter(|path| is_bootloader_mount(path))
        .cloned()
        .next()
}

fn is_bootloader_mount(path: &Path) -> bool {
    path.is_dir()
        && path.file_name().is_some_and(|name| name == "RPI-RP2")
        && (path.join("INFO_UF2.TXT").is_file() || path.join("INDEX.HTM").is_file())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::sync::Mutex;

    #[derive(Default)]
    struct MockTransport {
        writes: Mutex<Vec<Vec<u8>>>,
        reads: Mutex<VecDeque<Vec<u8>>>,
    }

    impl HidTransport for MockTransport {
        fn write(&self, data: &[u8]) -> Result<usize, String> {
            self.writes.lock().unwrap().push(data.to_vec());
            Ok(data.len())
        }

        fn read_timeout(&self, data: &mut [u8], _timeout_ms: i32) -> Result<usize, String> {
            let Some(response) = self.reads.lock().unwrap().pop_front() else {
                return Ok(0);
            };
            data[..response.len()].copy_from_slice(&response);
            Ok(response.len())
        }
    }

    #[test]
    fn flash_arguments_select_exactly_one_half() {
        let (yes, half) =
            parse_flash_args(["--right", "--yes"].into_iter().map(str::to_string)).unwrap();
        assert!(yes);
        assert_eq!(half, Some(KeyboardHalf::Right));

        let error =
            parse_flash_args(["--left", "--right"].into_iter().map(str::to_string)).unwrap_err();
        assert_eq!(error, "choose only one of --left or --right");
    }

    #[test]
    fn transaction_adds_zero_report_id() {
        let transport = MockTransport::default();
        let mut response = vec![0; REPORT_LEN];
        response[0] = ID_GET_PROTOCOL_VERSION;
        transport.reads.lock().unwrap().push_back(response);

        raw_transaction(
            &transport,
            command_report(ID_GET_PROTOCOL_VERSION),
            ID_GET_PROTOCOL_VERSION,
            Duration::from_millis(10),
        )
        .unwrap();

        let writes = transport.writes.lock().unwrap();
        assert_eq!(writes[0].len(), REPORT_LEN + 1);
        assert_eq!(writes[0][0], 0);
        assert_eq!(writes[0][1], ID_GET_PROTOCOL_VERSION);
    }

    #[test]
    fn transaction_accepts_leading_report_id() {
        let transport = MockTransport::default();
        let mut response = vec![0; REPORT_LEN + 1];
        response[1] = ID_GET_PROTOCOL_VERSION;
        transport.reads.lock().unwrap().push_back(response);

        let result = raw_transaction(
            &transport,
            command_report(ID_GET_PROTOCOL_VERSION),
            ID_GET_PROTOCOL_VERSION,
            Duration::from_millis(10),
        )
        .unwrap();
        assert_eq!(result[0], ID_GET_PROTOCOL_VERSION);
    }

    #[test]
    fn watcher_reconciles_only_new_devices() {
        let first = BTreeSet::from([b"first".to_vec()]);
        let both = BTreeSet::from([b"first".to_vec(), b"second".to_vec()]);
        assert!(should_reconcile(&BTreeSet::new(), &first));
        assert!(!should_reconcile(&first, &first));
        assert!(should_reconcile(&first, &both));
        assert!(!should_reconcile(&both, &BTreeSet::new()));
    }

    #[test]
    fn mount_detection_requires_expected_volume_name() {
        let root = std::env::temp_dir().join(format!("silakka54-sync-test-{}", std::process::id()));
        let expected = root.join("RPI-RP2");
        let other = root.join("OTHER");
        fs::create_dir_all(&expected).unwrap();
        fs::create_dir_all(&other).unwrap();
        fs::write(expected.join("INFO_UF2.TXT"), "UF2 Bootloader").unwrap();
        assert_eq!(
            find_existing_mount([&other, &expected].into_iter()),
            Some(expected.clone())
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn layer_name_is_a_momentary_layer_keycode() {
        let layers = BTreeMap::from([("Base", 0), ("Nav", 2)]);
        assert_eq!(
            resolve_keycode("Nav", &layers, &BTreeMap::new()).unwrap(),
            0x5222
        );
    }

    #[test]
    fn macros_are_encoded_as_via_nul_separated_buffer() {
        assert_eq!(
            desired_macro_buffer(&["one".into(), "two".into()], 4, 12).unwrap(),
            b"one\0two\0\0\0\0\0".to_vec()
        );
        assert!(desired_macro_buffer(&["too long".into()], 1, 4).is_err());
        assert!(desired_macro_buffer(&["one".into(), "two".into()], 1, 12).is_err());
    }

    #[test]
    fn live_keycodes_round_trip_to_configuration_expressions() {
        let keycodes = BTreeMap::from([("KC_A".to_string(), 0x04), ("KC_SPC".to_string(), 0x2c)]);
        let layers = vec!["_BASE".to_string(), "_NAV".to_string()];
        assert_eq!(
            describe_keycode(0x5221, &layers, &keycodes).unwrap(),
            "MO(_NAV)"
        );
        assert_eq!(
            describe_keycode(0x412c, &layers, &keycodes).unwrap(),
            "LT(_NAV, KC_SPC)"
        );
        assert_eq!(
            describe_keycode(0x2104, &layers, &keycodes).unwrap(),
            "LCTL_T(KC_A)"
        );
        assert_eq!(
            decode_macro_buffer(b"one\0two\0\0\0", 4).unwrap(),
            vec!["one", "two"]
        );
    }
}
