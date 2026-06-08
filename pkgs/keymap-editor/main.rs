use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::{c_char, c_double, c_int, c_uint, c_ulong, c_void};
use std::path::{Path, PathBuf};

const DEFAULT_KEYMAP: &str = "@default_keymap@";
const KEY_COUNT: usize = 54;
const GTK_WINDOW_TOPLEVEL: c_int = 0;
const GTK_ORIENTATION_HORIZONTAL: c_int = 0;
const GTK_ORIENTATION_VERTICAL: c_int = 1;
const TRUE: c_int = 1;
const FALSE: c_int = 0;
const GDK_BUTTON_PRESS_MASK: c_int = 1 << 8;
const GDK_KEY_PRESS_MASK: c_int = 1 << 10;
const GTK_STYLE_PROVIDER_PRIORITY_APPLICATION: c_uint = 600;
const REF_WIDTH: f64 = 1209.0;
const REF_HEIGHT: f64 = 529.0;

const QUICK_LABELS: &[&str] = &[
    "___", "Esc", "Tab", "Bspc", "Space", "Enter", "Shift", "Ctrl", "GUI", "Num", "Nav", "Sym",
    "Boot",
];

const KEY_GEOMETRY: [KeyGeometry; KEY_COUNT] = [
    KeyGeometry::square(53.5, 82.5),
    KeyGeometry::square(132.5, 82.5),
    KeyGeometry::square(211.5, 72.5),
    KeyGeometry::square(290.0, 62.5),
    KeyGeometry::square(368.5, 72.5),
    KeyGeometry::square(447.5, 82.5),
    KeyGeometry::square(754.5, 82.5),
    KeyGeometry::square(833.0, 72.5),
    KeyGeometry::square(911.5, 62.5),
    KeyGeometry::square(990.5, 72.5),
    KeyGeometry::square(1069.5, 82.5),
    KeyGeometry::square(1148.5, 82.5),
    KeyGeometry::square(53.5, 161.5),
    KeyGeometry::square(132.5, 161.5),
    KeyGeometry::square(211.5, 151.5),
    KeyGeometry::square(290.0, 141.5),
    KeyGeometry::square(368.5, 151.5),
    KeyGeometry::square(447.5, 161.5),
    KeyGeometry::square(754.5, 161.5),
    KeyGeometry::square(833.0, 151.5),
    KeyGeometry::square(912.5, 141.5),
    KeyGeometry::square(990.5, 151.5),
    KeyGeometry::square(1069.5, 161.5),
    KeyGeometry::square(1148.5, 161.5),
    KeyGeometry::square(53.5, 240.5),
    KeyGeometry::square(132.5, 240.5),
    KeyGeometry::square(211.5, 230.5),
    KeyGeometry::square(290.0, 220.5),
    KeyGeometry::square(368.5, 230.5),
    KeyGeometry::square(447.5, 240.5),
    KeyGeometry::square(754.5, 240.5),
    KeyGeometry::square(833.0, 230.5),
    KeyGeometry::square(912.5, 220.5),
    KeyGeometry::square(990.5, 230.5),
    KeyGeometry::square(1069.5, 240.5),
    KeyGeometry::square(1148.5, 240.5),
    KeyGeometry::square(53.5, 319.0),
    KeyGeometry::square(132.5, 319.0),
    KeyGeometry::square(211.5, 309.5),
    KeyGeometry::square(290.0, 298.5),
    KeyGeometry::square(368.5, 309.5),
    KeyGeometry::square(447.5, 319.0),
    KeyGeometry::square(754.5, 319.0),
    KeyGeometry::square(833.0, 309.5),
    KeyGeometry::square(912.5, 298.5),
    KeyGeometry::square(990.5, 309.5),
    KeyGeometry::square(1069.5, 319.0),
    KeyGeometry::square(1148.5, 319.0),
    KeyGeometry::square(303.5, 396.5),
    KeyGeometry::rotated(398.3, 414.0, 74.0, 74.0, 10.0),
    KeyGeometry::rotated(492.7, 443.0, 74.5, 109.5, 20.0),
    KeyGeometry::rotated(709.0, 443.0, 74.5, 109.5, -20.0),
    KeyGeometry::rotated(803.4, 413.7, 74.0, 74.0, -10.0),
    KeyGeometry::square(897.5, 396.5),
];

const ALIASES: &[&str] = &[
    "___", "TRNS", "---", "NO", "Esc", "Tab", "Ctrl", "Shift", "GUI", "Alt", "Space", "Enter",
    "Bspc", "Del", "Ins", "Home", "End", "PgUp", "PgDn", "Left", "Down", "Up", "Right", "Boot",
    "Caps", "Menu", "Mute", "Vol-", "Vol+", "Prev", "Next", "Play", ",", ".", "/", "-", "'", ";",
    "`", "\\", "[", "]", "=", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+", "{", "}",
    "|", ":", "\"", "<", ">", "?", "~",
];

const MOCHA_TEXT: Color = Color::hex(0xcdd6f4);
const MOCHA_OVERLAY0: Color = Color::hex(0x6c7086);
const MOCHA_SURFACE0: Color = Color::hex(0x313244);
const MOCHA_SURFACE1: Color = Color::hex(0x45475a);
const MOCHA_BASE: Color = Color::hex(0x1e1e2e);
const MOCHA_CRUST: Color = Color::hex(0x11111b);
const MOCHA_RED: Color = Color::hex(0xf38ba8);
const MOCHA_YELLOW: Color = Color::hex(0xf9e2af);
const MOCHA_GREEN: Color = Color::hex(0xa6e3a1);
const MOCHA_TEAL: Color = Color::hex(0x94e2d5);

const GTK_CSS: &str = r#"
window {
  background: #1e1e2e;
  color: #cdd6f4;
}
button {
  background: #313244;
  color: #cdd6f4;
  border: 1px solid #585b70;
  border-radius: 7px;
  padding: 6px 10px;
  box-shadow: none;
}
button:hover {
  background: #45475a;
  border-color: #89b4fa;
}
button:active {
  background: #585b70;
}
entry, combobox button {
  background: #181825;
  color: #cdd6f4;
  border: 1px solid #585b70;
  border-radius: 7px;
  padding: 6px;
}
entry:focus {
  border-color: #94e2d5;
}
label {
  color: #cdd6f4;
}
"#;

#[link(name = "gtk-3")]
#[link(name = "gobject-2.0")]
extern "C" {
    fn gtk_init(argc: *mut c_int, argv: *mut *mut *mut c_char);
    fn gtk_window_new(window_type: c_int) -> *mut c_void;
    fn gtk_window_set_title(window: *mut c_void, title: *const c_char);
    fn gtk_window_set_default_size(window: *mut c_void, width: c_int, height: c_int);
    fn gtk_box_new(orientation: c_int, spacing: c_int) -> *mut c_void;
    fn gtk_box_pack_start(
        box_: *mut c_void,
        child: *mut c_void,
        expand: c_int,
        fill: c_int,
        padding: c_uint,
    );
    fn gtk_button_new_with_label(label: *const c_char) -> *mut c_void;
    fn gtk_combo_box_text_new() -> *mut c_void;
    fn gtk_combo_box_text_append_text(combo_box: *mut c_void, text: *const c_char);
    fn gtk_combo_box_text_remove_all(combo_box: *mut c_void);
    fn gtk_combo_box_set_active(combo_box: *mut c_void, index: c_int);
    fn gtk_combo_box_get_active(combo_box: *mut c_void) -> c_int;
    fn gtk_container_add(container: *mut c_void, widget: *mut c_void);
    fn gtk_container_set_border_width(container: *mut c_void, border_width: c_uint);
    fn gtk_css_provider_load_from_data(
        css_provider: *mut c_void,
        data: *const c_char,
        length: isize,
        error: *mut *mut c_void,
    ) -> c_int;
    fn gtk_css_provider_new() -> *mut c_void;
    fn gtk_drawing_area_new() -> *mut c_void;
    fn gtk_entry_new() -> *mut c_void;
    fn gtk_entry_get_text(entry: *mut c_void) -> *const c_char;
    fn gtk_entry_set_text(entry: *mut c_void, text: *const c_char);
    fn gtk_entry_set_width_chars(entry: *mut c_void, n_chars: c_int);
    fn gtk_label_new(text: *const c_char) -> *mut c_void;
    fn gtk_label_set_text(label: *mut c_void, text: *const c_char);
    fn gtk_label_set_xalign(label: *mut c_void, xalign: f32);
    fn gtk_main();
    fn gtk_main_quit();
    fn gtk_widget_add_events(widget: *mut c_void, events: c_int);
    fn gtk_widget_get_allocated_height(widget: *mut c_void) -> c_int;
    fn gtk_widget_get_allocated_width(widget: *mut c_void) -> c_int;
    fn gtk_widget_grab_focus(widget: *mut c_void);
    fn gtk_widget_queue_draw(widget: *mut c_void);
    fn gtk_widget_set_can_focus(widget: *mut c_void, can_focus: c_int);
    fn gtk_widget_set_size_request(widget: *mut c_void, width: c_int, height: c_int);
    fn gtk_widget_show_all(widget: *mut c_void);
    fn gtk_style_context_add_provider_for_screen(
        screen: *mut c_void,
        provider: *mut c_void,
        priority: c_uint,
    );
    fn g_signal_connect_data(
        instance: *mut c_void,
        detailed_signal: *const c_char,
        c_handler: *const c_void,
        data: *mut c_void,
        destroy_data: Option<unsafe extern "C" fn(*mut c_void)>,
        connect_flags: c_int,
    ) -> c_ulong;
}

#[link(name = "gdk-3")]
extern "C" {
    fn gdk_screen_get_default() -> *mut c_void;
    fn gdk_event_get_coords(
        event: *mut c_void,
        x_win: *mut c_double,
        y_win: *mut c_double,
    ) -> c_int;
    fn gdk_event_get_keyval(event: *mut c_void, keyval: *mut c_uint) -> c_int;
}

#[link(name = "cairo")]
extern "C" {
    fn cairo_arc(
        cr: *mut c_void,
        xc: c_double,
        yc: c_double,
        radius: c_double,
        angle1: c_double,
        angle2: c_double,
    );
    fn cairo_close_path(cr: *mut c_void);
    fn cairo_fill(cr: *mut c_void);
    fn cairo_fill_preserve(cr: *mut c_void);
    fn cairo_create(surface: *mut c_void) -> *mut c_void;
    fn cairo_destroy(cr: *mut c_void);
    fn cairo_move_to(cr: *mut c_void, x: c_double, y: c_double);
    fn cairo_new_sub_path(cr: *mut c_void);
    fn cairo_image_surface_create(format: c_int, width: c_int, height: c_int) -> *mut c_void;
    fn cairo_rectangle(
        cr: *mut c_void,
        x: c_double,
        y: c_double,
        width: c_double,
        height: c_double,
    );
    fn cairo_restore(cr: *mut c_void);
    fn cairo_rotate(cr: *mut c_void, angle: c_double);
    fn cairo_save(cr: *mut c_void);
    fn cairo_select_font_face(cr: *mut c_void, family: *const c_char, slant: c_int, weight: c_int);
    fn cairo_set_font_size(cr: *mut c_void, size: c_double);
    fn cairo_set_line_width(cr: *mut c_void, width: c_double);
    fn cairo_set_source_rgb(cr: *mut c_void, red: c_double, green: c_double, blue: c_double);
    fn cairo_set_source_rgba(
        cr: *mut c_void,
        red: c_double,
        green: c_double,
        blue: c_double,
        alpha: c_double,
    );
    fn cairo_show_text(cr: *mut c_void, utf8: *const c_char);
    fn cairo_stroke(cr: *mut c_void);
    fn cairo_surface_destroy(surface: *mut c_void);
    fn cairo_surface_write_to_png(surface: *mut c_void, filename: *const c_char) -> c_int;
    fn cairo_text_extents(cr: *mut c_void, utf8: *const c_char, extents: *mut CairoTextExtents);
    fn cairo_translate(cr: *mut c_void, tx: c_double, ty: c_double);
}

#[repr(C)]
#[derive(Default)]
struct CairoTextExtents {
    x_bearing: c_double,
    y_bearing: c_double,
    width: c_double,
    height: c_double,
    x_advance: c_double,
    y_advance: c_double,
}

#[derive(Clone)]
struct Layer {
    name: String,
    keys: Vec<String>,
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
    const fn square(x: f64, y: f64) -> Self {
        Self::rotated(x, y, 73.0, 73.0, 0.0)
    }

    const fn rotated(x: f64, y: f64, width: f64, height: f64, rotation: f64) -> Self {
        Self {
            x,
            y,
            width,
            height,
            rotation,
        }
    }
}

#[derive(Clone, Copy)]
struct LayoutMetrics {
    origin_x: f64,
    origin_y: f64,
    scale: f64,
}

struct Args {
    keymap_path: PathBuf,
    print_path: bool,
    validate_only: bool,
    render_png: Option<PathBuf>,
}

struct AppState {
    path: PathBuf,
    layers: Vec<Layer>,
    current_layer: usize,
    selected_key: Option<usize>,
    drawing_area: *mut c_void,
    combo: *mut c_void,
    status: *mut c_void,
    selected_label: *mut c_void,
    editor_entry: *mut c_void,
}

struct QuickAction {
    state: *mut AppState,
    value: CString,
}

fn main() {
    let args = parse_args();
    if args.print_path {
        println!("{}", args.keymap_path.display());
        return;
    }

    let layers = match load_layers(&args.keymap_path) {
        Ok(layers) => layers,
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    };

    if args.validate_only {
        if let Err(error) = validate_layers(&layers) {
            eprintln!("{error}");
            std::process::exit(1);
        }
        println!("{} is valid", args.keymap_path.display());
        return;
    }

    if let Some(path) = args.render_png {
        if let Err(error) = render_preview_png(&path, layers) {
            eprintln!("{error}");
            std::process::exit(1);
        }
        println!("{}", path.display());
        return;
    }

    run_gui(args.keymap_path, layers);
}

fn parse_args() -> Args {
    let mut keymap_path = None;
    let mut print_path = false;
    let mut validate_only = false;
    let mut render_png = None;
    let mut args = std::env::args().skip(1);

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--print-path" => print_path = true,
            "--validate" => validate_only = true,
            "--render-png" => {
                let Some(path) = args.next() else {
                    eprintln!("--render-png requires a path");
                    std::process::exit(2);
                };
                render_png = Some(PathBuf::from(path));
            }
            "--help" | "-h" => {
                println!("Usage: keymap-editor [--print-path] [--validate] [--render-png out.png] [keymap.yaml]");
                std::process::exit(0);
            }
            value if value.starts_with('-') => {
                eprintln!("unknown option: {value}");
                std::process::exit(2);
            }
            value => keymap_path = Some(PathBuf::from(value)),
        }
    }

    Args {
        keymap_path: keymap_path.unwrap_or_else(default_keymap_path),
        print_path,
        validate_only,
        render_png,
    }
}

fn default_keymap_path() -> PathBuf {
    let candidates = [
        PathBuf::from("packages/silakka54/keymap.yaml"),
        dirs_home().join(".config/system-config/packages/silakka54/keymap.yaml"),
        PathBuf::from(DEFAULT_KEYMAP),
    ];

    candidates
        .into_iter()
        .find(|candidate| candidate.exists())
        .unwrap_or_else(|| PathBuf::from(DEFAULT_KEYMAP))
}

fn dirs_home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn run_gui(path: PathBuf, layers: Vec<Layer>) {
    let title = cstring("Silakka54 Keymap Editor");
    let destroy = cstring("destroy");
    let draw = cstring("draw");
    let changed = cstring("changed");
    let clicked = cstring("clicked");
    let activate = cstring("activate");
    let button_press = cstring("button-press-event");
    let key_press = cstring("key-press-event");

    unsafe {
        gtk_init(std::ptr::null_mut(), std::ptr::null_mut());
        install_gtk_theme();

        let window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
        gtk_window_set_title(window, title.as_ptr());
        gtk_window_set_default_size(window, 1180, 720);
        gtk_container_set_border_width(window, 14);

        let root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
        let toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        let combo = gtk_combo_box_text_new();
        let save_button = gtk_button_new_with_label(cstring("Save").as_ptr());
        let reload_button = gtk_button_new_with_label(cstring("Reload").as_ptr());
        let validate_button = gtk_button_new_with_label(cstring("Validate").as_ptr());
        let drawing_area = gtk_drawing_area_new();
        let editor = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
        let selected_label = gtk_label_new(cstring("Select a key").as_ptr());
        let editor_entry = gtk_entry_new();
        let apply_button = gtk_button_new_with_label(cstring("Apply").as_ptr());
        let status = gtk_label_new(cstring("").as_ptr());

        gtk_label_set_xalign(status, 0.0);
        gtk_label_set_xalign(selected_label, 0.0);
        gtk_entry_set_width_chars(editor_entry, 14);
        gtk_widget_set_size_request(drawing_area, 900, 500);
        gtk_widget_set_can_focus(drawing_area, TRUE);
        gtk_widget_add_events(drawing_area, GDK_BUTTON_PRESS_MASK | GDK_KEY_PRESS_MASK);

        gtk_box_pack_start(toolbar, combo, FALSE, FALSE, 0);
        gtk_box_pack_start(toolbar, save_button, FALSE, FALSE, 0);
        gtk_box_pack_start(toolbar, reload_button, FALSE, FALSE, 0);
        gtk_box_pack_start(toolbar, validate_button, FALSE, FALSE, 0);

        gtk_box_pack_start(editor, selected_label, FALSE, FALSE, 0);
        gtk_box_pack_start(editor, editor_entry, FALSE, FALSE, 0);
        gtk_box_pack_start(editor, apply_button, FALSE, FALSE, 0);
        let mut quick_buttons = Vec::new();
        for label in QUICK_LABELS {
            let button = gtk_button_new_with_label(cstring(label).as_ptr());
            gtk_box_pack_start(editor, button, FALSE, FALSE, 0);
            quick_buttons.push((*label, button));
        }

        gtk_box_pack_start(root, toolbar, FALSE, FALSE, 0);
        gtk_box_pack_start(root, drawing_area, TRUE, TRUE, 0);
        gtk_box_pack_start(root, editor, FALSE, FALSE, 0);
        gtk_box_pack_start(root, status, FALSE, FALSE, 0);
        gtk_container_add(window, root);

        let state = Box::into_raw(Box::new(AppState {
            path,
            layers,
            current_layer: 0,
            selected_key: None,
            drawing_area,
            combo,
            status,
            selected_label,
            editor_entry,
        }));

        populate_combo(&*state);
        gtk_combo_box_set_active(combo, 0);
        set_status(&*state, &format!("Loaded {}", (*state).path.display()));

        g_signal_connect_data(
            window,
            destroy.as_ptr(),
            on_destroy as *const c_void,
            std::ptr::null_mut(),
            None,
            0,
        );
        g_signal_connect_data(
            drawing_area,
            draw.as_ptr(),
            on_draw as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            drawing_area,
            button_press.as_ptr(),
            on_button_press as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            drawing_area,
            key_press.as_ptr(),
            on_key_press as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            combo,
            changed.as_ptr(),
            on_layer_changed as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            save_button,
            clicked.as_ptr(),
            on_save as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            reload_button,
            clicked.as_ptr(),
            on_reload as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            validate_button,
            clicked.as_ptr(),
            on_validate as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            apply_button,
            clicked.as_ptr(),
            on_apply as *const c_void,
            state as *mut c_void,
            None,
            0,
        );
        g_signal_connect_data(
            editor_entry,
            activate.as_ptr(),
            on_apply as *const c_void,
            state as *mut c_void,
            None,
            0,
        );

        for (label, button) in quick_buttons {
            let quick = Box::into_raw(Box::new(QuickAction {
                state,
                value: cstring(label),
            }));
            g_signal_connect_data(
                button,
                clicked.as_ptr(),
                on_quick_label as *const c_void,
                quick as *mut c_void,
                None,
                0,
            );
        }

        gtk_widget_show_all(window);
        gtk_widget_grab_focus(drawing_area);
        gtk_main();
    }
}

unsafe fn install_gtk_theme() {
    let provider = gtk_css_provider_new();
    if provider.is_null() {
        return;
    }
    let css = cstring(GTK_CSS);
    gtk_css_provider_load_from_data(provider, css.as_ptr(), -1, std::ptr::null_mut());
    let screen = gdk_screen_get_default();
    if !screen.is_null() {
        gtk_style_context_add_provider_for_screen(
            screen,
            provider,
            GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

unsafe extern "C" fn on_destroy(_widget: *mut c_void, _data: *mut c_void) {
    gtk_main_quit();
}

unsafe extern "C" fn on_draw(widget: *mut c_void, cr: *mut c_void, data: *mut c_void) -> c_int {
    let state = &*(data as *mut AppState);
    let width = gtk_widget_get_allocated_width(widget).max(1) as f64;
    let height = gtk_widget_get_allocated_height(widget).max(1) as f64;
    draw_keyboard(cr, state, width, height);
    FALSE
}

unsafe extern "C" fn on_button_press(
    widget: *mut c_void,
    event: *mut c_void,
    data: *mut c_void,
) -> c_int {
    let state = &mut *(data as *mut AppState);
    let mut x = 0.0;
    let mut y = 0.0;
    if gdk_event_get_coords(event, &mut x, &mut y) == FALSE {
        return FALSE;
    }
    let width = gtk_widget_get_allocated_width(widget).max(1) as f64;
    let height = gtk_widget_get_allocated_height(widget).max(1) as f64;
    if let Some(index) = hit_test(x, y, layout_metrics(width, height)) {
        select_key(state, index);
    }
    gtk_widget_grab_focus(widget);
    FALSE
}

unsafe extern "C" fn on_key_press(
    _widget: *mut c_void,
    event: *mut c_void,
    data: *mut c_void,
) -> c_int {
    let state = &mut *(data as *mut AppState);
    let mut keyval = 0;
    if gdk_event_get_keyval(event, &mut keyval) == FALSE {
        return FALSE;
    }
    let Some(label) = keyval_to_label(keyval) else {
        return FALSE;
    };
    apply_selected_value(state, &label);
    TRUE
}

unsafe extern "C" fn on_layer_changed(widget: *mut c_void, data: *mut c_void) {
    let state = &mut *(data as *mut AppState);
    let active = gtk_combo_box_get_active(widget);
    if active < 0 {
        return;
    }
    let active = active as usize;
    if active >= state.layers.len() || active == state.current_layer {
        return;
    }
    if let Err(error) = collect_editor(state) {
        set_status(state, &error);
        gtk_combo_box_set_active(widget, state.current_layer as c_int);
        return;
    }
    state.current_layer = active;
    refresh_editor(state);
    gtk_widget_queue_draw(state.drawing_area);
    set_status(
        state,
        &format!("Editing layer {}", state.layers[active].name),
    );
}

unsafe extern "C" fn on_save(_widget: *mut c_void, data: *mut c_void) {
    let state = &mut *(data as *mut AppState);
    if let Err(error) = collect_editor(state) {
        set_status(state, &error);
        return;
    }
    if let Err(error) = validate_layers(&state.layers) {
        set_status(state, &error);
        return;
    }
    let backup = state.path.with_extension("yaml.bak");
    if let Err(error) = fs::copy(&state.path, &backup) {
        set_status(state, &format!("Could not write backup: {error}"));
        return;
    }
    if let Err(error) = fs::write(&state.path, render_yaml(&state.layers)) {
        set_status(
            state,
            &format!("Could not save {}: {error}", state.path.display()),
        );
        return;
    }
    set_status(
        state,
        &format!(
            "Saved {} (backup: {})",
            state.path.display(),
            backup.display()
        ),
    );
}

unsafe extern "C" fn on_reload(_widget: *mut c_void, data: *mut c_void) {
    let state = &mut *(data as *mut AppState);
    if let Err(error) = collect_editor(state) {
        set_status(state, &error);
        return;
    }
    match load_layers(&state.path) {
        Ok(layers) => {
            state.layers = layers;
            state.current_layer = state
                .current_layer
                .min(state.layers.len().saturating_sub(1));
            populate_combo(state);
            gtk_combo_box_set_active(state.combo, state.current_layer as c_int);
            refresh_editor(state);
            gtk_widget_queue_draw(state.drawing_area);
            set_status(state, &format!("Reloaded {}", state.path.display()));
        }
        Err(error) => set_status(state, &error),
    }
}

unsafe extern "C" fn on_validate(_widget: *mut c_void, data: *mut c_void) {
    let state = &mut *(data as *mut AppState);
    if let Err(error) = collect_editor(state) {
        set_status(state, &error);
        return;
    }
    match validate_layers(&state.layers) {
        Ok(()) => set_status(state, "Keymap labels are valid"),
        Err(error) => set_status(state, &error),
    }
}

unsafe extern "C" fn on_apply(_widget: *mut c_void, data: *mut c_void) {
    let state = &mut *(data as *mut AppState);
    match collect_editor(state) {
        Ok(()) => {
            gtk_widget_queue_draw(state.drawing_area);
            set_status(state, "Applied selected key");
        }
        Err(error) => set_status(state, &error),
    }
}

unsafe extern "C" fn on_quick_label(_widget: *mut c_void, data: *mut c_void) {
    if data.is_null() {
        return;
    }
    let quick = &*(data as *mut QuickAction);
    let state = &mut *quick.state;
    let value = quick.value.to_string_lossy();
    apply_selected_value(state, &value);
}

unsafe fn draw_keyboard(cr: *mut c_void, state: &AppState, width: f64, height: f64) {
    cairo_save(cr);
    set_rgb(cr, MOCHA_BASE);
    cairo_rectangle(cr, 0.0, 0.0, width, height);
    cairo_fill(cr);

    let metrics = layout_metrics(width, height);
    let layer = &state.layers[state.current_layer];
    for (index, geometry) in KEY_GEOMETRY.iter().enumerate() {
        let selected = state.selected_key == Some(index);
        draw_key(cr, metrics, *geometry, index, &layer.keys[index], selected);
    }
    cairo_restore(cr);
}

fn render_preview_png(path: &Path, layers: Vec<Layer>) -> Result<(), String> {
    let status = unsafe {
        let surface = cairo_image_surface_create(0, REF_WIDTH as c_int, REF_HEIGHT as c_int);
        if surface.is_null() {
            return Err("Could not create Cairo image surface".to_string());
        }
        let cr = cairo_create(surface);
        if cr.is_null() {
            cairo_surface_destroy(surface);
            return Err("Could not create Cairo context".to_string());
        }
        let state = AppState {
            path: PathBuf::new(),
            layers,
            current_layer: 0,
            selected_key: Some(0),
            drawing_area: std::ptr::null_mut(),
            combo: std::ptr::null_mut(),
            status: std::ptr::null_mut(),
            selected_label: std::ptr::null_mut(),
            editor_entry: std::ptr::null_mut(),
        };
        draw_keyboard(cr, &state, REF_WIDTH, REF_HEIGHT);
        let status = cairo_surface_write_to_png(surface, cstring(&path.to_string_lossy()).as_ptr());
        cairo_destroy(cr);
        cairo_surface_destroy(surface);
        status
    };
    if status == 0 {
        Ok(())
    } else {
        Err(format!("Could not write {}", path.display()))
    }
}

unsafe fn draw_key(
    cr: *mut c_void,
    metrics: LayoutMetrics,
    geometry: KeyGeometry,
    index: usize,
    label: &str,
    selected: bool,
) {
    let cx = metrics.origin_x + geometry.x * metrics.scale;
    let cy = metrics.origin_y + geometry.y * metrics.scale;
    let key_width = geometry.width * metrics.scale;
    let key_height = geometry.height * metrics.scale;
    let r = 18.0 * metrics.scale;

    cairo_save(cr);
    cairo_translate(cr, cx, cy);
    cairo_rotate(cr, geometry.rotation.to_radians());

    rounded_rect(
        cr,
        -key_width / 2.0 + 2.0 * metrics.scale,
        -key_height / 2.0 + 3.0 * metrics.scale,
        key_width,
        key_height,
        r,
    );
    set_rgba(cr, MOCHA_CRUST, 0.42);
    cairo_fill(cr);

    rounded_rect(
        cr,
        -key_width / 2.0,
        -key_height / 2.0,
        key_width,
        key_height,
        r,
    );
    if selected {
        set_rgb(cr, MOCHA_TEAL);
    } else if is_layer_label(label) {
        set_rgb(cr, MOCHA_YELLOW);
    } else if label == "___" {
        set_rgb(cr, MOCHA_SURFACE0);
    } else {
        set_rgb(cr, MOCHA_SURFACE1);
    }
    cairo_fill_preserve(cr);
    if selected {
        set_rgb(cr, MOCHA_GREEN);
        cairo_set_line_width(cr, 3.6 * metrics.scale);
    } else {
        set_rgb(cr, MOCHA_RED);
        cairo_set_line_width(cr, 2.4 * metrics.scale);
    }
    cairo_stroke(cr);

    let text_color = if selected || is_layer_label(label) {
        MOCHA_CRUST
    } else if label == "___" {
        MOCHA_OVERLAY0
    } else {
        MOCHA_TEXT
    };
    set_rgb(cr, text_color);
    draw_centered_text(
        cr,
        label,
        0.0,
        -key_height * 0.04,
        key_width.min(key_height) * 0.25,
        key_width * 0.76,
    );

    set_rgba(cr, text_color, 0.62);
    draw_centered_text(
        cr,
        &format!("{}", index + 1),
        0.0,
        key_height * 0.31,
        key_width.min(key_height) * 0.11,
        key_width * 0.70,
    );
    cairo_restore(cr);
}

unsafe fn draw_centered_text(
    cr: *mut c_void,
    text: &str,
    center_x: f64,
    baseline_y: f64,
    font_size: f64,
    max_width: f64,
) {
    let mut display = text.to_string();
    cairo_select_font_face(cr, cstring("Sans").as_ptr(), 0, 1);
    let mut size = font_size;
    loop {
        cairo_set_font_size(cr, size);
        let extents = text_extents(cr, &display);
        if extents.width <= max_width || size <= font_size * 0.62 {
            cairo_move_to(
                cr,
                center_x - extents.width / 2.0 - extents.x_bearing,
                baseline_y - extents.height / 2.0,
            );
            cairo_show_text(cr, cstring(&display).as_ptr());
            return;
        }
        if display.chars().count() > 8 {
            display = format!("{}.", display.chars().take(7).collect::<String>());
        } else {
            size *= 0.92;
        }
    }
}

unsafe fn text_extents(cr: *mut c_void, text: &str) -> CairoTextExtents {
    let mut extents = CairoTextExtents::default();
    cairo_text_extents(cr, cstring(text).as_ptr(), &mut extents);
    extents
}

unsafe fn rounded_rect(cr: *mut c_void, x: f64, y: f64, w: f64, h: f64, r: f64) {
    let pi = std::f64::consts::PI;
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -pi / 2.0, 0.0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0.0, pi / 2.0);
    cairo_arc(cr, x + r, y + h - r, r, pi / 2.0, pi);
    cairo_arc(cr, x + r, y + r, r, pi, 3.0 * pi / 2.0);
    cairo_close_path(cr);
}

fn layout_metrics(width: f64, height: f64) -> LayoutMetrics {
    let scale = (width / REF_WIDTH).min(height / REF_HEIGHT).max(0.05);
    let origin_x = (width - REF_WIDTH * scale) / 2.0;
    let origin_y = (height - REF_HEIGHT * scale) / 2.0;
    LayoutMetrics {
        origin_x,
        origin_y,
        scale,
    }
}

fn hit_test(x: f64, y: f64, metrics: LayoutMetrics) -> Option<usize> {
    KEY_GEOMETRY
        .iter()
        .enumerate()
        .find_map(|(index, geometry)| {
            let cx = metrics.origin_x + geometry.x * metrics.scale;
            let cy = metrics.origin_y + geometry.y * metrics.scale;
            let dx = x - cx;
            let dy = y - cy;
            let angle = -geometry.rotation.to_radians();
            let local_x = dx * angle.cos() - dy * angle.sin();
            let local_y = dx * angle.sin() + dy * angle.cos();
            let half_width = geometry.width * metrics.scale / 2.0;
            let half_height = geometry.height * metrics.scale / 2.0;
            (local_x.abs() <= half_width && local_y.abs() <= half_height).then_some(index)
        })
}

unsafe fn select_key(state: &mut AppState, index: usize) {
    if let Err(error) = collect_editor(state) {
        set_status(state, &error);
        return;
    }
    state.selected_key = Some(index);
    refresh_editor(state);
    gtk_widget_queue_draw(state.drawing_area);
}

unsafe fn refresh_editor(state: &AppState) {
    if let Some(index) = state.selected_key {
        let layer = &state.layers[state.current_layer];
        gtk_label_set_text(
            state.selected_label,
            cstring(&format!("{} key {}", layer.name, index + 1)).as_ptr(),
        );
        gtk_entry_set_text(state.editor_entry, cstring(&layer.keys[index]).as_ptr());
    } else {
        gtk_label_set_text(state.selected_label, cstring("Select a key").as_ptr());
        gtk_entry_set_text(state.editor_entry, cstring("").as_ptr());
    }
}

unsafe fn collect_editor(state: &mut AppState) -> Result<(), String> {
    let Some(index) = state.selected_key else {
        return Ok(());
    };
    let text = CStr::from_ptr(gtk_entry_get_text(state.editor_entry))
        .to_string_lossy()
        .trim()
        .to_string();
    if text.is_empty() {
        return Err("Selected key label cannot be empty".to_string());
    }
    if valid_label(&text, &layer_names(&state.layers)) {
        state.layers[state.current_layer].keys[index] = text;
        Ok(())
    } else {
        Err(format!("Unsupported key label {text:?}"))
    }
}

unsafe fn apply_selected_value(state: &mut AppState, value: &str) {
    let Some(index) = state.selected_key else {
        set_status(state, "Select a key before assigning a value");
        return;
    };
    if !valid_label(value, &layer_names(&state.layers)) {
        set_status(state, &format!("Unsupported key label {value:?}"));
        return;
    }
    state.layers[state.current_layer].keys[index] = value.to_string();
    gtk_entry_set_text(state.editor_entry, cstring(value).as_ptr());
    gtk_widget_queue_draw(state.drawing_area);
    set_status(
        state,
        &format!(
            "Set {}[{}] = {}",
            state.layers[state.current_layer].name, index, value
        ),
    );
}

fn keyval_to_label(keyval: u32) -> Option<String> {
    match keyval {
        0xff1b => Some("Esc".to_string()),
        0xff09 => Some("Tab".to_string()),
        0xff08 => Some("Bspc".to_string()),
        0xffff => Some("Del".to_string()),
        0xff0d | 0xff8d => Some("Enter".to_string()),
        0xff50 => Some("Home".to_string()),
        0xff57 => Some("End".to_string()),
        0xff55 => Some("PgUp".to_string()),
        0xff56 => Some("PgDn".to_string()),
        0xff51 => Some("Left".to_string()),
        0xff52 => Some("Up".to_string()),
        0xff53 => Some("Right".to_string()),
        0xff54 => Some("Down".to_string()),
        0xffe1 | 0xffe2 => Some("Shift".to_string()),
        0xffe3 | 0xffe4 => Some("Ctrl".to_string()),
        0xffe7 | 0xffe8 => Some("GUI".to_string()),
        0xffe9 | 0xffea => Some("Alt".to_string()),
        0x20 => Some("Space".to_string()),
        value if (b'a' as u32..=b'z' as u32).contains(&value) => {
            Some((value as u8 as char).to_ascii_uppercase().to_string())
        }
        value if (b'A' as u32..=b'Z' as u32).contains(&value) => {
            Some((value as u8 as char).to_string())
        }
        value if (b'0' as u32..=b'9' as u32).contains(&value) => {
            Some((value as u8 as char).to_string())
        }
        value if (0x21..=0x7e).contains(&value) => Some((value as u8 as char).to_string()),
        _ => None,
    }
}

fn is_layer_label(label: &str) -> bool {
    matches!(label, "Num" | "Nav" | "Sym" | "Base")
}

unsafe fn populate_combo(state: &AppState) {
    gtk_combo_box_text_remove_all(state.combo);
    for layer in &state.layers {
        gtk_combo_box_text_append_text(state.combo, cstring(&layer.name).as_ptr());
    }
}

unsafe fn set_status(state: &AppState, message: &str) {
    gtk_label_set_text(state.status, cstring(message).as_ptr());
}

fn load_layers(path: &Path) -> Result<Vec<Layer>, String> {
    let text = fs::read_to_string(path)
        .map_err(|error| format!("Could not read {}: {error}", path.display()))?;
    parse_layers(&text).map_err(|error| format!("{}: {error}", path.display()))
}

fn parse_layers(text: &str) -> Result<Vec<Layer>, String> {
    let mut in_layers = false;
    let mut layers = Vec::new();
    let mut current: Option<Layer> = None;

    for (line_number, raw_line) in text.lines().enumerate() {
        let line = raw_line.trim_end();
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed == "layers:" {
            in_layers = true;
            continue;
        }
        if !in_layers {
            continue;
        }

        if line.starts_with("  ") && !line.starts_with("    ") && trimmed.ends_with(':') {
            if let Some(layer) = current.take() {
                layers.push(layer);
            }
            let name = trimmed.trim_end_matches(':').to_string();
            if name.is_empty() {
                return Err(format!("line {} has an empty layer name", line_number + 1));
            }
            current = Some(Layer {
                name,
                keys: Vec::new(),
            });
            continue;
        }

        if line.starts_with("    - ") {
            let Some(layer) = current.as_mut() else {
                return Err(format!(
                    "line {} has a key before any layer",
                    line_number + 1
                ));
            };
            layer.keys.push(
                parse_scalar(&line[6..])
                    .map_err(|error| format!("line {}: {error}", line_number + 1))?,
            );
            continue;
        }

        return Err(format!(
            "line {} is not valid keymap.yaml syntax",
            line_number + 1
        ));
    }

    if let Some(layer) = current {
        layers.push(layer);
    }
    if layers.is_empty() {
        return Err("no layers found".to_string());
    }
    for layer in &layers {
        if layer.keys.len() != KEY_COUNT {
            return Err(format!(
                "layer {} has {} keys, expected {}",
                layer.name,
                layer.keys.len(),
                KEY_COUNT
            ));
        }
    }
    Ok(layers)
}

fn parse_scalar(value: &str) -> Result<String, String> {
    let value = value.trim();
    if value.starts_with('"') {
        parse_double_quoted(value)
    } else if value.starts_with('\'') {
        parse_single_quoted(value)
    } else {
        Ok(value.to_string())
    }
}

fn parse_double_quoted(value: &str) -> Result<String, String> {
    let mut chars = value.chars();
    if chars.next() != Some('"') {
        return Err("expected quoted value".to_string());
    }
    let mut output = String::new();
    let mut escaped = false;
    for ch in chars {
        if escaped {
            match ch {
                '"' => output.push('"'),
                '\\' => output.push('\\'),
                'n' => output.push('\n'),
                'r' => output.push('\r'),
                't' => output.push('\t'),
                other => output.push(other),
            }
            escaped = false;
        } else if ch == '\\' {
            escaped = true;
        } else if ch == '"' {
            return Ok(output);
        } else {
            output.push(ch);
        }
    }
    Err("unterminated quoted value".to_string())
}

fn parse_single_quoted(value: &str) -> Result<String, String> {
    let mut chars = value.chars().peekable();
    if chars.next() != Some('\'') {
        return Err("expected single-quoted value".to_string());
    }
    let mut output = String::new();
    while let Some(ch) = chars.next() {
        if ch == '\'' {
            if chars.peek() == Some(&'\'') {
                chars.next();
                output.push('\'');
            } else {
                return Ok(output);
            }
        } else {
            output.push(ch);
        }
    }
    Err("unterminated single-quoted value".to_string())
}

fn validate_layers(layers: &[Layer]) -> Result<(), String> {
    let layer_names = layer_names(layers);
    for layer in layers {
        if layer.keys.len() != KEY_COUNT {
            return Err(format!(
                "Layer {} has {} keys, expected {}",
                layer.name,
                layer.keys.len(),
                KEY_COUNT
            ));
        }
        for (index, label) in layer.keys.iter().enumerate() {
            if !valid_label(label, &layer_names) {
                return Err(format!(
                    "{}[{}]: unsupported key label {:?}",
                    layer.name, index, label
                ));
            }
        }
    }
    Ok(())
}

fn layer_names(layers: &[Layer]) -> Vec<&str> {
    layers.iter().map(|layer| layer.name.as_str()).collect()
}

fn valid_label(label: &str, layer_names: &[&str]) -> bool {
    layer_names.contains(&label)
        || ALIASES.contains(&label)
        || is_single_ascii_upper(label)
        || is_single_ascii_digit(label)
        || is_function_key(label)
        || label.starts_with("KC_")
        || label.starts_with("QK_")
        || is_function_call(label)
}

fn is_single_ascii_upper(value: &str) -> bool {
    value.len() == 1 && value.as_bytes()[0].is_ascii_uppercase()
}

fn is_single_ascii_digit(value: &str) -> bool {
    value.len() == 1 && value.as_bytes()[0].is_ascii_digit()
}

fn is_function_key(value: &str) -> bool {
    let Some(number) = value.strip_prefix('F') else {
        return false;
    };
    number
        .parse::<u8>()
        .is_ok_and(|number| (1..=24).contains(&number))
}

fn is_function_call(value: &str) -> bool {
    let Some(open) = value.find('(') else {
        return false;
    };
    value.ends_with(')')
        && value[..open]
            .chars()
            .all(|ch| ch.is_ascii_uppercase() || ch == '_')
        && value[open + 1..value.len() - 1]
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == ',' || ch == ' ')
}

fn render_yaml(layers: &[Layer]) -> String {
    let mut output = String::from("layers:\n");
    for (index, layer) in layers.iter().enumerate() {
        if index > 0 {
            output.push('\n');
        }
        output.push_str("  ");
        output.push_str(&layer.name);
        output.push_str(":\n");
        for key in &layer.keys {
            output.push_str("    - ");
            output.push_str(&yaml_scalar(key));
            output.push('\n');
        }
    }
    output
}

fn yaml_scalar(value: &str) -> String {
    if is_plain_yaml_scalar(value) {
        value.to_string()
    } else {
        let mut quoted = String::from("\"");
        for ch in value.chars() {
            match ch {
                '"' => quoted.push_str("\\\""),
                '\\' => quoted.push_str("\\\\"),
                '\n' => quoted.push_str("\\n"),
                '\r' => quoted.push_str("\\r"),
                '\t' => quoted.push_str("\\t"),
                other => quoted.push(other),
            }
        }
        quoted.push('"');
        quoted
    }
}

fn is_plain_yaml_scalar(value: &str) -> bool {
    let mut chars = value.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first.is_ascii_alphabetic() || first == '_')
        && chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '+' || ch == '-')
        && !matches!(value, "true" | "false" | "null" | "Null" | "NULL")
}

unsafe fn set_rgb(cr: *mut c_void, color: Color) {
    cairo_set_source_rgb(cr, color.red, color.green, color.blue);
}

unsafe fn set_rgba(cr: *mut c_void, color: Color, alpha: f64) {
    cairo_set_source_rgba(cr, color.red, color.green, color.blue, alpha);
}

fn cstring(value: &str) -> CString {
    CString::new(value).unwrap_or_else(|_| CString::new(value.replace('\0', "")).unwrap())
}
