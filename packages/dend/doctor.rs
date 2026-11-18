//! io.denden.Machine.Doctor: is the machine healthy, and what needs a look.

use crate::{Caller, machine, service, util};
use serde_json::{Value, json};
use std::time::Duration;

#[derive(Clone, Copy, PartialEq, PartialOrd)]
enum Status {
    Ok,
    Warn,
    Fail,
}

impl Status {
    fn name(self) -> &'static str {
        match self {
            Status::Ok => "ok",
            Status::Warn => "warn",
            Status::Fail => "fail",
        }
    }
}

struct Check {
    id: &'static str,
    title: &'static str,
    status: Status,
    detail: String,
}

fn check(id: &'static str, title: &'static str, status: Status, detail: impl Into<String>) -> Check {
    Check { id, title, status, detail: detail.into() }
}

/// Free space of /, /home, /src and /boot; subvolumes of one Btrfs
/// filesystem are reported once.
fn disk_space() -> Check {
    let mut seen = Vec::new();
    let mut parts = Vec::new();
    let mut status = Status::Ok;
    for mount in ["/", "/home", "/src", "/boot"] {
        let Some(space) = util::space(mount) else { continue };
        if space.size == 0 || seen.contains(&(space.size, space.available)) {
            continue;
        }
        seen.push((space.size, space.available));
        let free = space.available as f64 / space.size as f64;
        let large = space.size > 50_000_000_000;
        let worst = if free < 0.05 {
            Status::Fail
        } else if free < 0.15 || (large && space.available < 10_000_000_000) {
            Status::Warn
        } else {
            Status::Ok
        };
        if worst > status {
            status = worst;
        }
        parts.push(format!("{mount} {} free of {}", util::bytes(space.available), util::bytes(space.size)));
    }
    check("disk-space", "Disk space", status, parts.join("; "))
}

/// SMART health of every fixed disk (read-only queries).
fn disk_health() -> Check {
    let mut parts = Vec::new();
    let mut status = Status::Ok;
    for disk in machine::disks() {
        if disk["removable"].as_bool() == Some(true) {
            continue;
        }
        let name = disk["name"].as_str().unwrap_or_default();
        let model = disk["model"].as_str().filter(|model| !model.is_empty()).unwrap_or(name).to_string();
        // smartctl's exit code is a bit mask of findings; its JSON says more.
        let Some(output) = util::run("smartctl", &["-j", "-H", "-A", &format!("/dev/{name}")], Duration::from_secs(20)) else {
            parts.push(format!("{model}: couldn't be read"));
            status = status.max_with(Status::Warn);
            continue;
        };
        let report: Value = serde_json::from_str(&output.stdout).unwrap_or_default();
        let mut notes = Vec::new();
        let mut worst = Status::Ok;
        match report["smart_status"]["passed"].as_bool() {
            Some(true) => {}
            Some(false) => {
                worst = Status::Fail;
                notes.push("failing its health check; back up now".to_string());
            }
            None => {
                worst = Status::Warn;
                notes.push("no health report".to_string());
            }
        }
        let nvme = &report["nvme_smart_health_information_log"];
        if let Some(used) = nvme["percentage_used"].as_u64() {
            notes.push(format!("{used}% worn"));
            if used >= 90 {
                worst = worst.max_with(Status::Warn);
            }
        }
        if let (Some(spare), Some(threshold)) = (nvme["available_spare"].as_u64(), nvme["available_spare_threshold"].as_u64()) {
            if spare <= threshold {
                worst = Status::Fail;
                notes.push("out of spare blocks".to_string());
            }
        }
        if nvme["critical_warning"].as_u64().is_some_and(|warning| warning != 0) {
            worst = worst.max_with(Status::Warn);
            notes.push("reports a critical warning".to_string());
        }
        if worst == Status::Ok {
            notes.insert(0, "healthy".to_string());
        }
        status = status.max_with(worst);
        parts.push(format!("{model}: {}", notes.join(", ")));
    }
    check("disk-health", "Disk health", status, parts.join("; "))
}

impl Status {
    fn max_with(self, other: Status) -> Status {
        if other > self { other } else { self }
    }
}

fn failed_units(caller: &Caller) -> Check {
    let mut failed = service::failed(None);
    if let Some(user) = caller.user.as_deref() {
        failed.extend(service::failed(Some(user)).into_iter().map(|unit| format!("{unit} (user)")));
    }
    if failed.is_empty() {
        check("failed-units", "Services", Status::Ok, "none have failed")
    } else {
        check("failed-units", "Services", Status::Warn, format!("failed: {}", failed.join(", ")))
    }
}

/// T3 Code's desktop app (or its headless server) running for the caller.
fn t3code(caller: &Caller) -> Check {
    if caller.user.is_none() {
        return check("t3code", "T3 Code", Status::Ok, "not checked for this caller");
    }
    let running = std::fs::read_dir("/proc").into_iter().flatten().flatten().any(|entry| {
        let path = entry.path();
        let owner = std::fs::read_to_string(path.join("status")).ok().and_then(|status| {
            status.lines().find_map(|line| line.strip_prefix("Uid:")?.split_whitespace().next()?.parse::<u32>().ok())
        });
        owner == Some(caller.uid)
            && std::fs::read_link(path.join("exe")).is_ok_and(|exe| {
                exe.starts_with("/opt/t3code-desktop") || exe.starts_with("/opt/t3code-cli") || exe.starts_with("/opt/t3code-cli-bin")
            })
    });
    if running {
        check("t3code", "T3 Code", Status::Ok, "running")
    } else {
        check("t3code", "T3 Code", Status::Warn, "not running")
    }
}

fn tailscale() -> Check {
    let Some(status) = util::json("tailscale", &["status", "--json"]) else {
        return check("tailscale", "Tailscale", Status::Warn, "not running, so this machine can't be reached remotely");
    };
    match status["BackendState"].as_str() {
        Some("Running") => {
            let host = status["Self"]["HostName"].as_str().unwrap_or_default();
            let address = status["Self"]["TailscaleIPs"][0].as_str().unwrap_or_default();
            check("tailscale", "Tailscale", Status::Ok, format!("connected as {host} ({address})"))
        }
        Some("NeedsLogin") => check("tailscale", "Tailscale", Status::Warn, "signed out"),
        Some("Stopped") => check("tailscale", "Tailscale", Status::Warn, "turned off"),
        Some(state) => check("tailscale", "Tailscale", Status::Warn, format!("not connected ({state})")),
        None => check("tailscale", "Tailscale", Status::Warn, "no status"),
    }
}

/// The last backup to the Den Den USB stick; overdue after three days, as
/// the reminder says.
fn backups() -> Check {
    if !std::path::Path::new("/etc/denden/backup.conf").exists() {
        return check("backups", "Backups", Status::Warn, "not set up");
    }
    let Some(last) = util::read("/var/lib/denden-backup/last-success").parse::<i64>().ok() else {
        return check("backups", "Backups", Status::Fail, "no backup has finished yet");
    };
    let days = (util::now() - last) / 86400;
    let when = match days {
        0 => "today".to_string(),
        1 => "yesterday".to_string(),
        days => format!("{days} days ago"),
    };
    let status = if days >= 7 { Status::Fail } else if days >= 3 { Status::Warn } else { Status::Ok };
    check("backups", "Backups", status, format!("last backup {when}"))
}

/// Root snapshots around every pacman transaction, and the timers that take
/// and prune the hourly ones.
fn snapshots() -> Check {
    let mut problems = Vec::new();
    if !util::run("pacman", &["-Q", "snap-pac"], Duration::from_secs(10)).is_some_and(|output| output.ok()) {
        problems.push("snap-pac isn't installed, so package changes aren't snapshotted".to_string());
    }
    for timer in ["snapper-timeline.timer", "snapper-cleanup.timer"] {
        if !util::run("systemctl", &["is-active", "--quiet", timer], Duration::from_secs(10)).is_some_and(|output| output.ok()) {
            problems.push(format!("{timer} isn't running"));
        }
    }
    if problems.is_empty() {
        check("snapshots", "Snapshots", Status::Ok, "taken around package changes and hourly")
    } else {
        check("snapshots", "Snapshots", Status::Fail, problems.join("; "))
    }
}

/// The caller's last daily update check (denden-updates.timer), and a pacman
/// database lock that no pacman holds.
fn updates(caller: &Caller) -> Check {
    let pacman_running = std::fs::read_dir("/proc").into_iter().flatten().flatten().any(|entry| {
        std::fs::read_to_string(entry.path().join("comm")).is_ok_and(|name| name.trim() == "pacman")
    });
    if std::path::Path::new("/var/lib/pacman/db.lck").exists() && !pacman_running {
        return check(
            "updates",
            "Updates",
            Status::Warn,
            "pacman's database is locked by a pacman that isn't running (/var/lib/pacman/db.lck)",
        );
    }
    let Some(home) = caller.user.as_deref().and_then(util::home) else {
        return check("updates", "Updates", Status::Ok, "not checked for this caller");
    };
    let path = format!("{home}/.local/state/denden/updates.json");
    let Ok(text) = std::fs::read_to_string(&path) else {
        return check("updates", "Updates", Status::Warn, "the daily update check hasn't run yet");
    };
    let report: Value = serde_json::from_str(&text).unwrap_or_default();
    let age = std::fs::metadata(&path)
        .and_then(|meta| meta.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .map(|elapsed| elapsed.as_secs() / 86400)
        .unwrap_or(0);
    let count = |key: &str| report[key].as_array().map(Vec::len).unwrap_or(0);
    if count("errors") > 0 {
        check("updates", "Updates", Status::Warn, "the last update check couldn't finish (denden-update check)")
    } else if age >= 3 {
        check("updates", "Updates", Status::Warn, format!("the daily update check last ran {age} days ago"))
    } else if count("updates") > 0 {
        check("updates", "Updates", Status::Warn, format!("{} Den Den package changes need attention (denden-update check)", count("updates")))
    } else {
        check("updates", "Updates", Status::Ok, "Den Den packages are up to date")
    }
}

pub fn doctor(caller: &Caller) -> Value {
    // The slow checks (SMART, systemd, Tailscale) run side by side.
    let checks: Vec<Check> = std::thread::scope(|scope| {
        let tasks = vec![
            scope.spawn(disk_space),
            scope.spawn(disk_health),
            scope.spawn(|| failed_units(caller)),
            scope.spawn(|| t3code(caller)),
            scope.spawn(tailscale),
            scope.spawn(backups),
            scope.spawn(snapshots),
            scope.spawn(|| updates(caller)),
        ];
        tasks.into_iter().filter_map(|task| task.join().ok()).collect()
    });
    let status = checks.iter().fold(Status::Ok, |worst, check| worst.max_with(check.status));
    json!({
        "status": status.name(),
        "checks": checks
            .iter()
            .map(|check| json!({ "id": check.id, "title": check.title, "status": check.status.name(), "detail": check.detail }))
            .collect::<Vec<_>>(),
    })
}
