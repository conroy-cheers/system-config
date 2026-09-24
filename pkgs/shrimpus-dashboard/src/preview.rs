//! Deterministic previews, including the panel's exact three-colour conversion.
use std::env;
use std::error::Error;
use std::fs;
use std::path::Path;
use std::rc::Rc;

use chrono::{Datelike, Local, TimeZone};
use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint::{ComponentHandle, PhysicalSize, Rgb8Pixel};

use crate::{Dashboard, Snapshot, Weather, apply_snapshot};

fn snapshot() -> Result<Snapshot, Box<dyn Error>> {
    let now = Local.with_ymd_and_hms(2026, 9, 25, 8, 30, 0).unwrap();
    let mut snapshot = Snapshot {
        date: now.date_naive(),
        wifi: Some("floznet-7".into()),
        weather: Some(Weather {
            date: now.date_naive(),
            updated_at: now,
            code: 2,
            low: 12,
            high: 19,
            rain: 30,
        }),
        weather_is_current: true,
    };
    let case = env::var("SHRIMPUS_PREVIEW_CASE").unwrap_or_else(|_| "normal".into());
    match case.as_str() {
        "normal" => {}
        "offline" => {
            snapshot.wifi = None;
            snapshot.weather_is_current = false;
        }
        "missing" => {
            snapshot.wifi = None;
            snapshot.weather = None;
            snapshot.weather_is_current = false;
        }
        "long" => {
            snapshot.date = now.date_naive().with_day(30).unwrap();
            snapshot.wifi = Some("A very long wireless network name".into());
            let weather = snapshot.weather.as_mut().unwrap();
            weather.code = 95;
            weather.low = -12;
            weather.high = -3;
            weather.rain = 100;
        }
        "sun" | "cloud" | "fog" | "rain" | "snow" | "storm" | "unknown" => {
            snapshot.weather.as_mut().unwrap().code = match case.as_str() {
                "sun" => 0,
                "cloud" => 3,
                "fog" => 45,
                "rain" => 63,
                "snow" => 73,
                "storm" => 95,
                _ => 255,
            };
        }
        _ => return Err(format!("unknown preview case: {case}").into()),
    }
    Ok(snapshot)
}

pub fn run() -> Result<(), Box<dyn Error>> {
    let app = Dashboard::new()?;
    apply_snapshot(&app, &snapshot()?);
    app.run()?;
    Ok(())
}

struct PreviewPlatform(Rc<MinimalSoftwareWindow>);

impl slint::platform::Platform for PreviewPlatform {
    fn create_window_adapter(
        &self,
    ) -> Result<Rc<dyn slint::platform::WindowAdapter>, slint::PlatformError> {
        Ok(self.0.clone())
    }
}

pub fn render(path: &Path) -> Result<(), Box<dyn Error>> {
    let window = MinimalSoftwareWindow::new(RepaintBufferType::NewBuffer);
    slint::platform::set_platform(Box::new(PreviewPlatform(window.clone())))?;
    let app = Dashboard::new()?;
    apply_snapshot(&app, &snapshot()?);
    window.set_size(PhysicalSize::new(296, 152));
    app.show()?;
    let mut pixels = vec![Rgb8Pixel::default(); 296 * 152];
    window.draw_if_needed(|renderer| {
        renderer.render(&mut pixels, 296);
    });

    // Match modules/nixos/orangepi-zero2w/ssd16xx/panel-ssd16xx.c.
    // PPM avoids a runtime image-encoding dependency in the dashboard.
    let mut ppm = b"P6\n296 152\n255\n".to_vec();
    for pixel in pixels {
        let luma =
            (77 * u32::from(pixel.r) + 150 * u32::from(pixel.g) + 29 * u32::from(pixel.b)) >> 8;
        let color = if pixel.r > 127 && pixel.r > pixel.g && pixel.r > pixel.b {
            [255, 0, 0]
        } else if luma > 127 {
            [255, 255, 255]
        } else {
            [0, 0, 0]
        };
        ppm.extend_from_slice(&color);
    }
    fs::write(path, ppm)?;
    Ok(())
}
