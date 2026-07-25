use hidapi::{HidApi, HidDevice};
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
const FIRMWARE_PATH: &str = "@firmware_path@";
const DYNAMIC_KEYMAP_TSV: &str = "@dynamic_keymap_tsv@";
const EXPECTED_ABI_HASH: &str = "@firmware_abi_hash@";
const EXPECTED_KEYMAP_HASH: &str = "@keymap_hash@";
const REPORT_LEN: usize = 32;

const ID_GET_PROTOCOL_VERSION: u8 = 0x01;
const ID_GET_KEYBOARD_VALUE: u8 = 0x02;
const ID_DYNAMIC_KEYMAP_GET_KEYCODE: u8 = 0x04;
const ID_DYNAMIC_KEYMAP_SET_KEYCODE: u8 = 0x05;
const ID_BOOTLOADER_JUMP: u8 = 0x0b;
const SILAKKA54_SYNC_QUERY: u8 = 0x54;
const SILAKKA54_SYNC_BOOTLOADER: u8 = 0x42;
const SILAKKA54_SYNC_VERSION: u8 = 1;
const SILAKKA54_SYNC_MAGIC: &[u8] = b"SL54SYN";

#[derive(Clone, Debug)]
struct KeyEntry {
    layer: u8,
    row: u8,
    col: u8,
    keycode: u16,
    label: String,
    qmk: String,
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

#[derive(Debug)]
struct FirmwareStatus {
    abi_hash_prefix: String,
    keymap_hash_prefix: String,
    layer_count: u8,
    rows: u8,
    cols: u8,
}

#[derive(Debug)]
struct DeviceStatus {
    name: String,
    via_protocol: Option<u16>,
    firmware: Option<FirmwareStatus>,
    keymap_drift: Option<usize>,
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
    let result = match command.as_str() {
        "status" => status_command(),
        "sync-keymap" => sync_keymap_command(),
        "flash-firmware" => flash_firmware_command(args.any(|arg| arg == "--yes" || arg == "-y")),
        "hotplug" => hotplug_command(),
        "rebuild-switch" => rebuild_switch_command(),
        "prompt-firmware" => prompt_firmware_command(),
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
    println!(
        "Usage: silakka54-sync <status|sync-keymap|flash-firmware|hotplug|rebuild-switch|prompt-firmware|watch>"
    );
}

fn status_command() -> Result<(), String> {
    let statuses = collect_statuses()?;
    if statuses.is_empty() {
        println!("Silakka54: no connected raw HID devices for {VID:04x}:{PID:04x}");
        return Ok(());
    }

    println!("Silakka54 manifest: {MANIFEST_PATH}");
    println!("Expected firmware ABI: {EXPECTED_ABI_HASH}");
    println!("Expected keymap: {EXPECTED_KEYMAP_HASH}");
    for status in statuses {
        print_device_status(&status);
    }
    Ok(())
}

fn rebuild_switch_command() -> Result<(), String> {
    if std::env::var_os("REBUILD_SKIP_SILAKKA54").is_some() {
        return Ok(());
    }

    let statuses = collect_statuses()?;
    if statuses.is_empty() {
        return Ok(());
    }

    let firmware_stale = statuses.iter().any(firmware_is_stale);
    let keymap_stale = statuses
        .iter()
        .any(|status| firmware_is_current(status) && status.keymap_drift.unwrap_or(0) > 0);

    if keymap_stale {
        sync_keymap_command()?;
    }

    if firmware_stale {
        if is_interactive() {
            eprintln!("Silakka54 firmware ABI is stale for a connected half.");
            if ask_yes_no("Flash the connected Silakka54 half now? [y/N] ")? {
                flash_firmware_command(true)?;
            } else {
                eprintln!("Silakka54 firmware flash deferred.");
            }
        } else {
            eprintln!(
                "Silakka54 firmware ABI is stale; flashing deferred in noninteractive rebuild."
            );
        }
    }

    Ok(())
}

fn hotplug_command() -> Result<(), String> {
    let statuses = collect_statuses()?;
    if statuses.is_empty() {
        return Ok(());
    }

    if statuses
        .iter()
        .any(|status| firmware_is_current(status) && status.keymap_drift.unwrap_or(0) > 0)
    {
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

#[cfg(target_os = "linux")]
fn prompt_firmware_command() -> Result<(), String> {
    if std::env::var_os("DISPLAY").is_none() && std::env::var_os("WAYLAND_DISPLAY").is_none() {
        eprintln!(
            "Silakka54 firmware is stale; no graphical session is available, deferring flash."
        );
        return Ok(());
    }

    let status = Command::new("zenity")
        .args([
            "--question",
            "--title",
            "Silakka54 firmware",
            "--text",
            "Firmware is stale for the connected Silakka54 half.",
            "--ok-label",
            "Flash now",
            "--cancel-label",
            "Skip this time",
        ])
        .status()
        .map_err(|error| format!("failed to run graphical prompt: {error}"))?;

    if status.success() {
        flash_firmware_command(true)
    } else {
        eprintln!("Silakka54 firmware flash skipped from graphical prompt.");
        Ok(())
    }
}

#[cfg(target_os = "macos")]
fn prompt_firmware_command() -> Result<(), String> {
    let script = r#"button returned of (display dialog "Firmware is stale for the connected Silakka54 half." with title "Silakka54 firmware" buttons {"Skip this time", "Flash now"} default button "Flash now")"#;
    let output = Command::new("/usr/bin/osascript")
        .args(["-e", script])
        .output()
        .map_err(|error| format!("failed to run macOS firmware prompt: {error}"))?;

    if output.status.success() && String::from_utf8_lossy(&output.stdout).trim() == "Flash now" {
        flash_firmware_command(true)
    } else {
        eprintln!("Silakka54 firmware flash skipped from graphical prompt.");
        Ok(())
    }
}

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn prompt_firmware_command() -> Result<(), String> {
    Err("graphical firmware prompts are unsupported on this platform".to_string())
}

fn sync_keymap_command() -> Result<(), String> {
    let entries = read_keymap_entries()?;
    let devices = via_devices()?;
    if devices.is_empty() {
        println!("Silakka54: no connected VIA-capable HID devices for {VID:04x}:{PID:04x}");
        return Ok(());
    }

    let mut changed_total = 0usize;
    for descriptor in devices {
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
            }
            Err(error) => eprintln!("{}: keymap sync failed: {error}", descriptor.display_name),
        }
    }

    if changed_total > 0 {
        println!("Silakka54 dynamic keymap synced ({changed_total} keycodes changed).");
    }
    Ok(())
}

fn flash_firmware_command(yes: bool) -> Result<(), String> {
    if !yes && !ask_yes_no("Flash the connected Silakka54 half with the packaged UF2? [y/N] ")? {
        return Ok(());
    }

    if request_silakka54_bootloader_jump()? {
        match wait_for_bootloader_mount(Duration::from_secs(30)) {
            Ok(mount) => return copy_firmware_and_verify(&mount),
            Err(error) => eprintln!("Silakka54 bootloader jump did not produce RPI-RP2: {error}"),
        }
    }

    if request_vial_bootloader_jump()? {
        match wait_for_bootloader_mount(Duration::from_secs(30)) {
            Ok(mount) => return copy_firmware_and_verify(&mount),
            Err(error) => eprintln!("Vial bootloader jump did not produce RPI-RP2: {error}"),
        }
    }

    let mount = wait_for_bootloader_mount(Duration::from_secs(120))?;
    copy_firmware_and_verify(&mount)
}

fn request_silakka54_bootloader_jump() -> Result<bool, String> {
    for descriptor in via_devices()? {
        match open_hid(&descriptor) {
            Ok(device) => match silakka54_bootloader_jump(&device) {
                Ok(()) => {
                    eprintln!(
                        "{}: requested Silakka54 bootloader jump",
                        descriptor.display_name
                    );
                    return Ok(true);
                }
                Err(error) => eprintln!(
                    "{}: Silakka54 bootloader jump unavailable: {error}",
                    descriptor.display_name
                ),
            },
            Err(error) => eprintln!(
                "{}: could not open HID device for Silakka54 bootloader jump: {error}",
                descriptor.display_name
            ),
        }
    }
    Ok(false)
}

fn request_vial_bootloader_jump() -> Result<bool, String> {
    for descriptor in via_devices()? {
        match open_hid(&descriptor) {
            Ok(device) => match raw_transaction(
                &device,
                command_report(ID_BOOTLOADER_JUMP),
                ID_BOOTLOADER_JUMP,
                Duration::from_millis(500),
            ) {
                Ok(_) => {
                    eprintln!(
                        "{}: requested Vial bootloader jump",
                        descriptor.display_name
                    );
                    return Ok(true);
                }
                Err(error) => eprintln!(
                    "{}: Vial bootloader jump unavailable: {error}",
                    descriptor.display_name
                ),
            },
            Err(error) => eprintln!(
                "{}: could not open HID device for bootloader jump: {error}",
                descriptor.display_name
            ),
        }
    }
    Ok(false)
}

fn copy_firmware_and_verify(mount: &Path) -> Result<(), String> {
    let target = mount.join(
        Path::new(FIRMWARE_PATH)
            .file_name()
            .ok_or_else(|| "firmware path has no file name".to_string())?,
    );
    fs::copy(FIRMWARE_PATH, &target)
        .map_err(|error| format!("failed to copy UF2 to {}: {error}", target.display()))?;
    sync_firmware_copy(&target)?;
    println!("Copied firmware UF2 to {}", target.display());

    let deadline = Instant::now() + Duration::from_secs(60);
    while Instant::now() < deadline {
        thread::sleep(Duration::from_secs(1));
        match collect_statuses() {
            Ok(statuses) if statuses.iter().any(firmware_is_current) => {
                println!("Silakka54 firmware ABI verified after reconnect.");
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
    let entries = read_keymap_entries().unwrap_or_default();
    raw_hid_devices()?
        .iter()
        .map(|descriptor| Ok(device_status(descriptor, &entries)))
        .collect()
}

fn device_status(descriptor: &DeviceDescriptor, entries: &[KeyEntry]) -> DeviceStatus {
    let mut status = DeviceStatus {
        name: descriptor.display_name.clone(),
        via_protocol: None,
        firmware: None,
        keymap_drift: None,
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
            println!("  compiled keymap: {}", firmware.keymap_hash_prefix);
            println!(
                "  dynamic matrix: {} layers, {} rows, {} cols",
                firmware.layer_count, firmware.rows, firmware.cols
            );
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
}

fn firmware_is_current(status: &DeviceStatus) -> bool {
    status
        .firmware
        .as_ref()
        .is_some_and(|firmware| firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH))
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
    let mut report = command_report(ID_GET_KEYBOARD_VALUE);
    report[1] = SILAKKA54_SYNC_QUERY;
    report[2] = SILAKKA54_SYNC_VERSION;
    let response = raw_transaction(
        device,
        report,
        ID_GET_KEYBOARD_VALUE,
        Duration::from_secs(1),
    )?;
    if response[1] != SILAKKA54_SYNC_QUERY || response[2] != SILAKKA54_SYNC_VERSION {
        return Err("firmware did not answer Silakka54 sync query".to_string());
    }
    if &response[3..10] != SILAKKA54_SYNC_MAGIC {
        return Err("firmware sync magic mismatch".to_string());
    }
    Ok(FirmwareStatus {
        abi_hash_prefix: bytes_to_hex(&response[11..19]),
        keymap_hash_prefix: bytes_to_hex(&response[19..27]),
        layer_count: response[27],
        rows: response[28],
        cols: response[29],
    })
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

#[cfg(target_os = "linux")]
fn request_user_prompt() -> Result<(), String> {
    let status = Command::new("systemctl")
        .args([
            "--user",
            "--machine=conroy@.host",
            "--no-block",
            "start",
            "silakka54-firmware-prompt.service",
        ])
        .status()
        .map_err(|error| format!("failed to request user prompt: {error}"))?;
    if !status.success() {
        eprintln!("Silakka54 firmware is stale; graphical prompt could not be started.");
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn request_user_prompt() -> Result<(), String> {
    prompt_firmware_command()
}

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
fn request_user_prompt() -> Result<(), String> {
    Err("firmware prompts are unsupported on this platform".to_string())
}

fn wait_for_bootloader_mount(timeout: Duration) -> Result<PathBuf, String> {
    eprintln!("Waiting for RPI-RP2 bootloader mount. Put the connected Silakka54 half into bootloader mode if needed.");
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Some(path) = find_bootloader_mount() {
            return Ok(path);
        }
        thread::sleep(Duration::from_secs(1));
    }
    Err("timed out waiting for RPI-RP2 bootloader mount".to_string())
}

fn find_bootloader_mount() -> Option<PathBuf> {
    let user = std::env::var("USER").unwrap_or_else(|_| "conroy".to_string());
    let candidates = [
        PathBuf::from(format!("/run/media/{user}/RPI-RP2")),
        PathBuf::from(format!("/media/{user}/RPI-RP2")),
        PathBuf::from("/mnt/RPI-RP2"),
        PathBuf::from("/Volumes/RPI-RP2"),
    ];
    if let Some(path) = find_existing_mount(candidates.iter()) {
        return Some(path);
    }

    let mounts = fs::read_to_string("/proc/mounts").ok()?;
    mounts.lines().find_map(|line| {
        let mount = line.split_whitespace().nth(1)?.replace("\\040", " ");
        let path = PathBuf::from(mount);
        is_bootloader_mount(&path).then_some(path)
    })
}

fn find_existing_mount<'a>(paths: impl Iterator<Item = &'a PathBuf>) -> Option<PathBuf> {
    paths
        .filter(|path| is_bootloader_mount(path))
        .cloned()
        .next()
}

fn is_bootloader_mount(path: &Path) -> bool {
    path.is_dir() && path.file_name().is_some_and(|name| name == "RPI-RP2")
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
        assert_eq!(
            find_existing_mount([&other, &expected].into_iter()),
            Some(expected.clone())
        );
        fs::remove_dir_all(root).unwrap();
    }
}
