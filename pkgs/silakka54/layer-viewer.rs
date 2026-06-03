use std::ffi::CString;
use std::fs::{self, File};
use std::io::Read;
use std::os::raw::{c_char, c_int, c_uint, c_ulong, c_void};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::Duration;

const ASSET_DIR: &str = "@asset_dir@";
const DEFAULT_VID: &str = "feed";
const DEFAULT_PID: &str = "1212";
const REPORT_MAGIC: &[u8] = b"SL54LYR";
const GTK_WINDOW_TOPLEVEL: c_int = 0;
const GTK_ORIENTATION_VERTICAL: c_int = 1;
const G_SOURCE_CONTINUE: c_int = 1;

#[link(name = "gtk-3")]
#[link(name = "gobject-2.0")]
extern "C" {
    fn gtk_init(argc: *mut c_int, argv: *mut *mut *mut c_char);
    fn gtk_window_new(window_type: c_int) -> *mut c_void;
    fn gtk_window_set_title(window: *mut c_void, title: *const c_char);
    fn gtk_window_set_default_size(window: *mut c_void, width: c_int, height: c_int);
    fn gtk_box_new(orientation: c_int, spacing: c_int) -> *mut c_void;
    fn gtk_container_add(container: *mut c_void, widget: *mut c_void);
    fn gtk_box_pack_start(
        box_: *mut c_void,
        child: *mut c_void,
        expand: c_int,
        fill: c_int,
        padding: c_uint,
    );
    fn gtk_image_new_from_file(filename: *const c_char) -> *mut c_void;
    fn gtk_image_set_from_file(image: *mut c_void, filename: *const c_char);
    fn gtk_label_new(text: *const c_char) -> *mut c_void;
    fn gtk_label_set_text(label: *mut c_void, text: *const c_char);
    fn gtk_widget_show_all(widget: *mut c_void);
    fn gtk_main();
    fn gtk_main_quit();
    fn g_timeout_add(
        interval: c_uint,
        function: Option<unsafe extern "C" fn(*mut c_void) -> c_int>,
        data: *mut c_void,
    ) -> c_uint;
    fn g_signal_connect_data(
        instance: *mut c_void,
        detailed_signal: *const c_char,
        c_handler: Option<unsafe extern "C" fn(*mut c_void, *mut c_void)>,
        data: *mut c_void,
        destroy_data: Option<unsafe extern "C" fn(*mut c_void)>,
        connect_flags: c_int,
    ) -> c_ulong;
}

struct Args {
    vid: String,
    pid: String,
    path: Option<PathBuf>,
    simulate_layer: Option<u8>,
}

struct AppState {
    rx: Receiver<u8>,
    image: *mut c_void,
    label: *mut c_void,
    layers: Vec<&'static str>,
    current_layer: u8,
}

fn parse_args() -> Args {
    let mut args = std::env::args().skip(1);
    let mut parsed = Args {
        vid: DEFAULT_VID.to_string(),
        pid: DEFAULT_PID.to_string(),
        path: None,
        simulate_layer: None,
    };

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--vid" => {
                parsed.vid = normalize_hex_arg(&args.next().expect("--vid requires a value"));
            }
            "--pid" => {
                parsed.pid = normalize_hex_arg(&args.next().expect("--pid requires a value"));
            }
            "--path" => {
                parsed.path = Some(PathBuf::from(args.next().expect("--path requires a value")));
            }
            "--simulate-layer" => {
                let value = args.next().expect("--simulate-layer requires a value");
                parsed.simulate_layer = Some(value.parse().expect("--simulate-layer must be an integer"));
            }
            "--help" | "-h" => {
                println!(
                    "Usage: silakka54-layer-viewer [--vid 0xfeed] [--pid 0x1212] [--path /dev/hidrawN] [--simulate-layer N]"
                );
                std::process::exit(0);
            }
            other => panic!("unknown argument: {}", other),
        }
    }

    parsed
}

fn normalize_hex_arg(value: &str) -> String {
    let trimmed = value.trim_start_matches("0x").trim_start_matches("0X");
    format!("{:0>4}", trimmed.to_ascii_lowercase())
}

fn hidraw_paths(args: &Args) -> Vec<PathBuf> {
    if let Some(path) = &args.path {
        return vec![path.clone()];
    }

    let Ok(entries) = fs::read_dir("/sys/class/hidraw") else {
        return Vec::new();
    };

    entries
        .filter_map(Result::ok)
        .filter_map(|entry| {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            let uevent = entry.path().join("device/uevent");
            let contents = fs::read_to_string(uevent).ok()?;
            let needle = format!(":0000{}:0000{}", args.vid, args.pid);
            if contents.to_ascii_lowercase().contains(&needle) {
                Some(PathBuf::from("/dev").join(name.as_ref()))
            } else {
                None
            }
        })
        .collect()
}

fn normalize_report(buffer: &[u8], len: usize) -> &[u8] {
    let data = &buffer[..len];
    if data.first() == Some(&0) {
        &data[1..]
    } else {
        data
    }
}

fn read_layers(args: Args, tx: mpsc::Sender<u8>) {
    loop {
        let paths = hidraw_paths(&args);
        if paths.is_empty() {
            thread::sleep(Duration::from_secs(1));
            continue;
        }

        for path in paths {
            let Ok(mut file) = File::open(&path) else {
                continue;
            };
            let mut buffer = [0u8; 33];
            loop {
                match file.read(&mut buffer) {
                    Ok(len) if len > 0 => {
                        let report = normalize_report(&buffer, len);
                        if report.len() >= 9 && &report[0..7] == REPORT_MAGIC && report[7] == 1 {
                            let _ = tx.send(report[8]);
                        }
                    }
                    Ok(_) => thread::sleep(Duration::from_millis(100)),
                    Err(_) => break,
                }
            }
        }

        thread::sleep(Duration::from_secs(1));
    }
}

fn layer_image(layer: u8, layers: &[&str]) -> CString {
    let name = layers.get(layer as usize).copied().unwrap_or("base");
    let path = Path::new(ASSET_DIR)
        .join("layers")
        .join(format!("{}.png", name.to_ascii_lowercase()));
    CString::new(path.to_string_lossy().as_bytes()).unwrap()
}

fn set_layer(state: &mut AppState, layer: u8) {
    let layer = if (layer as usize) < state.layers.len() { layer } else { 0 };
    if layer == state.current_layer {
        return;
    }

    state.current_layer = layer;
    let image_path = layer_image(layer, &state.layers);
    let label_text = CString::new(format!("Layer {}: {}", layer, state.layers[layer as usize])).unwrap();
    unsafe {
        gtk_image_set_from_file(state.image, image_path.as_ptr());
        gtk_label_set_text(state.label, label_text.as_ptr());
    }
}

unsafe extern "C" fn poll_layers(data: *mut c_void) -> c_int {
    let state = &mut *(data as *mut AppState);
    while let Ok(layer) = state.rx.try_recv() {
        set_layer(state, layer);
    }
    G_SOURCE_CONTINUE
}

unsafe extern "C" fn on_destroy(_widget: *mut c_void, _data: *mut c_void) {
    gtk_main_quit();
}

fn main() {
    let args = parse_args();
    let initial_layer = args.simulate_layer.unwrap_or(0);
    let (tx, rx) = mpsc::channel();

    if let Some(layer) = args.simulate_layer {
        tx.send(layer).ok();
    } else {
        thread::spawn(move || read_layers(args, tx));
    }

    let layers = vec!["base", "num", "nav", "sym"];
    let initial_path = layer_image(initial_layer, &layers);
    let initial_label = CString::new(format!("Layer {}: {}", initial_layer, layers[initial_layer as usize])).unwrap();
    let title = CString::new("Silakka54 keymap").unwrap();
    let destroy = CString::new("destroy").unwrap();

    unsafe {
        gtk_init(std::ptr::null_mut(), std::ptr::null_mut());

        let window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
        gtk_window_set_title(window, title.as_ptr());
        gtk_window_set_default_size(window, 1100, 460);

        let box_ = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        let image = gtk_image_new_from_file(initial_path.as_ptr());
        let label = gtk_label_new(initial_label.as_ptr());

        gtk_box_pack_start(box_, image, 1, 1, 0);
        gtk_box_pack_start(box_, label, 0, 0, 4);
        gtk_container_add(window, box_);

        g_signal_connect_data(window, destroy.as_ptr(), Some(on_destroy), std::ptr::null_mut(), None, 0);

        let state = Box::into_raw(Box::new(AppState {
            rx,
            image,
            label,
            layers,
            current_layer: initial_layer,
        }));
        g_timeout_add(100, Some(poll_layers), state as *mut c_void);

        gtk_widget_show_all(window);
        gtk_main();
    }
}
