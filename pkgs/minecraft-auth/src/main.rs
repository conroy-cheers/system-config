use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{self, Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::{STANDARD as BASE64_STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use p256::ecdsa::signature::hazmat::PrehashSigner;
use p256::ecdsa::{Signature, SigningKey};
use p256::elliptic_curve::pkcs8::{DecodePrivateKey, EncodePrivateKey, LineEnding};
use reqwest::header::{AUTHORIZATION, CONTENT_TYPE};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use thiserror::Error;
use tokio::time::sleep;
use uuid::Uuid;

const CLIENT_ID: &str = "00000000402b5328";
const SCOPE: &str = "service::user.auth.xboxlive.com::MBI_SSL";
const DEVICE_TYPE: &str = "Win32";
const LIVE_DEVICE_CODE_URL: &str = "https://login.live.com/oauth20_connect.srf";
const LIVE_TOKEN_URL: &str = "https://login.live.com/oauth20_token.srf";
const XBOX_DEVICE_AUTH_URL: &str = "https://device.auth.xboxlive.com/device/authenticate";
const XBOX_SISU_URL: &str = "https://sisu.xboxlive.com/authorize";
const MINECRAFT_LAUNCHER_LOGIN_URL: &str = "https://api.minecraftservices.com/launcher/login";
const MINECRAFT_PROFILE_URL: &str = "https://api.minecraftservices.com/minecraft/profile";
const XBOX_AUTH_RELYING_PARTY: &str = "http://auth.xboxlive.com";
const JAVA_XSTS_RELYING_PARTY: &str = "rp://api.minecraftservices.com/";
const STATE_VERSION: u32 = 2;

#[derive(Debug, Error)]
enum AuthError {
    #[error("{0}")]
    Message(String),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] reqwest::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Pkcs8(#[from] p256::pkcs8::Error),
    #[error(transparent)]
    Spki(#[from] p256::pkcs8::spki::Error),
    #[error(transparent)]
    Signature(#[from] p256::ecdsa::Error),
}

#[derive(Debug, Clone, Copy)]
enum CommandKind {
    Ensure,
    Show,
    Logout,
}

#[derive(Debug)]
struct Args {
    command: CommandKind,
    account: String,
    json: bool,
    reauth: bool,
    no_open_browser: bool,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct State {
    version: u32,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    device_id: Option<String>,
    #[serde(default)]
    device_key_pem: Option<String>,
    #[serde(default)]
    last_profile: Option<ProfileSummary>,
    #[serde(default)]
    last_updated_at: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ProfileSummary {
    name: String,
    uuid: String,
}

#[derive(Debug, Serialize)]
struct SessionOutput {
    username: String,
    uuid: String,
    access_token: String,
    access_token_expires_at: u64,
}

#[derive(Debug, Serialize)]
struct ShowOutput {
    path: String,
    last_profile: Option<ProfileSummary>,
    last_updated_at: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct DeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_uri: String,
    expires_in: u64,
    interval: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct LiveTokenResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
}

#[derive(Debug, Deserialize)]
struct DeviceTokenResponse {
    #[serde(rename = "Token")]
    token: String,
}

#[derive(Debug, Deserialize)]
struct SisuResponse {
    #[serde(rename = "AuthorizationToken")]
    authorization_token: AuthorizationToken,
}

#[derive(Debug, Deserialize)]
struct AuthorizationToken {
    #[serde(rename = "Token")]
    token: String,
    #[serde(rename = "DisplayClaims")]
    display_claims: DisplayClaims,
}

#[derive(Debug, Deserialize)]
struct DisplayClaims {
    xui: Vec<UserHashClaim>,
}

#[derive(Debug, Deserialize)]
struct UserHashClaim {
    uhs: String,
}

#[derive(Debug, Deserialize)]
struct MinecraftLauncherLoginResponse {
    access_token: String,
    expires_in: u64,
}

#[derive(Debug, Deserialize)]
struct MinecraftProfile {
    id: String,
    name: String,
}

fn print_help() {
    println!("usage: minecraft-auth <ensure|show|logout> [options]");
    println!();
    println!("commands:");
    println!("  ensure  Ensure a valid Minecraft access token exists");
    println!("  show    Show cached auth metadata");
    println!("  logout  Delete cached auth state");
    println!();
    println!("options:");
    println!("  --account <name>      Auth state name (default: default)");
    println!("  --json                Print session JSON for `ensure`");
    println!("  --reauth              Ignore saved refresh token");
    println!("  --no-open-browser     Do not call xdg-open");
    println!("  -h, --help            Show this help");
}

fn parse_args() -> Result<Args, AuthError> {
    let mut iter = env::args().skip(1);
    let Some(command) = iter.next() else {
        print_help();
        process::exit(0);
    };

    if command == "-h" || command == "--help" {
        print_help();
        process::exit(0);
    }

    let command = match command.as_str() {
        "ensure" => CommandKind::Ensure,
        "show" => CommandKind::Show,
        "logout" => CommandKind::Logout,
        other => {
            return Err(AuthError::Message(format!(
                "unknown command '{other}'"
            )));
        }
    };

    let mut args = Args {
        command,
        account: "default".to_string(),
        json: false,
        reauth: false,
        no_open_browser: false,
    };

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--account" => {
                let Some(value) = iter.next() else {
                    return Err(AuthError::Message(
                        "--account requires a value".to_string(),
                    ));
                };
                args.account = value;
            }
            "--json" => args.json = true,
            "--reauth" => args.reauth = true,
            "--no-open-browser" => args.no_open_browser = true,
            "-h" | "--help" => {
                print_help();
                process::exit(0);
            }
            other => {
                return Err(AuthError::Message(format!(
                    "unknown option '{other}'"
                )));
            }
        }
    }

    Ok(args)
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::from_secs(0))
        .as_secs()
}

fn windows_timestamp() -> u64 {
    (now_unix() + 11_644_473_600) * 10_000_000
}

fn data_home() -> PathBuf {
    if let Some(path) = env::var_os("XDG_DATA_HOME") {
        return PathBuf::from(path);
    }
    PathBuf::from(env::var_os("HOME").unwrap_or_default())
        .join(".local")
        .join("share")
}

fn state_path(account: &str) -> PathBuf {
    data_home()
        .join("minecraft-auth")
        .join(format!("{account}.json"))
}

fn load_state(path: &Path) -> Result<State, AuthError> {
    if !path.exists() {
        return Ok(State {
            version: STATE_VERSION,
            ..State::default()
        });
    }

    let mut state: State = serde_json::from_str(&fs::read_to_string(path)?)?;
    if state.version == 0 {
        state.version = STATE_VERSION;
    }
    Ok(state)
}

fn save_state(path: &Path, state: &State) -> Result<(), AuthError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let tmp_path = path.with_extension("tmp");
    fs::write(&tmp_path, serde_json::to_vec_pretty(state)?)?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&tmp_path, fs::Permissions::from_mode(0o600))?;
    }

    fs::rename(tmp_path, path)?;
    Ok(())
}

fn ensure_device_identity(state: &mut State) -> Result<(Uuid, SigningKey), AuthError> {
    let device_id = match state.device_id.as_deref() {
        Some(value) => Uuid::parse_str(value)
            .map_err(|err| AuthError::Message(format!("invalid stored device id: {err}")))?,
        None => {
            let value = Uuid::new_v4();
            state.device_id = Some(value.to_string());
            value
        }
    };

    let signing_key = match state.device_key_pem.as_deref() {
        Some(pem) => SigningKey::from_pkcs8_pem(pem)?,
        None => {
            let key = SigningKey::random(&mut p256::elliptic_curve::rand_core::OsRng);
            state.device_key_pem = Some(key.to_pkcs8_pem(LineEnding::LF)?.to_string());
            key
        }
    };

    Ok((device_id, signing_key))
}

async fn request_form<T>(
    client: &Client,
    url: &str,
    params: &[(&str, &str)],
) -> Result<T, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    let body = serde_urlencoded::to_string(params)
        .map_err(|err| AuthError::Message(err.to_string()))?;
    let response = client
        .post(url)
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .body(body)
        .send()
        .await?;
    parse_response(response).await
}

async fn parse_response<T>(response: reqwest::Response) -> Result<T, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    let status = response.status();
    let body = response.text().await?;
    let json: Value = serde_json::from_str(&body)?;

    if !status.is_success() {
        let error = json.get("error").and_then(Value::as_str);
        let description = json.get("error_description").and_then(Value::as_str);
        let message = match (error, description) {
            (Some(error), Some(description)) => format!("{error}: {description}"),
            (Some(error), None) => error.to_string(),
            (None, Some(description)) => description.to_string(),
            (None, None) => json
                .get("Message")
                .and_then(Value::as_str)
                .unwrap_or(body.as_str())
                .to_string(),
        };
        return Err(AuthError::Message(message));
    }

    Ok(serde_json::from_value(json)?)
}

async fn request_device_code(client: &Client) -> Result<DeviceCodeResponse, AuthError> {
    request_form(
        client,
        LIVE_DEVICE_CODE_URL,
        &[
            ("client_id", CLIENT_ID),
            ("scope", SCOPE),
            ("response_type", "device_code"),
        ],
    )
    .await
}

async fn refresh_live_token(
    client: &Client,
    refresh_token: &str,
) -> Result<LiveTokenResponse, AuthError> {
    request_form(
        client,
        LIVE_TOKEN_URL,
        &[
            ("client_id", CLIENT_ID),
            ("scope", SCOPE),
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh_token),
        ],
    )
    .await
}

async fn exchange_device_code(
    client: &Client,
    device_code: &str,
) -> Result<LiveTokenResponse, AuthError> {
    request_form(
        client,
        LIVE_TOKEN_URL,
        &[
            ("client_id", CLIENT_ID),
            ("grant_type", "device_code"),
            ("device_code", device_code),
        ],
    )
    .await
}

fn maybe_open_browser(url: &str, open_browser: bool) {
    if !open_browser {
        return;
    }

    let _ = Command::new("xdg-open")
        .arg(url)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

async fn acquire_live_token(
    client: &Client,
    state: &State,
    reauth: bool,
    open_browser: bool,
) -> Result<LiveTokenResponse, AuthError> {
    if !reauth {
        if let Some(refresh_token) = state.refresh_token.as_deref() {
            if let Ok(token) = refresh_live_token(client, refresh_token).await {
                return Ok(token);
            }
        }
    }

    let device_code = request_device_code(client).await?;
    let mut interval = device_code.interval.unwrap_or(5).max(1);
    let expires_at = now_unix() + device_code.expires_in;

    eprintln!("Microsoft login required for Minecraft.");
    eprintln!("Open: {}", device_code.verification_uri);
    eprintln!("Enter code: {}", device_code.user_code);
    maybe_open_browser(&device_code.verification_uri, open_browser);

    while now_unix() < expires_at {
        match exchange_device_code(client, &device_code.device_code).await {
            Ok(token) => return Ok(token),
            Err(AuthError::Message(message))
                if message.contains("authorization_pending") =>
            {
                sleep(Duration::from_secs(interval)).await;
            }
            Err(AuthError::Message(message)) if message.contains("slow_down") => {
                interval += 1;
                sleep(Duration::from_secs(interval)).await;
            }
            Err(err) => return Err(err),
        }
    }

    Err(AuthError::Message(
        "Device code login timed out".to_string(),
    ))
}

fn proof_key(signing_key: &SigningKey) -> Value {
    let encoded = signing_key.verifying_key().to_encoded_point(false);
    let x = encoded.x().expect("p256 uncompressed public key includes x");
    let y = encoded.y().expect("p256 uncompressed public key includes y");
    json!({
        "kty": "EC",
        "alg": "ES256",
        "crv": "P-256",
        "use": "sig",
        "x": URL_SAFE_NO_PAD.encode(x),
        "y": URL_SAFE_NO_PAD.encode(y),
    })
}

fn signature_header(
    method: &str,
    url: &str,
    body: &[u8],
    authorization: Option<&str>,
    signing_key: &SigningKey,
) -> Result<String, AuthError> {
    let parsed = reqwest::Url::parse(url)
        .map_err(|err| AuthError::Message(format!("invalid URL '{url}': {err}")))?;
    let timestamp = windows_timestamp();
    let path_and_query = if let Some(query) = parsed.query() {
        format!("{}?{query}", parsed.path())
    } else {
        parsed.path().to_string()
    };

    let mut signed_payload = Vec::new();
    signed_payload.extend_from_slice(&1u32.to_be_bytes());
    signed_payload.push(0);
    signed_payload.extend_from_slice(&timestamp.to_be_bytes());
    signed_payload.push(0);
    signed_payload.extend_from_slice(method.as_bytes());
    signed_payload.push(0);
    signed_payload.extend_from_slice(path_and_query.as_bytes());
    signed_payload.push(0);
    if let Some(value) = authorization {
        signed_payload.extend_from_slice(value.as_bytes());
    }
    signed_payload.push(0);
    signed_payload.extend_from_slice(body);
    signed_payload.push(0);

    let digest = Sha256::digest(&signed_payload);
    let signature: Signature = signing_key.sign_prehash(&digest)?;

    let mut header = Vec::new();
    header.extend_from_slice(&1u32.to_be_bytes());
    header.extend_from_slice(&timestamp.to_be_bytes());
    header.extend_from_slice(signature.to_bytes().as_ref());
    Ok(BASE64_STANDARD.encode(header))
}

async fn signed_json_post<T>(
    client: &Client,
    url: &str,
    payload: &Value,
    signing_key: &SigningKey,
    extra_headers: &[(&str, &str)],
) -> Result<T, AuthError>
where
    T: for<'de> Deserialize<'de>,
{
    let body = serde_json::to_vec(payload)?;
    let signature = signature_header("POST", url, &body, None, signing_key)?;
    let mut request = client
        .post(url)
        .header(CONTENT_TYPE, "application/json")
        .header("Accept", "application/json")
        .header("Signature", signature)
        .body(body);

    for (name, value) in extra_headers {
        request = request.header(*name, *value);
    }

    let response = request.send().await?;
    parse_response(response).await
}

async fn authenticate_device(
    client: &Client,
    device_id: Uuid,
    signing_key: &SigningKey,
) -> Result<DeviceTokenResponse, AuthError> {
    signed_json_post(
        client,
        XBOX_DEVICE_AUTH_URL,
        &json!({
            "Properties": {
                "DeviceType": DEVICE_TYPE,
                "Id": format!("{{{device_id}}}"),
                "AuthMethod": "ProofOfPossession",
                "ProofKey": proof_key(signing_key),
            },
            "RelyingParty": XBOX_AUTH_RELYING_PARTY,
            "TokenType": "JWT",
        }),
        signing_key,
        &[("x-xbl-contract-version", "1")],
    )
    .await
}

async fn sisu_authorize(
    client: &Client,
    msa_access_token: &str,
    device_token: &str,
    signing_key: &SigningKey,
) -> Result<SisuResponse, AuthError> {
    signed_json_post(
        client,
        XBOX_SISU_URL,
        &json!({
            "Sandbox": "RETAIL",
            "UseModernGamertag": true,
            "AppId": CLIENT_ID,
            "AccessToken": format!("t={msa_access_token}"),
            "DeviceToken": device_token,
            "ProofKey": proof_key(signing_key),
            "RelyingParty": JAVA_XSTS_RELYING_PARTY,
        }),
        signing_key,
        &[],
    )
    .await
}

async fn minecraft_launcher_login(
    client: &Client,
    user_hash: &str,
    xsts_token: &str,
) -> Result<MinecraftLauncherLoginResponse, AuthError> {
    let response = client
        .post(MINECRAFT_LAUNCHER_LOGIN_URL)
        .json(&json!({
            "platform": "PC_LAUNCHER",
            "xtoken": format!("XBL3.0 x={user_hash};{xsts_token}"),
        }))
        .send()
        .await?;
    parse_response(response).await
}

async fn minecraft_profile(
    client: &Client,
    access_token: &str,
) -> Result<MinecraftProfile, AuthError> {
    let response = client
        .get(MINECRAFT_PROFILE_URL)
        .header(AUTHORIZATION, format!("Bearer {access_token}"))
        .send()
        .await?;
    parse_response(response).await
}

fn hyphenate_uuid(value: &str) -> Result<String, AuthError> {
    if value.len() != 32 {
        return Err(AuthError::Message(format!(
            "unexpected Minecraft profile UUID '{value}'"
        )));
    }

    Ok(format!(
        "{}-{}-{}-{}-{}",
        &value[0..8],
        &value[8..12],
        &value[12..16],
        &value[16..20],
        &value[20..32]
    ))
}

async fn ensure_session(
    client: &Client,
    account: &str,
    reauth: bool,
    open_browser: bool,
) -> Result<SessionOutput, AuthError> {
    let path = state_path(account);
    let mut state = load_state(&path)?;
    let (device_id, signing_key) = ensure_device_identity(&mut state)?;
    let live_token = acquire_live_token(client, &state, reauth, open_browser).await?;
    let refresh_token = live_token
        .refresh_token
        .clone()
        .ok_or_else(|| AuthError::Message("Login succeeded without a refresh token".to_string()))?;
    let microsoft_access_token = live_token
        .access_token
        .as_deref()
        .ok_or_else(|| AuthError::Message("Login succeeded without an access token".to_string()))?;

    let device_token = authenticate_device(client, device_id, &signing_key).await?;
    let sisu = sisu_authorize(
        client,
        microsoft_access_token,
        &device_token.token,
        &signing_key,
    )
    .await?;
    let user_hash = sisu
        .authorization_token
        .display_claims
        .xui
        .first()
        .ok_or_else(|| AuthError::Message("missing SISU user hash".to_string()))?
        .uhs
        .clone();
    let minecraft_login = minecraft_launcher_login(
        client,
        &user_hash,
        &sisu.authorization_token.token,
    )
    .await?;
    let profile = minecraft_profile(client, &minecraft_login.access_token).await?;

    let session = SessionOutput {
        username: profile.name.clone(),
        uuid: hyphenate_uuid(&profile.id)?,
        access_token: minecraft_login.access_token,
        access_token_expires_at: now_unix() + minecraft_login.expires_in,
    };

    state.version = STATE_VERSION;
    state.refresh_token = Some(refresh_token);
    state.last_profile = Some(ProfileSummary {
        name: session.username.clone(),
        uuid: session.uuid.clone(),
    });
    state.last_updated_at = Some(now_unix());
    save_state(&path, &state)?;

    Ok(session)
}

fn show_state(account: &str) -> Result<ShowOutput, AuthError> {
    let path = state_path(account);
    if !path.exists() {
        return Err(AuthError::Message(format!(
            "No stored Minecraft auth state for account '{account}'"
        )));
    }

    let state = load_state(&path)?;
    Ok(ShowOutput {
        path: path.display().to_string(),
        last_profile: state.last_profile,
        last_updated_at: state.last_updated_at,
    })
}

fn logout(account: &str) -> Result<(), AuthError> {
    let path = state_path(account);
    if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

#[tokio::main]
async fn main() {
    let args = match parse_args() {
        Ok(args) => args,
        Err(err) => {
            eprintln!("minecraft-auth: {err}");
            process::exit(1);
        }
    };

    let client = match Client::builder().user_agent("minecraft-auth").build() {
        Ok(client) => client,
        Err(err) => {
            eprintln!("minecraft-auth: {err}");
            process::exit(1);
        }
    };

    let result = match args.command {
        CommandKind::Ensure => ensure_session(
            &client,
            &args.account,
            args.reauth,
            !args.no_open_browser,
        )
        .await
        .and_then(|session| {
            if args.json {
                println!("{}", serde_json::to_string(&session)?);
            } else {
                println!("{} {}", session.username, session.uuid);
            }
            Ok(())
        }),
        CommandKind::Show => show_state(&args.account).and_then(|output| {
            println!("{}", serde_json::to_string_pretty(&output)?);
            Ok(())
        }),
        CommandKind::Logout => logout(&args.account),
    };

    if let Err(err) = result {
        eprintln!("minecraft-auth: {err}");
        process::exit(1);
    }
}
