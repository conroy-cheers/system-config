use std::env;
use std::error::Error;
use std::fs;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

use chrono::{DateTime, Local, NaiveDate};
use serde::{Deserialize, Serialize};
use slint::ComponentHandle;
use zbus::zvariant::OwnedObjectPath;

slint::include_modules!();

mod preview;

const NETWORK_MANAGER: &str = "org.freedesktop.NetworkManager";
const WEATHER_URL: &str = "https://api.open-meteo.com/v1/forecast";
const UPDATE_INTERVAL: Duration = Duration::from_secs(60);
const WEATHER_UPDATE_TICKS: u32 = 30;

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager"
)]
trait NetworkManager {
    fn get_device_by_ip_iface(&self, iface: &str) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.Device.Wireless")]
trait WirelessDevice {
    #[zbus(property)]
    fn active_access_point(&self) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.NetworkManager.AccessPoint")]
trait AccessPoint {
    #[zbus(property)]
    fn ssid(&self) -> zbus::Result<Vec<u8>>;
}

#[derive(Clone, Debug, PartialEq)]
struct Snapshot {
    date: NaiveDate,
    wifi: Option<String>,
    weather: Option<Weather>,
    weather_is_current: bool,
}

#[derive(Debug, Deserialize, Serialize)]
struct Forecast {
    daily: DailyForecast,
}

#[derive(Debug, Deserialize, Serialize)]
struct DailyForecast {
    time: Vec<String>,
    weather_code: Vec<u8>,
    temperature_2m_max: Vec<f64>,
    temperature_2m_min: Vec<f64>,
    precipitation_probability_max: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
struct Weather {
    date: NaiveDate,
    updated_at: DateTime<Local>,
    code: u8,
    low: i32,
    high: i32,
    rain: u8,
}

#[derive(Debug, Deserialize, Serialize)]
struct CachedForecast {
    fetched_at: i64,
    forecast: Forecast,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = env::args().skip(1).collect();
    if let Some(index) = args
        .iter()
        .position(|argument| argument == "--render-preview")
    {
        let path = args
            .get(index + 1)
            .ok_or("--render-preview requires a .ppm path")?;
        return preview::render(Path::new(path));
    }
    if args.iter().any(|argument| argument == "--preview") {
        return preview::run();
    }

    let (mut snapshot, weather_is_current) = collect_snapshot(None, true);
    let app = Dashboard::new()?;
    apply_snapshot(&app, &snapshot);

    let weak_app = app.as_weak();
    thread::spawn(move || {
        let mut ticks = 0;
        let mut retry_weather = !weather_is_current;
        loop {
            thread::sleep(UPDATE_INTERVAL);
            ticks += 1;
            let refresh_weather = retry_weather
                || ticks >= WEATHER_UPDATE_TICKS
                || snapshot.date != Local::now().date_naive();

            let (next, weather_is_current) = collect_snapshot(Some(&snapshot), refresh_weather);
            if refresh_weather {
                retry_weather = !weather_is_current;
                if weather_is_current {
                    ticks = 0;
                }
            }
            if next != snapshot {
                snapshot = next.clone();
                if weak_app
                    .upgrade_in_event_loop(move |app| apply_snapshot(&app, &next))
                    .is_err()
                {
                    break;
                }
            }
        }
    });

    app.run()?;
    Ok(())
}

fn collect_snapshot(previous: Option<&Snapshot>, refresh_weather: bool) -> (Snapshot, bool) {
    let (weather, weather_is_current) = if refresh_weather {
        match fetch_weather() {
            Ok(weather) => (Some(weather), true),
            Err(error) => {
                eprintln!("weather update failed: {error}");
                (
                    previous
                        .and_then(|snapshot| snapshot.weather.clone())
                        .or_else(read_cached_weather),
                    false,
                )
            }
        }
    } else {
        (
            previous.and_then(|snapshot| snapshot.weather.clone()),
            previous.is_some_and(|snapshot| snapshot.weather_is_current),
        )
    };
    let now = Local::now();
    let weather = weather.filter(|weather| weather_is_for_today(weather, now));
    let weather_is_current = weather_is_current && weather.is_some();

    (
        Snapshot {
            date: now.date_naive(),
            wifi: connected_ssid().unwrap_or_else(|error| {
                eprintln!("could not read Wi-Fi state: {error}");
                None
            }),
            weather,
            weather_is_current,
        },
        weather_is_current,
    )
}

fn connected_ssid() -> Result<Option<String>, Box<dyn Error>> {
    let connection = zbus::blocking::Connection::system()?;
    let manager = NetworkManagerProxyBlocking::new(&connection)?;
    let device_path = manager.get_device_by_ip_iface("wlan0")?;
    let wireless = WirelessDeviceProxyBlocking::builder(&connection)
        .destination(NETWORK_MANAGER)?
        .path(device_path)?
        .build()?;
    let access_point_path = wireless.active_access_point()?;

    if access_point_path.as_str() == "/" {
        return Ok(None);
    }

    let access_point = AccessPointProxyBlocking::builder(&connection)
        .destination(NETWORK_MANAGER)?
        .path(access_point_path)?
        .build()?;
    let ssid = access_point.ssid()?;
    // SSIDs are untrusted display text; don't let control characters alter layout.
    let ssid: String = String::from_utf8_lossy(&ssid)
        .chars()
        .filter(|character| !character.is_control())
        .collect();
    Ok(Some(if ssid.is_empty() {
        "Connected".into()
    } else {
        ssid
    }))
}

fn fetch_weather() -> Result<Weather, Box<dyn Error>> {
    let latitude = env::var("SHRIMPUS_WEATHER_LATITUDE").unwrap_or_else(|_| "-37.8136".into());
    let longitude = env::var("SHRIMPUS_WEATHER_LONGITUDE").unwrap_or_else(|_| "144.9631".into());
    let timezone =
        env::var("SHRIMPUS_WEATHER_TIMEZONE").unwrap_or_else(|_| "Australia/Melbourne".into());

    let response = minreq::get(WEATHER_URL)
        .with_param("latitude", &latitude)
        .with_param("longitude", &longitude)
        .with_param("timezone", &timezone)
        .with_param("forecast_days", "1")
        .with_param(
            "daily",
            "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        )
        .with_timeout(10)
        .send()?;

    if response.status_code != 200 {
        return Err(format!("Open-Meteo returned HTTP {}", response.status_code).into());
    }

    let body = response.as_str()?;
    let forecast: Forecast = serde_json::from_str(body)?;
    let now = Local::now();
    let weather = format_weather(&forecast, now)?;
    if !weather_is_for_today(&weather, now) {
        return Err("forecast is not for today's local date".into());
    }
    let cached = CachedForecast {
        fetched_at: now.timestamp(),
        forecast,
    };
    write_weather_cache(&serde_json::to_string(&cached)?);
    Ok(weather)
}

fn format_weather(
    forecast: &Forecast,
    updated_at: DateTime<Local>,
) -> Result<Weather, Box<dyn Error>> {
    let date = NaiveDate::parse_from_str(
        forecast.daily.time.first().ok_or("forecast has no date")?,
        "%Y-%m-%d",
    )?;
    let code = *forecast
        .daily
        .weather_code
        .first()
        .ok_or("forecast has no weather code")?;
    let high = forecast
        .daily
        .temperature_2m_max
        .first()
        .ok_or("forecast has no high temperature")?;
    let low = forecast
        .daily
        .temperature_2m_min
        .first()
        .ok_or("forecast has no low temperature")?;
    let rain = forecast
        .daily
        .precipitation_probability_max
        .first()
        .ok_or("forecast has no rain probability")?;

    if !low.is_finite()
        || !high.is_finite()
        || !(-90.0..=60.0).contains(low)
        || !(-90.0..=60.0).contains(high)
        || low > high
        || *rain > 100
    {
        return Err("forecast has invalid temperatures or rain probability".into());
    }
    Ok(Weather {
        date,
        updated_at,
        code,
        low: low.round() as i32,
        high: high.round() as i32,
        rain: *rain,
    })
}

fn weather_description(code: u8) -> &'static str {
    match code {
        0 => "Clear",
        1 => "Mostly clear",
        2 => "Partly cloudy",
        3 => "Overcast",
        45 | 48 => "Fog",
        51 | 53 | 55 | 56 | 57 => "Drizzle",
        61 | 63 | 65 | 66 | 67 => "Rain",
        71 | 73 | 75 | 77 => "Snow",
        80 | 81 | 82 => "Rain showers",
        85 | 86 => "Snow showers",
        95 | 96 | 99 => "Thunderstorms",
        _ => "Mixed weather",
    }
}

fn weather_kind(code: u8) -> i32 {
    match code {
        0 => 0,
        1 | 2 => 1,
        3 => 2,
        45 | 48 => 3,
        51..=67 | 80..=82 => 4,
        71..=77 | 85 | 86 => 5,
        95 | 96 | 99 => 6,
        _ => 7,
    }
}

fn weather_is_for_today(weather: &Weather, now: DateTime<Local>) -> bool {
    weather.date == now.date_naive()
        && weather.updated_at.date_naive() == now.date_naive()
        && weather.updated_at <= now
}

fn cache_path() -> PathBuf {
    env::var_os("SHRIMPUS_WEATHER_CACHE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/var/cache/shrimpus-dashboard/weather.json"))
}

fn read_cached_weather() -> Option<Weather> {
    let body = fs::read_to_string(cache_path()).ok()?;
    decode_cached_weather(&body, Local::now())
}

fn decode_cached_weather(body: &str, now: DateTime<Local>) -> Option<Weather> {
    // Legacy caches have no trustworthy fetch time and are intentionally ignored.
    let cached: CachedForecast = serde_json::from_str(body).ok()?;
    let updated_at = DateTime::from_timestamp(cached.fetched_at, 0)?.with_timezone(&Local);
    let weather = format_weather(&cached.forecast, updated_at).ok()?;
    weather_is_for_today(&weather, now).then_some(weather)
}

fn write_weather_cache(body: &str) {
    let path = cache_path();
    if let Err(error) = write_weather_cache_inner(&path, body) {
        eprintln!("could not cache weather: {error}");
    }
}

fn write_weather_cache_inner(path: &Path, body: &str) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, body)?;
    fs::rename(temporary, path)
}

fn apply_snapshot(app: &Dashboard, snapshot: &Snapshot) {
    app.set_weekday(snapshot.date.format("%a").to_string().to_uppercase().into());
    app.set_day(snapshot.date.format("%-d").to_string().into());
    app.set_month_year(
        snapshot
            .date
            .format("%b %Y")
            .to_string()
            .to_uppercase()
            .into(),
    );
    app.set_wifi_connected(snapshot.wifi.is_some());
    app.set_wifi_text(snapshot.wifi.as_deref().unwrap_or("Offline").into());
    app.set_weather_available(snapshot.weather.is_some());
    app.set_weather_stale(!snapshot.weather_is_current);
    if let Some(weather) = &snapshot.weather {
        app.set_weather_kind(weather_kind(weather.code));
        app.set_weather_title(weather_description(weather.code).into());
        app.set_temperatures(format!("{}–{}°", weather.low, weather.high).into());
        app.set_compact_temperatures(weather.low < 0 || weather.high < 0);
        app.set_rain_text(format!("{}% chance of rain", weather.rain).into());
        let prefix = if snapshot.weather_is_current {
            "Updated"
        } else {
            "Saved"
        };
        app.set_freshness_text(format!("{prefix} {}", weather.updated_at.format("%H:%M")).into());
    } else {
        app.set_weather_kind(7);
        app.set_weather_title("No forecast".into());
        app.set_temperatures("".into());
        app.set_compact_temperatures(false);
        app.set_rain_text("Waiting for weather".into());
        app.set_freshness_text("Update pending".into());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> DateTime<Local> {
        Local.with_ymd_and_hms(2026, 9, 25, 12, 0, 0).unwrap()
    }

    fn forecast() -> Forecast {
        serde_json::from_str(
            r#"{"daily":{"time":["2026-09-25"],"weather_code":[61],"temperature_2m_max":[19.4],"temperature_2m_min":[11.6],"precipitation_probability_max":[70]}}"#,
        ).unwrap()
    }

    #[test]
    fn formats_daily_forecast() {
        let weather = format_weather(&forecast(), now()).unwrap();
        assert_eq!((weather.low, weather.high, weather.rain), (12, 19, 70));
        assert_eq!(weather_description(weather.code), "Rain");
        assert_eq!(weather_kind(weather.code), 4);
    }

    #[test]
    fn cache_preserves_fetch_time_and_expires_at_midnight() {
        let cached = CachedForecast {
            fetched_at: now().timestamp(),
            forecast: forecast(),
        };
        let body = serde_json::to_string(&cached).unwrap();
        let later = now() + chrono::Duration::hours(6);
        assert_eq!(
            decode_cached_weather(&body, later).unwrap().updated_at,
            now()
        );
        assert!(decode_cached_weather(&body, now() + chrono::Duration::days(1)).is_none());
        assert!(decode_cached_weather(&body, now() - chrono::Duration::hours(1)).is_none());
    }

    #[test]
    fn rejects_undated_cache_and_wrong_forecast_date() {
        assert!(
            decode_cached_weather(&serde_json::to_string(&forecast()).unwrap(), now()).is_none()
        );
        let mut forecast = forecast();
        forecast.daily.time[0] = "2026-09-24".into();
        let weather = format_weather(&forecast, now()).unwrap();
        assert!(!weather_is_for_today(&weather, now()));
    }

    #[test]
    fn rejects_incomplete_or_invalid_forecasts() {
        let mut data = forecast();
        data.daily.temperature_2m_min.clear();
        assert!(format_weather(&data, now()).is_err());
        data.daily.temperature_2m_min = vec![f64::NAN];
        assert!(format_weather(&data, now()).is_err());
        data.daily.temperature_2m_min = vec![25.0];
        assert!(format_weather(&data, now()).is_err());
        data.daily.temperature_2m_min = vec![12.0];
        data.daily.precipitation_probability_max = vec![101];
        assert!(format_weather(&data, now()).is_err());
    }

    #[test]
    fn freezing_temperatures_and_unknown_conditions_are_explicit() {
        let mut data = forecast();
        data.daily.temperature_2m_min = vec![-0.2];
        data.daily.weather_code = vec![255];
        let weather = format_weather(&data, now()).unwrap();
        assert_eq!(weather.low, 0);
        assert_eq!(weather_kind(weather.code), 7);
        assert_eq!(weather_description(weather.code), "Mixed weather");
    }
}
