use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::thread;
use std::time::{Duration, Instant};

const VID: &str = "feed";
const PID: &str = "1212";
const MANIFEST_PATH: &str = "@manifest_path@";
const FIRMWARE_PATH: &str = "@firmware_path@";
const DYNAMIC_KEYMAP_TSV: &str = "@dynamic_keymap_tsv@";
const EXPECTED_ABI_HASH: &str = "@firmware_abi_hash@";
const EXPECTED_KEYMAP_HASH: &str = "@keymap_hash@";
const REPORT_LEN: usize = 32;
const POLLIN: i16 = 0x0001;

const ID_GET_PROTOCOL_VERSION: u8 = 0x01;
const ID_GET_KEYBOARD_VALUE: u8 = 0x02;
const ID_DYNAMIC_KEYMAP_GET_KEYCODE: u8 = 0x04;
const ID_DYNAMIC_KEYMAP_SET_KEYCODE: u8 = 0x05;
const ID_BOOTLOADER_JUMP: u8 = 0x0B;
const SILAKKA54_SYNC_QUERY: u8 = 0x54;
const SILAKKA54_SYNC_BOOTLOADER: u8 = 0x42;
const SILAKKA54_SYNC_VERSION: u8 = 1;
const SILAKKA54_SYNC_MAGIC: &[u8] = b"SL54SYN";

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

unsafe extern "C" {
    fn poll(fds: *mut PollFd, nfds: usize, timeout: i32) -> i32;
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
    path: PathBuf,
    via_protocol: Option<u16>,
    firmware: Option<FirmwareStatus>,
    keymap_drift: Option<usize>,
    error: Option<String>,
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
        "Usage: silakka54-sync <status|sync-keymap|flash-firmware|hotplug|rebuild-switch|prompt-firmware>"
    );
}

fn status_command() -> Result<(), String> {
    let statuses = collect_statuses(false)?;
    if statuses.is_empty() {
        println!("Silakka54: no connected hidraw devices for {VID}:{PID}");
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

    let statuses = collect_statuses(false)?;
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
    let statuses = collect_statuses(false)?;
    if statuses.is_empty() {
        return Ok(());
    }

    let has_stale_keymap = statuses
        .iter()
        .any(|status| firmware_is_current(status) && status.keymap_drift.unwrap_or(0) > 0);
    if has_stale_keymap {
        sync_keymap_command()?;
    }

    if statuses.iter().any(firmware_is_stale) {
        request_user_prompt()?;
    }

    Ok(())
}

fn prompt_firmware_command() -> Result<(), String> {
    if std::env::var_os("DISPLAY").is_none() && std::env::var_os("WAYLAND_DISPLAY").is_none() {
        eprintln!(
            "Silakka54 firmware is stale; no graphical session is available, deferring flash."
        );
        return Ok(());
    }

    let message = "Firmware is stale for the connected Silakka54 half.";
    let status = Command::new("zenity")
        .args([
            "--question",
            "--title",
            "Silakka54 firmware",
            "--text",
            message,
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

fn sync_keymap_command() -> Result<(), String> {
    let entries = read_keymap_entries()?;
    let paths = via_hidraw_paths();
    if paths.is_empty() {
        println!("Silakka54: no connected VIA-capable hidraw devices for {VID}:{PID}");
        return Ok(());
    }

    let mut changed_total = 0usize;
    for path in paths {
        match sync_keymap_for_path(&path, &entries) {
            Ok(changed) => {
                changed_total += changed;
                if changed == 0 {
                    println!("{}: keymap already current", path.display());
                } else {
                    println!("{}: wrote {changed} differing keycodes", path.display());
                }
            }
            Err(error) => eprintln!("{}: keymap sync failed: {error}", path.display()),
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
    for path in via_hidraw_paths() {
        match open_hid(&path) {
            Ok(mut file) => match silakka54_bootloader_jump(&mut file) {
                Ok(()) => {
                    eprintln!("{}: requested Silakka54 bootloader jump", path.display());
                    return Ok(true);
                }
                Err(error) => {
                    eprintln!(
                        "{}: Silakka54 bootloader jump unavailable: {error}",
                        path.display()
                    );
                }
            },
            Err(error) => {
                eprintln!(
                    "{}: could not open HID device for Silakka54 bootloader jump: {error}",
                    path.display()
                );
            }
        }
    }
    Ok(false)
}

fn request_vial_bootloader_jump() -> Result<bool, String> {
    for path in via_hidraw_paths() {
        match open_hid(&path) {
            Ok(mut file) => {
                match raw_transaction(
                    &mut file,
                    command_report(ID_BOOTLOADER_JUMP),
                    ID_BOOTLOADER_JUMP,
                    Duration::from_millis(500),
                ) {
                    Ok(_) => {
                        eprintln!("{}: requested Vial bootloader jump", path.display());
                        return Ok(true);
                    }
                    Err(error) => {
                        eprintln!(
                            "{}: Vial bootloader jump unavailable: {error}",
                            path.display()
                        );
                    }
                }
            }
            Err(error) => {
                eprintln!(
                    "{}: could not open HID device for bootloader jump: {error}",
                    path.display()
                );
            }
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
    sync_mount(&mount)?;
    println!("Copied firmware UF2 to {}", target.display());

    let deadline = Instant::now() + Duration::from_secs(60);
    while Instant::now() < deadline {
        thread::sleep(Duration::from_secs(1));
        let statuses = collect_statuses(false)?;
        if statuses.iter().any(firmware_is_current) {
            println!("Silakka54 firmware ABI verified after reconnect.");
            return Ok(());
        }
    }

    Err("firmware was copied, but the keyboard did not reconnect with the expected ABI".to_string())
}

fn collect_statuses(include_drift: bool) -> Result<Vec<DeviceStatus>, String> {
    let entries = if include_drift {
        Some(read_keymap_entries()?)
    } else {
        Some(read_keymap_entries().unwrap_or_default())
    };
    let mut statuses = Vec::new();
    for path in hidraw_paths() {
        statuses.push(device_status(&path, entries.as_deref()));
    }
    Ok(statuses)
}

fn device_status(path: &Path, entries: Option<&[KeyEntry]>) -> DeviceStatus {
    let mut status = DeviceStatus {
        path: path.to_path_buf(),
        via_protocol: None,
        firmware: None,
        keymap_drift: None,
        error: None,
    };

    let mut file = match open_hid(path) {
        Ok(file) => file,
        Err(error) => {
            status.error = Some(error.to_string());
            return status;
        }
    };

    status.via_protocol = via_protocol(&mut file).ok();
    if status.via_protocol.is_some() {
        status.firmware = firmware_status(&mut file).ok();
    }

    if status
        .firmware
        .as_ref()
        .is_some_and(|firmware| firmware.abi_hash_prefix == hash_prefix(EXPECTED_ABI_HASH))
    {
        if let Some(entries) = entries {
            status.keymap_drift = keymap_drift_for_file(&mut file, entries).ok();
        }
    }

    status
}

fn print_device_status(status: &DeviceStatus) {
    println!("Device: {}", status.path.display());
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

fn hidraw_paths() -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir("/sys/class/hidraw") else {
        return Vec::new();
    };
    let needle = format!(":0000{}:0000{}", VID, PID);
    let mut paths: Vec<_> = entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            let uevent = fs::read_to_string(entry.path().join("device/uevent")).ok()?;
            if uevent.to_ascii_lowercase().contains(&needle) {
                Some(PathBuf::from("/dev").join(name.as_ref()))
            } else {
                None
            }
        })
        .collect();
    paths.sort();
    paths
}

fn via_hidraw_paths() -> Vec<PathBuf> {
    hidraw_paths()
        .into_iter()
        .filter(|path| {
            open_hid(path)
                .and_then(|mut file| via_protocol(&mut file).map_err(io::Error::other))
                .is_ok()
        })
        .collect()
}

fn open_hid(path: &Path) -> io::Result<File> {
    OpenOptions::new().read(true).write(true).open(path)
}

fn via_protocol(file: &mut File) -> Result<u16, String> {
    let response = raw_transaction(
        file,
        command_report(ID_GET_PROTOCOL_VERSION),
        ID_GET_PROTOCOL_VERSION,
        Duration::from_secs(1),
    )?;
    Ok(u16::from_be_bytes([response[1], response[2]]))
}

fn firmware_status(file: &mut File) -> Result<FirmwareStatus, String> {
    let mut report = command_report(ID_GET_KEYBOARD_VALUE);
    report[1] = SILAKKA54_SYNC_QUERY;
    report[2] = SILAKKA54_SYNC_VERSION;
    let response = raw_transaction(file, report, ID_GET_KEYBOARD_VALUE, Duration::from_secs(1))?;
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

fn silakka54_bootloader_jump(file: &mut File) -> Result<(), String> {
    let mut report = command_report(ID_GET_KEYBOARD_VALUE);
    report[1] = SILAKKA54_SYNC_BOOTLOADER;
    report[2] = SILAKKA54_SYNC_VERSION;
    let response = raw_transaction(
        file,
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

fn get_keycode(file: &mut File, entry: &KeyEntry) -> Result<u16, String> {
    let mut report = command_report(ID_DYNAMIC_KEYMAP_GET_KEYCODE);
    report[1] = entry.layer;
    report[2] = entry.row;
    report[3] = entry.col;
    let response = raw_transaction(
        file,
        report,
        ID_DYNAMIC_KEYMAP_GET_KEYCODE,
        Duration::from_secs(1),
    )?;
    Ok(u16::from_be_bytes([response[4], response[5]]))
}

fn set_keycode(file: &mut File, entry: &KeyEntry) -> Result<(), String> {
    let mut report = command_report(ID_DYNAMIC_KEYMAP_SET_KEYCODE);
    report[1] = entry.layer;
    report[2] = entry.row;
    report[3] = entry.col;
    report[4] = (entry.keycode >> 8) as u8;
    report[5] = (entry.keycode & 0xFF) as u8;
    raw_transaction(
        file,
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
    file: &mut File,
    report: [u8; REPORT_LEN],
    expected_command: u8,
    timeout: Duration,
) -> Result<[u8; REPORT_LEN], String> {
    file.write_all(&report)
        .map_err(|error| format!("hid write failed: {error}"))?;

    let deadline = Instant::now() + timeout;
    let mut buffer = [0u8; REPORT_LEN + 1];
    while Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if !poll_readable(file, remaining.min(Duration::from_millis(100)))? {
            continue;
        }
        let len = file
            .read(&mut buffer)
            .map_err(|error| format!("hid read failed: {error}"))?;
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
    if buffer.first() == Some(&0) {
        &buffer[1..]
    } else {
        buffer
    }
}

fn poll_readable(file: &File, timeout: Duration) -> Result<bool, String> {
    let timeout_ms = timeout.as_millis().min(i32::MAX as u128) as i32;
    let mut poll_fd = PollFd {
        fd: file.as_raw_fd(),
        events: POLLIN,
        revents: 0,
    };
    let result = unsafe { poll(&mut poll_fd, 1, timeout_ms) };
    if result < 0 {
        return Err(io::Error::last_os_error().to_string());
    }
    Ok(result > 0 && (poll_fd.revents & POLLIN) != 0)
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

fn keymap_drift_for_file(file: &mut File, entries: &[KeyEntry]) -> Result<usize, String> {
    let mut drift = 0usize;
    for entry in entries {
        let current = get_keycode(file, entry)?;
        if current != entry.keycode {
            drift += 1;
        }
    }
    Ok(drift)
}

fn sync_keymap_for_path(path: &Path, entries: &[KeyEntry]) -> Result<usize, String> {
    let mut file = open_hid(path).map_err(|error| error.to_string())?;
    let firmware = firmware_status(&mut file)?;
    if firmware.abi_hash_prefix != hash_prefix(EXPECTED_ABI_HASH) {
        return Err(format!(
            "firmware ABI {} does not match expected {}; not writing dynamic keymap",
            firmware.abi_hash_prefix,
            hash_prefix(EXPECTED_ABI_HASH)
        ));
    }

    let mut changed = 0usize;
    for entry in entries {
        let current = get_keycode(&mut file, entry)?;
        if current != entry.keycode {
            eprintln!(
                "{}: L{} R{} C{} {} {}: 0x{current:04x} -> 0x{:04x}",
                path.display(),
                entry.layer,
                entry.row,
                entry.col,
                entry.label,
                entry.qmk,
                entry.keycode
            );
            set_keycode(&mut file, entry)?;
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
    unsafe extern "C" {
        fn isatty(fd: i32) -> i32;
    }
    unsafe { isatty(0) == 1 && isatty(1) == 1 }
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
    for path in [
        format!("/run/media/{user}/RPI-RP2"),
        format!("/media/{user}/RPI-RP2"),
        "/mnt/RPI-RP2".to_string(),
    ] {
        let path = PathBuf::from(path);
        if path.is_dir() {
            return Some(path);
        }
    }

    let mounts = fs::read_to_string("/proc/mounts").ok()?;
    for line in mounts.lines() {
        let mount = line.split_whitespace().nth(1)?;
        let mount = mount.replace("\\040", " ");
        let path = PathBuf::from(mount);
        if path.file_name().is_some_and(|name| name == "RPI-RP2") && path.is_dir() {
            return Some(path);
        }
    }
    None
}

fn sync_mount(path: &Path) -> Result<(), String> {
    let status = Command::new("sync")
        .arg(path)
        .status()
        .map_err(|error| format!("failed to sync {}: {error}", path.display()))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("sync {} exited with {status}", path.display()))
    }
}
