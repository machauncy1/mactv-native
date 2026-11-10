//! App-owned receiver. NDJSON over inherited pipes is the only local control API.
//! No keyboard/mouse injection, system volume API, or network debug server.
use atv_core::{AtvConfig, AtvDelegate, AtvServer, EventKind, TrackpadMode};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{collections::HashMap, io::{self, BufRead, Write}, path::PathBuf,
    sync::{Arc, Mutex}, time::{Duration, Instant}};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    name: String,
    pin: u32,
    server_id: String,
    device_id: String,
    private_key: String,
    state_directory: PathBuf,
}

fn emit(value: Value) {
    let stdout = io::stdout();
    let mut out = stdout.lock();
    let _ = writeln!(out, "{value}");
    let _ = out.flush();
}

struct Host {
    connections: Mutex<HashMap<u64, bool>>,
    audio: Mutex<(f64, bool)>,
    pairings: Mutex<HashMap<String, Vec<u8>>>,
    pairing_path: PathBuf,
    pairing_until: Mutex<Option<Instant>>,
}

impl Host {
    fn load(directory: &PathBuf) -> io::Result<Self> {
        std::fs::create_dir_all(directory)?;
        std::fs::set_permissions(directory, std::fs::Permissions::from_mode(0o700))?;
        let pairing_path = directory.join("controllers.json");
        let pairings: HashMap<String, Vec<u8>> = match std::fs::read(&pairing_path) {
            Ok(bytes) => serde_json::from_slice(&bytes).map_err(io::Error::other)?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => HashMap::new(),
            Err(e) => return Err(e),
        };
        let pairing_until = if pairings.is_empty() {Some(Instant::now() + Duration::from_secs(300))} else {None};
        Ok(Self { connections: Mutex::new(HashMap::new()), audio: Mutex::new((0.8, false)),
            pairings: Mutex::new(pairings), pairing_path, pairing_until: Mutex::new(pairing_until) })
    }
}

fn map_command(name: &str) -> Option<&'static str> {
    Some(match name {
        "up" => "up", "down" => "down", "left" => "left", "right" => "right",
        "select" => "select", "menu" => "back", "home" => "home",
        "play_pause" | "play" | "pause" => "playPause",
        "volume_up" => "volumeUp", "volume_down" => "volumeDown", "mute" => "mute",
        "fast_forward" | "next" | "next_track" => "skipForward",
        "rewind" | "prev" | "previous" | "prev_track" => "skipBackward",
        _ => return None, // Power/Siri never control the desktop or other apps.
    })
}

impl AtvDelegate for Host {
    fn on_button(&self, name: &str) {
        if let Some(command) = map_command(name) {
            // Update synchronously so Companion replies contain the new volume.
            let mut audio = self.audio.lock().unwrap();
            match command {
                "volumeUp" => { audio.0 = (audio.0 + 0.05).min(1.0); audio.1 = false; }
                "volumeDown" => { audio.0 = (audio.0 - 0.05).max(0.0); audio.1 = false; }
                "mute" => audio.1 = !audio.1,
                _ => {}
            }
            drop(audio);
            emit(json!({"type":"command", "command":command}));
        }
    }
    fn on_audio(&self, volume: f64, muted: bool) {
        if !volume.is_finite() { return; }
        let volume = volume.clamp(0.0, 1.0);
        *self.audio.lock().unwrap() = (volume, muted);
        emit(json!({"type":"audio", "volume":volume, "muted":muted}));
    }
    fn get_audio_state(&self) -> Option<(f64, bool)> { Some(*self.audio.lock().unwrap()) }
    fn pairing_allowed(&self) -> bool {
        self.pairing_until.lock().unwrap().is_some_and(|until| Instant::now() < until)
    }
    fn store_pairing(&self, identifier: &[u8], public_key: &[u8]) -> bool {
        if !self.pairing_allowed() || public_key.len() != 32 || identifier.is_empty() { return false; }
        let mut pairings = self.pairings.lock().unwrap();
        let mut next = pairings.clone();
        next.insert(hex::encode(identifier), public_key.to_vec());
        let persist = || -> io::Result<()> {
            let temp = self.pairing_path.with_extension("tmp");
            let mut file = std::fs::OpenOptions::new().create(true).truncate(true).write(true).mode(0o600).open(&temp)?;
            file.write_all(&serde_json::to_vec(&next)?)?;
            file.sync_all()?;
            std::fs::rename(temp, &self.pairing_path)
        };
        if persist().is_err() { return false; }
        *pairings = next;
        *self.pairing_until.lock().unwrap() = None;
        emit(json!({"type":"paired"}));
        true
    }
    fn paired_key(&self, identifier: &[u8]) -> Option<Vec<u8>> {
        self.pairings.lock().unwrap().get(&hex::encode(identifier)).cloned()
    }
    fn on_connection_state(&self, id: u64, connected: bool, ready: bool) {
        let mut connections = self.connections.lock().unwrap();
        if connected { connections.insert(id, ready); } else { connections.remove(&id); }
        emit(json!({"type":"connection", "connected":!connections.is_empty(),
            "ready":connections.values().any(|ready| *ready)}));
    }
    fn on_event(&self, _kind: EventKind, _detail: &str) {}
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let (tx, mut rx) = tokio::sync::mpsc::channel::<String>(64);
    std::thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            match line {
                Ok(line) if line.len() <= 64 * 1024 => if tx.blocking_send(line).is_err() { break; },
                _ => break,
            }
        }
    });
    let first = rx.recv().await.ok_or("missing host configuration")?;
    let config: Config = serde_json::from_str(&first)?;
    if config.name.trim().is_empty() || config.name.len() > 120 || config.pin > 9999 { return Err("invalid host configuration".into()); }
    let key: [u8; 32] = hex::decode(&config.private_key)?.try_into().map_err(|_| "invalid identity key")?;
    let host = Arc::new(Host::load(&config.state_directory)?);
    let config = AtvConfig {
        name: config.name, pin: config.pin, ip: None, mouse_mode: false,
        trackpad_mode: TrackpadMode::Direction, ui_port: None, mouse_speed: 0.5,
        device_id: Some(config.device_id), server_identifier: Some(config.server_id), private_key: Some(key),
    };
    let server = AtvServer::start(config, host.clone()).await?;
    emit(json!({"type":"started", "pairingOpen":host.pairing_allowed(), "companionPort":server.companion_port()}));
    let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    loop {
        tokio::select! {
            line = rx.recv() => {
                let Some(line) = line else { break; }; // Parent exit closes stdin: no orphan receiver.
                let Ok(message) = serde_json::from_str::<Value>(&line) else { continue; };
                match message["type"].as_str() {
                    Some("stop") => break,
                    Some("audio") => {
                        if let (Some(volume), Some(muted)) = (message["volume"].as_f64(), message["muted"].as_bool()) {
                            *host.audio.lock().unwrap() = (volume.clamp(0.0, 1.0), muted);
                        }
                    }
                    Some("pair") => {
                        *host.pairing_until.lock().unwrap() = Some(Instant::now() + Duration::from_secs(300));
                        emit(json!({"type":"pairing", "open":true}));
                    }
                    _ => {}
                }
            }
            _ = terminate.recv() => break,
            _ = tokio::signal::ctrl_c() => break,
        }
    }
    server.stop().await;
    emit(json!({"type":"stopped"}));
    Ok(())
}

#[tokio::main]
async fn main() {
    if let Err(error) = run().await {
        emit(json!({"type":"error", "message":error.to_string()}));
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn routes_only_app_commands() {
        assert_eq!(map_command("menu"), Some("back"));
        assert_eq!(map_command("home"), Some("home"));
        assert_eq!(map_command("play_pause"), Some("playPause"));
        for unsupported in ["power", "siri", "sleep", "wake", "unknown:99"] {
            assert!(map_command(unsupported).is_none());
        }
    }
    #[test]
    fn stores_pairings_across_restart_and_closes_window() {
        let dir = std::env::temp_dir().join(format!("mactv-pair-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let host = Host::load(&dir).unwrap();
        assert!(host.pairing_allowed());
        assert!(host.store_pairing(b"phone", &[9; 32]));
        assert!(!host.pairing_allowed());
        assert!(!host.store_pairing(b"uninvited", &[8; 32]));
        let restored = Host::load(&dir).unwrap();
        assert_eq!(restored.paired_key(b"phone"), Some(vec![9; 32]));
        assert!(restored.paired_key(b"stranger").is_none());
        assert!(!restored.pairing_allowed());
        assert_eq!(std::fs::metadata(dir.join("controllers.json")).unwrap().permissions().mode() & 0o777, 0o600);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
