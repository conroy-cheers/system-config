use anyhow::{bail, Context, Result};
use glib::object::Cast;
use gtk::cairo::{Context as CairoContext, FontSlant, FontWeight, Operator};
use gtk::gdk;
use gtk::prelude::*;
use gtk::{Application, ApplicationWindow, DrawingArea};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer as ShellLayer, LayerShell};
use serde::Deserialize;
use serde_yaml::Value as YamlValue;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const APP_ID: &str = "dev.corncheese.silakka54.LayerViewer";
const DEFAULT_VID: &str = "feed";
const DEFAULT_PID: &str = "1212";
const LAYER_REPORT_MAGIC: &[u8] = b"SL54LYR";
const KEY_REPORT_MAGIC: &[u8] = b"SL54KEY";
const WINDOW_WIDTH: i32 = 659;
const WINDOW_HEIGHT: i32 = 284;
const BOTTOM_MARGIN: i32 = 12;
const OVERLAY_OPACITY: f64 = 0.60;
const KEY_FILL_OPACITY: f64 = 0.72;
const AUTO_HIDE_DURATION: Duration = Duration::from_secs(3);
const SUPPRESSED_SUBMAP: &str = "game";

const CSS: &str = r#"
window {
  background-color: transparent;
}
"#;

#[derive(Clone)]
struct KeyLayer {
    name: String,
    keys: Vec<String>,
}

#[derive(Clone)]
struct KeyboardLayout {
    keys: Vec<KeyGeometry>,
    bounds: LayoutBounds,
}

#[derive(Clone, Copy)]
struct LayoutBounds {
    min_x: f64,
    min_y: f64,
    width: f64,
    height: f64,
}

#[derive(Deserialize)]
struct QmkInfo {
    layouts: HashMap<String, QmkLayout>,
}

#[derive(Deserialize)]
struct QmkLayout {
    layout: Vec<QmkKey>,
}

#[derive(Deserialize)]
struct QmkKey {
    x: f64,
    y: f64,
    #[serde(default = "one_f64")]
    w: f64,
    #[serde(default = "one_f64")]
    h: f64,
    #[serde(default)]
    r: f64,
    rx: Option<f64>,
    ry: Option<f64>,
}

fn one_f64() -> f64 {
    1.0
}

#[derive(Clone, Copy)]
struct Color {
    red: f64,
    green: f64,
    blue: f64,
}

impl Color {
    const fn hex(value: u32) -> Self {
        Self {
            red: ((value >> 16) & 0xff) as f64 / 255.0,
            green: ((value >> 8) & 0xff) as f64 / 255.0,
            blue: (value & 0xff) as f64 / 255.0,
        }
    }

    fn from_rgba(value: &gdk::RGBA) -> Self {
        Self {
            red: value.red() as f64,
            green: value.green() as f64,
            blue: value.blue() as f64,
        }
    }

    fn mix(self, other: Self, amount: f64) -> Self {
        let amount = amount.clamp(0.0, 1.0);
        Self {
            red: self.red + (other.red - self.red) * amount,
            green: self.green + (other.green - self.green) * amount,
            blue: self.blue + (other.blue - self.blue) * amount,
        }
    }

    fn luminance(self) -> f64 {
        0.2126 * self.red + 0.7152 * self.green + 0.0722 * self.blue
    }
}

struct ThemePalette {
    text: Color,
    muted: Color,
    key: Color,
    key_dim: Color,
    accent: Color,
    layer: Color,
    outline: Color,
    inverse_text: Color,
}

impl ThemePalette {
    fn from_widget(widget: &DrawingArea) -> Self {
        let style = widget.style_context();
        let style_text = Color::from_rgba(&style.color());
        let text = lookup_theme_color(
            &style,
            &[
                "window_fg_color",
                "view_fg_color",
                "card_fg_color",
                "theme_fg_color",
                "theme_text_color",
            ],
        )
        .unwrap_or(style_text);
        let fallback_bg = if text.luminance() > 0.5 {
            Color::hex(0x101010)
        } else {
            Color::hex(0xf5f5f5)
        };
        let bg = lookup_theme_color(
            &style,
            &[
                "window_bg_color",
                "view_bg_color",
                "theme_bg_color",
                "theme_base_color",
            ],
        )
        .unwrap_or(fallback_bg);
        let accent = lookup_theme_color(
            &style,
            &[
                "accent_bg_color",
                "accent_color",
                "blue_3",
                "theme_selected_bg_color",
                "theme_unfocused_selected_bg_color",
            ],
        )
        .unwrap_or_else(|| bg.mix(text, 0.52));
        let layer = lookup_theme_color(&style, &["success_bg_color", "success_color", "green_3"])
            .unwrap_or_else(|| accent.mix(text, 0.20));
        let key = lookup_theme_color(
            &style,
            &["card_bg_color", "popover_bg_color", "headerbar_bg_color"],
        )
        .unwrap_or_else(|| bg.mix(text, 0.34));
        let key_dim = lookup_theme_color(
            &style,
            &[
                "sidebar_bg_color",
                "headerbar_bg_color",
                "scrollbar_outline_color",
            ],
        )
        .unwrap_or_else(|| bg.mix(text, 0.18));
        let outline = lookup_theme_color(
            &style,
            &[
                "scrollbar_outline_color",
                "headerbar_border_color",
                "borders",
            ],
        )
        .unwrap_or(accent);
        let muted = lookup_theme_color(
            &style,
            &[
                "headerbar_fg_color",
                "sidebar_fg_color",
                "insensitive_fg_color",
            ],
        )
        .map(|color| color.mix(bg, 0.38))
        .unwrap_or_else(|| text.mix(bg, 0.48));

        let inverse_text = lookup_theme_color(
            &style,
            &[
                "accent_fg_color",
                "success_fg_color",
                "theme_selected_fg_color",
            ],
        )
        .unwrap_or_else(|| {
            if accent.luminance() > 0.55 {
                Color::hex(0x080808)
            } else {
                Color::hex(0xf7f7f7)
            }
        });

        Self {
            text,
            muted,
            key,
            key_dim,
            accent,
            layer,
            outline,
            inverse_text,
        }
    }
}

fn lookup_theme_color(style: &gtk::StyleContext, names: &[&str]) -> Option<Color> {
    names.iter().find_map(|name| {
        style
            .lookup_color(name)
            .map(|color| Color::from_rgba(&color))
    })
}

#[derive(Clone, Copy)]
struct KeyGeometry {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    rotation: f64,
}

impl KeyGeometry {
    const fn rotated(x: f64, y: f64, width: f64, height: f64, rotation: f64) -> Self {
        Self {
            x,
            y,
            width,
            height,
            rotation,
        }
    }

    fn from_qmk_key(key: QmkKey) -> Self {
        let mut x = key.x + key.w / 2.0;
        let mut y = key.y + key.h / 2.0;
        if key.r != 0.0 {
            if let (Some(rx), Some(ry)) = (key.rx, key.ry) {
                let rotation = key.r.to_radians();
                let dx = x - rx;
                let dy = y - ry;
                x = rx + dx * rotation.cos() - dy * rotation.sin();
                y = ry + dx * rotation.sin() + dy * rotation.cos();
            }
        }
        Self::rotated(x, y, key.w, key.h, key.r)
    }

    fn x_axis_half_extent(self) -> f64 {
        let rotation = self.rotation.to_radians();
        (self.width * rotation.cos().abs() + self.height * rotation.sin().abs()) / 2.0
    }

    fn y_axis_half_extent(self) -> f64 {
        let rotation = self.rotation.to_radians();
        (self.width * rotation.sin().abs() + self.height * rotation.cos().abs()) / 2.0
    }
}

#[derive(Clone, Copy)]
struct LayoutMetrics {
    origin_x: f64,
    origin_y: f64,
    scale: f64,
}

#[derive(Clone)]
struct Args {
    vid: String,
    pid: String,
    path: Option<PathBuf>,
    keymap_path: PathBuf,
    info_path: PathBuf,
    simulate_layer: Option<u8>,
    control_command: Option<ControlCommand>,
    hidden: bool,
}

#[derive(Clone)]
enum ControlCommand {
    Activity,
    Hide,
    Place { monitor: String, left_margin: i32 },
    RefreshPlacement,
}

impl ControlCommand {
    fn message(&self) -> String {
        match self {
            Self::Activity => "activity".to_string(),
            Self::Hide => "hide".to_string(),
            Self::Place {
                monitor,
                left_margin,
            } => format!("place {monitor} {left_margin}"),
            Self::RefreshPlacement => "refresh-placement".to_string(),
        }
    }
}

#[derive(Clone)]
struct EventSink {
    tx: Sender<AppEvent>,
}

enum AppEvent {
    Layer(u8),
    PressedKeys { layer: u8, keys: Vec<u8> },
    Activity,
    Hide,
    Place { monitor: String, left_margin: i32 },
    RefreshPlacement,
    Monitor(String),
    Submap(String),
}

struct UiState {
    _hold: gtk::gio::ApplicationHoldGuard,
    window: ApplicationWindow,
    drawing_area: DrawingArea,
    layout: KeyboardLayout,
    layers: Vec<KeyLayer>,
    current_layer: usize,
    pressed_keys: Vec<u8>,
    visible: bool,
    auto_hide_enabled: bool,
    hide_after: Option<Instant>,
    suppressed_by_submap: bool,
}

#[derive(Debug, PartialEq, Eq)]
enum AutoHideDeadlineAction {
    Unchanged,
    Clear,
    Schedule,
}

#[derive(Deserialize)]
struct HyprMonitor {
    #[serde(default)]
    name: String,
    #[serde(default)]
    id: Option<i64>,
    #[serde(default)]
    focused: bool,
    #[serde(default)]
    x: f64,
    #[serde(default)]
    y: f64,
    #[serde(default)]
    width: f64,
    #[serde(default)]
    height: f64,
    #[serde(default)]
    scale: f64,
    #[serde(default, rename = "activeWorkspace")]
    active_workspace: HyprWorkspace,
    #[serde(default, rename = "specialWorkspace")]
    special_workspace: HyprWorkspace,
}

#[derive(Clone, Default, Deserialize)]
struct HyprWorkspace {
    id: Option<i64>,
}

#[derive(Clone, Deserialize)]
#[serde(untagged)]
enum HyprMonitorRef {
    Id(i64),
    Name(String),
}

#[derive(Clone, Default, Deserialize)]
struct HyprClient {
    #[serde(default)]
    address: String,
    mapped: Option<bool>,
    hidden: Option<bool>,
    monitor: Option<HyprMonitorRef>,
    #[serde(default)]
    workspace: HyprWorkspace,
    at: Option<[f64; 2]>,
    size: Option<[f64; 2]>,
}

#[derive(Default, Deserialize)]
struct HyprGapsOption {
    #[serde(default)]
    css: String,
}

fn main() -> Result<()> {
    let args = parse_args()?;
    if let Some(command) = &args.control_command {
        let message = if matches!(command, ControlCommand::Activity) && activity_is_suppressed_now()
        {
            "hide".to_string()
        } else {
            command.message()
        };
        if send_control(&message).is_ok() {
            return Ok(());
        }
        if matches!(command, ControlCommand::Hide | ControlCommand::Place { .. }) {
            return Ok(());
        }
    } else if send_control(if activity_is_suppressed_now() {
        "hide"
    } else {
        "activity"
    })
    .is_ok()
    {
        return Ok(());
    }

    let layout = load_layout(&args.info_path)?;
    let layers = load_layers(&args.keymap_path, layout.keys.len())?;
    let initial_layer = clamp_layer(args.simulate_layer.unwrap_or(0) as usize, &layers);
    let (tx, rx) = mpsc::channel();
    let sink = EventSink { tx };
    let _socket_guard = start_control_socket(sink.clone())?;
    watch_hyprland_monitors(sink.clone());
    if matches!(args.control_command, Some(ControlCommand::Activity)) {
        sink.send(AppEvent::Activity);
    }

    if let Some(layer) = args.simulate_layer {
        sink.send(AppEvent::Layer(layer));
    } else {
        let hid_args = args.clone();
        let hid_sink = sink.clone();
        let key_report_bytes = key_report_bytes(layout.keys.len());
        thread::spawn(move || watch_layer_devices(hid_args, hid_sink, key_report_bytes));
    }

    let rx = Rc::new(RefCell::new(Some(rx)));
    let app = Application::builder().application_id(APP_ID).build();
    app.connect_activate(move |app| {
        let rx = rx
            .borrow_mut()
            .take()
            .expect("application activated more than once");
        build_ui(
            app,
            rx,
            layout.clone(),
            layers.clone(),
            initial_layer,
            !args.hidden,
        );
    });
    app.run_with_args(&["silakka54-layer-viewer"]);
    Ok(())
}

fn parse_args() -> Result<Args> {
    let mut args = std::env::args().skip(1);
    let mut parsed = Args {
        vid: DEFAULT_VID.to_string(),
        pid: DEFAULT_PID.to_string(),
        path: None,
        keymap_path: packaged_keymap_path(),
        info_path: packaged_info_path(),
        simulate_layer: None,
        control_command: None,
        hidden: true,
    };

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--vid" => {
                parsed.vid = normalize_hex_arg(&next_arg(&mut args, "--vid")?);
            }
            "--pid" => {
                parsed.pid = normalize_hex_arg(&next_arg(&mut args, "--pid")?);
            }
            "--path" => {
                parsed.path = Some(PathBuf::from(next_arg(&mut args, "--path")?));
            }
            "--keymap" => {
                parsed.keymap_path = PathBuf::from(next_arg(&mut args, "--keymap")?);
            }
            "--info" => {
                parsed.info_path = PathBuf::from(next_arg(&mut args, "--info")?);
            }
            "--simulate-layer" => {
                parsed.simulate_layer = Some(
                    next_arg(&mut args, "--simulate-layer")?
                        .parse()
                        .context("--simulate-layer must be an integer")?,
                );
            }
            "--activity" => {
                parsed.control_command = Some(ControlCommand::Activity);
            }
            "--hide" => {
                parsed.control_command = Some(ControlCommand::Hide);
            }
            "--place" => {
                let monitor = next_arg(&mut args, "--place")?;
                let left_margin = next_arg(&mut args, "--place")?
                    .parse()
                    .context("--place LEFT_MARGIN must be an integer")?;
                parsed.control_command = Some(ControlCommand::Place {
                    monitor,
                    left_margin,
                });
            }
            "--refresh-placement" => {
                parsed.control_command = Some(ControlCommand::RefreshPlacement);
            }
            "--hidden" => {
                parsed.hidden = true;
            }
            "--help" | "-h" => {
                println!(
                    "Usage: silakka54-layer-viewer [--activity] [--hide] [--place MONITOR LEFT_MARGIN] [--refresh-placement] [--hidden] [--vid 0xfeed] [--pid 0x1212] [--path /dev/hidrawN] [--keymap keymap.yaml] [--info info.json] [--simulate-layer N]"
                );
                std::process::exit(0);
            }
            other => bail!("unknown argument: {other}"),
        }
    }

    if parsed.control_command.is_none() && parsed.simulate_layer.is_some() {
        parsed.hidden = false;
    }

    Ok(parsed)
}

fn next_arg(args: &mut impl Iterator<Item = String>, option: &str) -> Result<String> {
    args.next()
        .with_context(|| format!("{option} requires a value"))
}

fn packaged_keymap_path() -> PathBuf {
    if let Some(path) = std::env::var_os("SILAKKA54_KEYMAP") {
        return PathBuf::from(path);
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(prefix) = exe.parent().and_then(Path::parent) {
            return prefix.join("share/silakka54/keymap/keymap.yaml");
        }
    }
    PathBuf::from("/run/current-system/sw/share/silakka54/keymap/keymap.yaml")
}

fn packaged_info_path() -> PathBuf {
    if let Some(path) = std::env::var_os("SILAKKA54_INFO_JSON") {
        return PathBuf::from(path);
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(prefix) = exe.parent().and_then(Path::parent) {
            return prefix.join("share/silakka54/keymap/info.json");
        }
    }
    PathBuf::from("/run/current-system/sw/share/silakka54/keymap/info.json")
}

fn normalize_hex_arg(value: &str) -> String {
    let trimmed = value.trim_start_matches("0x").trim_start_matches("0X");
    format!("{:0>4}", trimmed.to_ascii_lowercase())
}

fn build_ui(
    app: &Application,
    rx: Receiver<AppEvent>,
    layout: KeyboardLayout,
    layers: Vec<KeyLayer>,
    current_layer: usize,
    visible: bool,
) {
    let hold = app.hold();
    let provider = gtk::CssProvider::new();
    provider.load_from_data(CSS);
    if let Some(display) = gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Silakka54 Layer Viewer")
        .default_width(WINDOW_WIDTH)
        .default_height(WINDOW_HEIGHT)
        .decorated(false)
        .resizable(false)
        .focusable(false)
        .build();
    window.set_default_size(WINDOW_WIDTH, WINDOW_HEIGHT);
    window.set_size_request(WINDOW_WIDTH, WINDOW_HEIGHT);
    window.init_layer_shell();
    window.set_namespace(Some("silakka54-layer-viewer"));
    window.set_layer(ShellLayer::Overlay);
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_exclusive_zone(0);
    window.set_anchor(Edge::Bottom, true);
    window.set_margin(Edge::Bottom, BOTTOM_MARGIN);
    window.set_can_focus(false);
    window.set_can_target(false);

    let drawing_area = DrawingArea::builder()
        .content_width(WINDOW_WIDTH)
        .content_height(WINDOW_HEIGHT)
        .width_request(WINDOW_WIDTH)
        .height_request(WINDOW_HEIGHT)
        .can_target(false)
        .build();

    window.set_child(Some(&drawing_area));

    let state = Rc::new(RefCell::new(UiState {
        _hold: hold,
        window: window.clone(),
        drawing_area: drawing_area.clone(),
        pressed_keys: vec![0; key_report_bytes(layout.keys.len())],
        layout,
        layers,
        current_layer,
        visible,
        auto_hide_enabled: false,
        hide_after: None,
        suppressed_by_submap: current_hyprland_submap()
            .is_some_and(|submap| submap_suppresses_activity(&submap)),
    }));

    {
        let state = Rc::clone(&state);
        drawing_area.set_draw_func(move |area, cr, width, height| {
            draw_keyboard(&state.borrow(), area, cr, width as f64, height as f64);
        });
    }

    if current_layer_placement()
        .map(|(monitor, left_margin)| {
            set_layer_placement(&window, &monitor, left_margin);
        })
        .is_none()
    {
        if let Some(name) = focused_hyprland_monitor() {
            set_layer_monitor(&window, &name);
        } else {
            set_first_monitor(&window);
        }
    }

    {
        let state = Rc::clone(&state);
        glib::timeout_add_local(Duration::from_millis(25), move || {
            while let Ok(event) = rx.try_recv() {
                handle_event(&state, event);
            }
            let mut state = state.borrow_mut();
            if state
                .hide_after
                .is_some_and(|deadline| Instant::now() >= deadline)
            {
                hide_state(&mut state);
            }
            glib::ControlFlow::Continue
        });
    }

    if visible {
        window.present();
    }
}

fn handle_event(state: &Rc<RefCell<UiState>>, event: AppEvent) {
    match event {
        AppEvent::Layer(layer) => set_layer(&mut state.borrow_mut(), layer),
        AppEvent::PressedKeys { layer, keys } => {
            set_pressed_keys(&mut state.borrow_mut(), layer, keys)
        }
        AppEvent::Activity => activity_state(&mut state.borrow_mut()),
        AppEvent::Hide => hide_state(&mut state.borrow_mut()),
        AppEvent::Place {
            monitor,
            left_margin,
        } => {
            let state = state.borrow();
            set_layer_placement(&state.window, &monitor, left_margin);
        }
        AppEvent::RefreshPlacement => {
            let state = state.borrow();
            refresh_layer_placement(&state.window);
        }
        AppEvent::Monitor(name) => {
            let state = state.borrow();
            set_layer_monitor(&state.window, &name);
        }
        AppEvent::Submap(submap) => {
            let mut state = state.borrow_mut();
            state.suppressed_by_submap = submap_suppresses_activity(&submap);
            if state.suppressed_by_submap {
                hide_state(&mut state);
            }
        }
    }
}

fn activity_state(state: &mut UiState) {
    refresh_submap_suppression(state);
    if state.suppressed_by_submap {
        hide_state(state);
        return;
    }
    show_state(state);
    state.auto_hide_enabled = true;
    update_auto_hide_deadline(state);
}

fn show_state(state: &mut UiState) {
    if !state.visible {
        state.window.present();
        state.visible = true;
    }
}

fn hide_state(state: &mut UiState) {
    state.hide_after = None;
    state.auto_hide_enabled = false;
    if state.visible {
        state.window.hide();
        state.visible = false;
    }
}

fn set_layer(state: &mut UiState, layer: u8) {
    let layer = clamp_layer(layer as usize, &state.layers);
    if layer == state.current_layer {
        return;
    }
    state.current_layer = layer;
    state.pressed_keys = vec![0; key_report_bytes(state.layout.keys.len())];
    update_auto_hide_deadline(state);
    state.drawing_area.queue_draw();
}

fn set_pressed_keys(state: &mut UiState, layer: u8, keys: Vec<u8>) {
    let pressed_count = pressed_key_count(&keys, state.layout.keys.len());
    state.current_layer = clamp_layer(layer as usize, &state.layers);
    state.pressed_keys = keys;
    if pressed_count > 0 {
        refresh_submap_suppression(state);
    }
    if should_open_from_pressed_keys(state.suppressed_by_submap, pressed_count) {
        show_state(state);
        state.auto_hide_enabled = true;
    }
    update_auto_hide_deadline(state);
    state.drawing_area.queue_draw();
}

fn update_auto_hide_deadline(state: &mut UiState) {
    match auto_hide_deadline_action(
        state.auto_hide_enabled,
        state.visible,
        pressed_key_count(&state.pressed_keys, state.layout.keys.len()),
    ) {
        AutoHideDeadlineAction::Unchanged => {}
        AutoHideDeadlineAction::Clear => state.hide_after = None,
        AutoHideDeadlineAction::Schedule => {
            state.hide_after = Some(Instant::now() + AUTO_HIDE_DURATION);
        }
    }
}

fn auto_hide_deadline_action(
    auto_hide_enabled: bool,
    visible: bool,
    pressed_count: usize,
) -> AutoHideDeadlineAction {
    if !auto_hide_enabled {
        AutoHideDeadlineAction::Unchanged
    } else if pressed_count > 0 {
        AutoHideDeadlineAction::Clear
    } else if visible {
        AutoHideDeadlineAction::Schedule
    } else {
        AutoHideDeadlineAction::Unchanged
    }
}

fn should_open_from_pressed_keys(suppressed_by_submap: bool, pressed_count: usize) -> bool {
    !suppressed_by_submap && pressed_count > 0
}

fn submap_suppresses_activity(submap: &str) -> bool {
    submap == SUPPRESSED_SUBMAP
}

fn activity_is_suppressed_now() -> bool {
    current_hyprland_submap().is_some_and(|submap| submap_suppresses_activity(&submap))
}

fn refresh_submap_suppression(state: &mut UiState) {
    if let Some(submap) = current_hyprland_submap() {
        state.suppressed_by_submap = submap_suppresses_activity(&submap);
    }
}

fn load_layout(path: &Path) -> Result<KeyboardLayout> {
    let text =
        fs::read_to_string(path).with_context(|| format!("could not read {}", path.display()))?;
    parse_layout_json(&text).with_context(|| format!("could not parse {}", path.display()))
}

fn parse_layout_json(text: &str) -> Result<KeyboardLayout> {
    let info: QmkInfo = serde_json::from_str(text)?;
    let layout = info
        .layouts
        .get("LAYOUT")
        .context("info.json does not contain layouts.LAYOUT")?;
    if layout.layout.is_empty() {
        bail!("info.json does not define any keys in layouts.LAYOUT");
    }

    let keys = layout
        .layout
        .iter()
        .map(|key| {
            KeyGeometry::from_qmk_key(QmkKey {
                x: key.x,
                y: key.y,
                w: key.w,
                h: key.h,
                r: key.r,
                rx: key.rx,
                ry: key.ry,
            })
        })
        .collect::<Vec<_>>();
    let bounds = layout_bounds(&keys);
    Ok(KeyboardLayout { keys, bounds })
}

fn layout_bounds(keys: &[KeyGeometry]) -> LayoutBounds {
    let mut min_x = f64::INFINITY;
    let mut min_y = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut max_y = f64::NEG_INFINITY;
    for key in keys {
        let half_width = key.x_axis_half_extent();
        let half_height = key.y_axis_half_extent();
        min_x = min_x.min(key.x - half_width);
        min_y = min_y.min(key.y - half_height);
        max_x = max_x.max(key.x + half_width);
        max_y = max_y.max(key.y + half_height);
    }
    LayoutBounds {
        min_x,
        min_y,
        width: max_x - min_x,
        height: max_y - min_y,
    }
}

fn load_layers(path: &Path, key_count: usize) -> Result<Vec<KeyLayer>> {
    let text =
        fs::read_to_string(path).with_context(|| format!("could not read {}", path.display()))?;
    let root: YamlValue = serde_yaml::from_str(&text)
        .with_context(|| format!("could not parse {}", path.display()))?;
    let layers = root
        .get("layers")
        .and_then(YamlValue::as_mapping)
        .with_context(|| format!("{} does not contain a layers mapping", path.display()))?;

    let mut output = Vec::new();
    for (name, keys) in layers {
        let name = scalar_to_string(name).context("layer name must be a scalar")?;
        let keys = keys
            .as_sequence()
            .with_context(|| format!("layer {name} must be a sequence"))?
            .iter()
            .map(|value| scalar_to_string(value).context("key label must be a scalar"))
            .collect::<Result<Vec<_>>>()?;
        if keys.len() != key_count {
            bail!("layer {name} has {} keys, expected {key_count}", keys.len());
        }
        output.push(KeyLayer { name, keys });
    }

    if output.is_empty() {
        bail!("{} does not define any layers", path.display());
    }
    Ok(output)
}

fn scalar_to_string(value: &YamlValue) -> Result<String> {
    match value {
        YamlValue::String(value) => Ok(value.clone()),
        YamlValue::Number(value) => Ok(value.to_string()),
        YamlValue::Bool(value) => Ok(value.to_string()),
        YamlValue::Null => Ok(String::new()),
        _ => bail!("expected scalar"),
    }
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
            contents
                .to_ascii_lowercase()
                .contains(&needle)
                .then(|| PathBuf::from("/dev").join(name.as_ref()))
        })
        .collect()
}

fn watch_layer_devices(args: Args, sink: EventSink, key_report_bytes: usize) {
    let active_paths = Arc::new(Mutex::new(HashSet::new()));
    loop {
        for path in hidraw_paths(&args) {
            let mut active = active_paths
                .lock()
                .expect("active hidraw path set poisoned");
            if !active.insert(path.clone()) {
                continue;
            }
            drop(active);

            let reader_sink = sink.clone();
            let reader_active_paths = Arc::clone(&active_paths);
            thread::spawn(move || {
                read_layer_path(&path, reader_sink, key_report_bytes);
                reader_active_paths
                    .lock()
                    .expect("active hidraw path set poisoned")
                    .remove(&path);
            });
        }

        thread::sleep(Duration::from_millis(250));
    }
}

fn read_layer_path(path: &Path, sink: EventSink, key_report_bytes: usize) {
    let Ok(mut file) = OpenOptions::new().read(true).open(path) else {
        return;
    };
    let mut buffer = [0u8; 64];
    loop {
        match file.read(&mut buffer) {
            Ok(len) if len > 0 => read_report(&buffer[..len], &sink, key_report_bytes),
            Ok(_) => thread::sleep(Duration::from_millis(1)),
            Err(error) if error.kind() == ErrorKind::Interrupted => {}
            Err(_) => break,
        }
    }
}

fn read_report(buffer: &[u8], sink: &EventSink, key_report_bytes: usize) {
    let report = normalize_report(buffer);
    if report.len() >= 9 && &report[0..7] == LAYER_REPORT_MAGIC && report[7] == 1 {
        sink.send(AppEvent::Layer(report[8]));
    } else if report.len() >= 9 + key_report_bytes
        && &report[0..7] == KEY_REPORT_MAGIC
        && report[7] == 1
    {
        let keys = report[9..9 + key_report_bytes].to_vec();
        sink.send(AppEvent::PressedKeys {
            layer: report[8],
            keys,
        });
    }
}

fn normalize_report(buffer: &[u8]) -> &[u8] {
    if buffer.first() == Some(&0) {
        &buffer[1..]
    } else {
        buffer
    }
}

impl EventSink {
    fn send(&self, event: AppEvent) {
        self.tx.send(event).ok();
    }
}

struct SocketGuard {
    path: PathBuf,
}

impl Drop for SocketGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn control_socket_path() -> Result<PathBuf> {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR").context("XDG_RUNTIME_DIR is not set")?;
    Ok(PathBuf::from(runtime).join("silakka54-layer-viewer.sock"))
}

fn send_control(command: &str) -> Result<()> {
    let path = control_socket_path()?;
    let mut stream = UnixStream::connect(path)?;
    stream.write_all(command.as_bytes())?;
    stream.write_all(b"\n")?;
    Ok(())
}

fn start_control_socket(sink: EventSink) -> Result<SocketGuard> {
    let path = control_socket_path()?;
    if UnixStream::connect(&path).is_ok() {
        bail!("silakka54-layer-viewer is already running");
    }
    match fs::remove_file(&path) {
        Ok(()) => {}
        Err(error) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error).with_context(|| format!("could not remove {}", path.display()))
        }
    }
    let listener =
        UnixListener::bind(&path).with_context(|| format!("could not bind {}", path.display()))?;
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            handle_control_stream(stream, &sink);
        }
    });
    Ok(SocketGuard { path })
}

fn handle_control_stream(mut stream: UnixStream, sink: &EventSink) {
    let mut text = String::new();
    if stream.read_to_string(&mut text).is_err() {
        return;
    }
    for line in text.lines() {
        let mut fields = line.split_whitespace();
        match fields.next() {
            Some("activity") => sink.send(AppEvent::Activity),
            Some("hide") => sink.send(AppEvent::Hide),
            Some("place") => {
                let Some(monitor) = fields.next() else {
                    continue;
                };
                let Some(left_margin) = fields.next().and_then(|value| value.parse().ok()) else {
                    continue;
                };
                sink.send(AppEvent::Place {
                    monitor: monitor.to_string(),
                    left_margin,
                });
            }
            Some("refresh-placement") => sink.send(AppEvent::RefreshPlacement),
            _ => {}
        }
    }
}

fn watch_hyprland_monitors(sink: EventSink) {
    let Some(path) = hyprland_socket2_path() else {
        return;
    };
    thread::spawn(move || loop {
        match UnixStream::connect(&path) {
            Ok(mut stream) => {
                let mut pending = Vec::new();
                let mut buffer = [0u8; 4096];
                loop {
                    match stream.read(&mut buffer) {
                        Ok(0) => break,
                        Ok(len) => {
                            pending.extend_from_slice(&buffer[..len]);
                            while let Some(pos) = pending.iter().position(|byte| *byte == b'\n') {
                                let line = pending.drain(..=pos).collect::<Vec<_>>();
                                if let Ok(line) = String::from_utf8(line) {
                                    handle_hyprland_event(line.trim(), &sink);
                                }
                            }
                        }
                        Err(error) if error.kind() == ErrorKind::Interrupted => {}
                        Err(_) => break,
                    }
                }
            }
            Err(_) => thread::sleep(Duration::from_secs(1)),
        }
    });
}

fn hyprland_socket2_path() -> Option<PathBuf> {
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")?;
    let signature = std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")?;
    Some(
        PathBuf::from(runtime)
            .join("hypr")
            .join(signature)
            .join(".socket2.sock"),
    )
}

fn handle_hyprland_event(line: &str, sink: &EventSink) {
    if let Some(rest) = line.strip_prefix("focusedmon>>") {
        if let Some((monitor, _workspace)) = rest.split_once(',') {
            sink.send(AppEvent::Monitor(monitor.to_string()));
        }
    } else if line.starts_with("monitoradded") || line.starts_with("monitorremoved") {
        if let Some(name) = focused_hyprland_monitor() {
            sink.send(AppEvent::Monitor(name));
        }
    } else if let Some(submap) = line.strip_prefix("submap>>") {
        sink.send(AppEvent::Submap(submap.to_string()));
    }
}

fn current_hyprland_submap() -> Option<String> {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return None;
    }
    let output = Command::new("hyprctl").arg("submap").output().ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8(output.stdout)
        .ok()
        .map(|submap| submap.trim().to_string())
}

fn refresh_layer_placement(window: &ApplicationWindow) {
    if let Some((monitor, left_margin)) = current_layer_placement() {
        set_layer_placement(window, &monitor, left_margin);
    } else if let Some(name) = focused_hyprland_monitor() {
        set_layer_monitor(window, &name);
    }
}

fn current_layer_placement() -> Option<(String, i32)> {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return None;
    }

    let monitors: Vec<HyprMonitor> = hyprctl_json(&["monitors", "-j"])?;
    let clients: Vec<HyprClient> = hyprctl_json(&["clients", "-j"])?;
    let active: HyprClient = hyprctl_json(&["activewindow", "-j"]).unwrap_or_default();
    let gaps: HyprGapsOption = hyprctl_json(&["getoption", "general:gaps_in", "-j"])
        .unwrap_or_default();

    compute_layer_placement(&monitors, &clients, &active, &gaps)
}

fn hyprctl_json<T: for<'de> Deserialize<'de>>(args: &[&str]) -> Option<T> {
    let output = Command::new("hyprctl").args(args).output().ok()?;
    if !output.status.success() || output.stdout.is_empty() {
        return None;
    }
    serde_json::from_slice(&output.stdout).ok()
}

fn compute_layer_placement(
    monitors: &[HyprMonitor],
    clients: &[HyprClient],
    active: &HyprClient,
    gaps: &HyprGapsOption,
) -> Option<(String, i32)> {
    let monitor = monitors
        .iter()
        .find(|monitor| monitor.focused)
        .or_else(|| monitors.first())?;
    let monitor_scale = if monitor.scale == 0.0 {
        1.0
    } else {
        monitor.scale
    };
    let monitor_width = monitor.width / monitor_scale;
    let monitor_height = monitor.height / monitor_scale;
    let monitor_center = monitor.x + monitor_width / 2.0;
    let band_top = monitor.y + monitor_height - f64::from(WINDOW_HEIGHT) - f64::from(BOTTOM_MARGIN);
    let band_bottom = monitor.y + monitor_height;
    let fallback_x = monitor.x
        + if monitor_width > f64::from(WINDOW_WIDTH) {
            (monitor_width - f64::from(WINDOW_WIDTH)) / 2.0
        } else {
            0.0
        };
    let workspace_id = placement_workspace_id(monitor, active)?;
    let focused_address = active.address.as_str();
    let gap_margin = configured_gap_margin(gaps);

    let focused_choice = if mapped_visible(active)
        && on_monitor(active, monitor)
        && on_workspace(active, workspace_id)
    {
        Some(PlacementChoice {
            left: place_near_window(
                active,
                monitor.x,
                monitor_width,
                band_top,
                band_bottom,
                gap_margin,
            ),
            distance: 0.0,
        })
    } else {
        None
    };

    let choice = focused_choice.or_else(|| {
        clients
            .iter()
            .filter(|client| mapped_visible(client))
            .filter(|client| on_monitor(client, monitor))
            .filter(|client| on_workspace(client, workspace_id))
            .filter(|client| client.address != focused_address)
            .filter_map(|client| {
                let [window_x, window_y] = client.at?;
                let [window_width, window_height] = client.size?;
                if window_width < f64::from(WINDOW_WIDTH)
                    || window_y + window_height <= band_top
                    || window_y >= band_bottom
                {
                    return None;
                }
                let left_bound = window_x.max(monitor.x);
                let right_bound =
                    (window_x + window_width - f64::from(WINDOW_WIDTH)).min(
                        monitor.x + monitor_width - f64::from(WINDOW_WIDTH),
                    );
                if right_bound < left_bound {
                    return None;
                }
                let left = clamp(
                    monitor_center - f64::from(WINDOW_WIDTH) / 2.0,
                    left_bound,
                    right_bound,
                );
                Some(PlacementChoice {
                    left,
                    distance: (left + f64::from(WINDOW_WIDTH) / 2.0 - monitor_center).abs(),
                })
            })
            .min_by(|left, right| left.distance.total_cmp(&right.distance))
    });

    let left = choice.map_or(fallback_x, |choice| choice.left);
    Some((monitor.name.clone(), (left - monitor.x).floor().max(0.0) as i32))
}

#[derive(Clone, Copy)]
struct PlacementChoice {
    left: f64,
    distance: f64,
}

fn placement_workspace_id(monitor: &HyprMonitor, active: &HyprClient) -> Option<i64> {
    if monitor.special_workspace.id.is_some_and(|id| id != 0) {
        return monitor.special_workspace.id;
    }
    if mapped_visible(active) && on_monitor(active, monitor) {
        return active.workspace.id.or(monitor.active_workspace.id);
    }
    monitor.active_workspace.id
}

fn mapped_visible(client: &HyprClient) -> bool {
    client.mapped.unwrap_or(true) && !client.hidden.unwrap_or(false)
}

fn on_monitor(client: &HyprClient, monitor: &HyprMonitor) -> bool {
    match (&client.monitor, monitor.id) {
        (Some(HyprMonitorRef::Id(client_id)), Some(monitor_id)) => *client_id == monitor_id,
        (Some(HyprMonitorRef::Name(client_name)), _) => client_name == &monitor.name,
        _ => false,
    }
}

fn on_workspace(client: &HyprClient, workspace_id: i64) -> bool {
    client.workspace.id == Some(workspace_id)
}

fn configured_gap_margin(gaps: &HyprGapsOption) -> f64 {
    (gaps
        .css
        .split_whitespace()
        .next()
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(0.0)
        * 0.7)
        .ceil()
}

fn place_near_window(
    client: &HyprClient,
    monitor_x: f64,
    monitor_width: f64,
    band_top: f64,
    band_bottom: f64,
    gap_margin: f64,
) -> f64 {
    let [window_x, window_y] = client.at.unwrap_or([0.0, 0.0]);
    let [window_width, window_height] = client.size.unwrap_or([0.0, 0.0]);
    let min_x = monitor_x;
    let max_x = monitor_x + monitor_width - f64::from(WINDOW_WIDTH);
    let centered_x = window_x + window_width / 2.0 - f64::from(WINDOW_WIDTH) / 2.0;
    let overlaps_band = window_y + window_height > band_top && window_y < band_bottom;

    if max_x < min_x {
        min_x
    } else if !overlaps_band {
        clamp(centered_x, min_x, max_x)
    } else {
        let window_center = window_x + window_width / 2.0;
        [
            window_x - gap_margin - f64::from(WINDOW_WIDTH),
            window_x + window_width + gap_margin,
        ]
        .into_iter()
        .filter(|left| *left >= min_x && *left <= max_x)
        .map(|left| PlacementChoice {
            left,
            distance: (left + f64::from(WINDOW_WIDTH) / 2.0 - window_center).abs(),
        })
        .min_by(|left, right| left.distance.total_cmp(&right.distance))
        .map_or_else(|| clamp(centered_x, min_x, max_x), |choice| choice.left)
    }
}

fn clamp(value: f64, min: f64, max: f64) -> f64 {
    value.max(min).min(max)
}

fn focused_hyprland_monitor() -> Option<String> {
    if std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_none() {
        return None;
    }
    let output = Command::new("hyprctl")
        .args(["monitors", "-j"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let monitors: Vec<HyprMonitor> = serde_json::from_slice(&output.stdout).ok()?;
    monitors
        .into_iter()
        .find(|monitor| monitor.focused)
        .map(|monitor| monitor.name)
}

fn set_layer_monitor(window: &ApplicationWindow, name: &str) {
    if let Some(monitor) = find_gdk_monitor(name) {
        window.set_monitor(Some(&monitor));
    }
}

fn set_layer_placement(window: &ApplicationWindow, monitor_name: &str, left_margin: i32) {
    set_layer_monitor(window, monitor_name);
    window.set_anchor(Edge::Bottom, true);
    window.set_anchor(Edge::Left, true);
    window.set_anchor(Edge::Right, false);
    window.set_margin(Edge::Left, left_margin.max(0));
}

fn set_first_monitor(window: &ApplicationWindow) {
    if let Some(display) = gdk::Display::default() {
        let monitors = display.monitors();
        if let Some(item) = monitors.item(0) {
            if let Ok(monitor) = item.downcast::<gdk::Monitor>() {
                window.set_monitor(Some(&monitor));
            }
        }
    }
}

fn find_gdk_monitor(name: &str) -> Option<gdk::Monitor> {
    let display = gdk::Display::default()?;
    let monitors = display.monitors();
    for index in 0..monitors.n_items() {
        let item = monitors.item(index)?;
        let monitor = item.downcast::<gdk::Monitor>().ok()?;
        if monitor
            .connector()
            .as_deref()
            .is_some_and(|connector| connector == name)
        {
            return Some(monitor);
        }
    }
    None
}

fn clamp_layer(layer: usize, layers: &[KeyLayer]) -> usize {
    if layer < layers.len() {
        layer
    } else {
        0
    }
}

fn draw_keyboard(state: &UiState, area: &DrawingArea, cr: &CairoContext, width: f64, height: f64) {
    cr.save().ok();
    cr.set_operator(Operator::Clear);
    cr.paint().ok();
    cr.restore().ok();

    let metrics = layout_metrics(width, height, state.layout.bounds);
    let palette = ThemePalette::from_widget(area);
    let layer = &state.layers[state.current_layer];
    let layer_names = state
        .layers
        .iter()
        .map(|layer| layer.name.as_str())
        .collect::<Vec<_>>();
    for (index, geometry) in state.layout.keys.iter().enumerate() {
        draw_key(
            cr,
            &metrics,
            index,
            geometry,
            &layer.keys[index],
            key_is_pressed(state, index),
            &layer_names,
            &palette,
        );
    }
}

fn layout_metrics(width: f64, height: f64, bounds: LayoutBounds) -> LayoutMetrics {
    let scale = (width / bounds.width).min(height / bounds.height).max(0.05);
    let origin_x = (width - bounds.width * scale) / 2.0 - bounds.min_x * scale;
    let origin_y = (height - bounds.height * scale) / 2.0 - bounds.min_y * scale;
    LayoutMetrics {
        origin_x,
        origin_y,
        scale,
    }
}

fn draw_key(
    cr: &CairoContext,
    metrics: &LayoutMetrics,
    index: usize,
    geometry: &KeyGeometry,
    label: &str,
    pressed: bool,
    layer_names: &[&str],
    palette: &ThemePalette,
) {
    let key_width = geometry.width * metrics.scale;
    let key_height = geometry.height * metrics.scale;
    let key_size = key_width.min(key_height);
    let radius = key_width.min(key_height) * 0.13;
    cr.save().ok();
    cr.translate(
        metrics.origin_x + geometry.x * metrics.scale,
        metrics.origin_y + geometry.y * metrics.scale,
    );
    cr.rotate(geometry.rotation.to_radians());
    rounded_rect(
        cr,
        -key_width / 2.0,
        -key_height / 2.0,
        key_width,
        key_height,
        radius,
    );
    if pressed {
        set_rgba(cr, palette.accent, 0.98 * KEY_FILL_OPACITY);
    } else if is_layer_label(label, layer_names) {
        set_rgba(cr, palette.layer, 0.92 * KEY_FILL_OPACITY);
    } else if label == "___" {
        set_rgba(cr, palette.key_dim, 0.78 * KEY_FILL_OPACITY);
    } else {
        set_rgba(cr, palette.key, 0.90 * KEY_FILL_OPACITY);
    }
    cr.fill_preserve().ok();
    if pressed {
        set_rgba(cr, palette.accent, OVERLAY_OPACITY);
        cr.set_line_width(key_size * 0.038);
    } else {
        set_rgba(cr, palette.outline, 0.62 * OVERLAY_OPACITY);
        cr.set_line_width(key_size * 0.020);
    }
    cr.stroke().ok();

    let text_color = if pressed || is_layer_label(label, layer_names) {
        palette.inverse_text
    } else if label == "___" {
        palette.muted
    } else {
        palette.text
    };
    set_rgba(cr, text_color, 0.92 * OVERLAY_OPACITY);
    draw_centered_text(
        cr,
        label,
        0.0,
        -key_height * 0.04,
        key_width.min(key_height) * 0.25,
        key_width * 0.76,
    );
    set_rgba(cr, text_color, 0.36 * OVERLAY_OPACITY);
    draw_centered_text(
        cr,
        &(index + 1).to_string(),
        0.0,
        key_height * 0.31,
        key_width.min(key_height) * 0.11,
        key_width * 0.70,
    );
    cr.restore().ok();
}

fn draw_centered_text(
    cr: &CairoContext,
    text: &str,
    center_x: f64,
    center_y: f64,
    font_size: f64,
    max_width: f64,
) {
    let mut display = text.to_string();
    let mut size = font_size;
    loop {
        cr.select_font_face("Sans", FontSlant::Normal, FontWeight::Bold);
        cr.set_font_size(size);
        let Ok(extents) = cr.text_extents(&display) else {
            return;
        };
        if extents.width() <= max_width || size <= font_size * 0.62 {
            cr.move_to(
                center_x - extents.width() / 2.0 - extents.x_bearing(),
                center_y + extents.height() / 2.0,
            );
            cr.show_text(&display).ok();
            return;
        }
        if display.chars().count() > 8 {
            display = format!("{}.", display.chars().take(7).collect::<String>());
        } else {
            size *= 0.92;
        }
    }
}

fn rounded_rect(cr: &CairoContext, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let pi = std::f64::consts::PI;
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -pi / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, pi / 2.0);
    cr.arc(x + r, y + h - r, r, pi / 2.0, pi);
    cr.arc(x + r, y + r, r, pi, 3.0 * pi / 2.0);
    cr.close_path();
}

fn set_rgba(cr: &CairoContext, color: Color, alpha: f64) {
    cr.set_source_rgba(color.red, color.green, color.blue, alpha);
}

fn is_layer_label(label: &str, layer_names: &[&str]) -> bool {
    layer_names.contains(&label)
}

fn key_is_pressed(state: &UiState, index: usize) -> bool {
    index < state.layout.keys.len()
        && index / 8 < state.pressed_keys.len()
        && (state.pressed_keys[index / 8] & (1 << (index % 8))) != 0
}

fn pressed_key_count(keys: &[u8], key_count: usize) -> usize {
    (0..key_count)
        .filter(|index| {
            keys.get(index / 8)
                .is_some_and(|byte| byte & (1 << (index % 8)) != 0)
        })
        .count()
}

fn key_report_bytes(key_count: usize) -> usize {
    (key_count + 7) / 8
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_hide_deadline_clears_while_keys_are_held() {
        assert_eq!(
            auto_hide_deadline_action(true, true, 1),
            AutoHideDeadlineAction::Clear
        );
    }

    #[test]
    fn auto_hide_deadline_schedules_after_all_keys_release() {
        assert_eq!(
            auto_hide_deadline_action(true, true, 0),
            AutoHideDeadlineAction::Schedule
        );
    }

    #[test]
    fn auto_hide_deadline_ignores_inactive_auto_hide() {
        assert_eq!(
            auto_hide_deadline_action(false, true, 0),
            AutoHideDeadlineAction::Unchanged
        );
        assert_eq!(
            auto_hide_deadline_action(false, true, 1),
            AutoHideDeadlineAction::Unchanged
        );
    }

    #[test]
    fn pressed_keys_open_when_not_suppressed() {
        assert!(should_open_from_pressed_keys(false, 1));
    }

    #[test]
    fn pressed_keys_do_not_open_while_suppressed() {
        assert!(!should_open_from_pressed_keys(true, 1));
    }

    #[test]
    fn empty_pressed_key_reports_do_not_open() {
        assert!(!should_open_from_pressed_keys(false, 0));
    }

    #[test]
    fn only_game_submap_suppresses_activity() {
        assert!(submap_suppresses_activity("game"));
        assert!(!submap_suppresses_activity("default"));
        assert!(!submap_suppresses_activity(""));
    }

    #[test]
    fn inner_thumb_gap_is_about_half_a_key_width() {
        let layout = parse_layout_json(
            r#"{
              "layouts": {
                "LAYOUT": {
                  "layout": [
                    { "x": 6.0062, "y": 4.6884, "w": 1.0205, "h": 1.5, "r": 20 },
                    { "x": 7.976, "y": 4.6884, "w": 1.0205, "h": 1.5, "r": -20 }
                  ]
                }
              }
            }"#,
        )
        .expect("test layout parses");
        let left_inner_thumb = layout.keys[0];
        let right_inner_thumb = layout.keys[1];
        let gap = right_inner_thumb.x
            - right_inner_thumb.x_axis_half_extent()
            - left_inner_thumb.x
            - left_inner_thumb.x_axis_half_extent();
        let key_widths = gap;

        assert!((key_widths - 0.5).abs() < 0.02);
    }
}
