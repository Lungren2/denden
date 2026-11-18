//! io.denden.Service.Status: systemd units of the system and of the caller.

use crate::{Caller, Error, invalid, util};
use serde_json::{Value, json};
use std::collections::HashMap;

const PROPERTIES: &str = "Id,Description,LoadState,ActiveState,SubState,UnitFileState,Result,StateChangeTimestamp,MainPID";

/// systemctl's arguments for one manager: the system's, or USER's session.
fn manager(user: Option<&str>) -> Vec<String> {
    match user {
        Some(user) => vec!["--user".into(), "-M".into(), format!("{user}@")],
        None => vec![],
    }
}

fn systemctl(user: Option<&str>, args: &[&str]) -> Option<String> {
    let mut all = manager(user);
    all.extend(args.iter().map(|arg| arg.to_string()));
    let all: Vec<&str> = all.iter().map(String::as_str).collect();
    // show exits non-zero for some unknown units but still prints them.
    util::run("systemctl", &all, std::time::Duration::from_secs(20)).map(|output| output.stdout)
}

fn show(user: Option<&str>, names: &[String]) -> Vec<Value> {
    if names.is_empty() {
        return vec![];
    }
    let mut args = vec!["show", "--timestamp=unix", "-p", PROPERTIES, "--"];
    args.extend(names.iter().map(String::as_str));
    let text = systemctl(user, &args).unwrap_or_default();
    text.split("\n\n")
        .filter_map(|block| {
            let fields: HashMap<&str, &str> = block.lines().filter_map(|line| line.split_once('=')).collect();
            let name = fields.get("Id")?;
            if fields.get("LoadState") == Some(&"not-found") {
                return None;
            }
            let since = fields.get("StateChangeTimestamp").and_then(|stamp| stamp.strip_prefix('@')?.parse::<i64>().ok());
            let main_pid = fields.get("MainPID").and_then(|pid| pid.parse::<i64>().ok()).filter(|pid| *pid > 0);
            Some(json!({
                "name": name,
                "scope": if user.is_some() { "user" } else { "system" },
                "description": fields.get("Description").copied().unwrap_or_default(),
                "load": fields.get("LoadState").copied().unwrap_or_default(),
                "active": fields.get("ActiveState").copied().unwrap_or_default(),
                "sub": fields.get("SubState").copied().unwrap_or_default(),
                "enabled": fields.get("UnitFileState").copied().unwrap_or_default(),
                "result": fields.get("Result").copied().unwrap_or_default(),
                "since": since,
                "main_pid": main_pid,
            }))
        })
        .collect()
}

/// Names of the failed units of one manager.
pub fn failed(user: Option<&str>) -> Vec<String> {
    systemctl(user, &["list-units", "--failed", "--plain", "--no-legend", "--full"])
        .unwrap_or_default()
        .lines()
        .filter_map(|line| line.split_whitespace().next().map(str::to_string))
        .collect()
}

pub fn status(parameters: &Value, caller: &Caller) -> Result<Value, Error> {
    let names = match &parameters["names"] {
        Value::Null => vec![],
        Value::Array(names) => names
            .iter()
            .map(|name| name.as_str().filter(|name| !name.starts_with('-')).map(str::to_string))
            .collect::<Option<Vec<_>>>()
            .ok_or_else(|| invalid("names"))?,
        _ => return Err(invalid("names")),
    };
    let only_user = match &parameters["user"] {
        Value::Null => None,
        Value::Bool(user) => Some(*user),
        _ => return Err(invalid("user")),
    };
    let want_failed = match &parameters["failed"] {
        Value::Null => names.is_empty(),
        Value::Bool(failed) => *failed,
        _ => return Err(invalid("failed")),
    };
    let user = caller.user.as_deref();
    let mut managers = vec![];
    if only_user != Some(true) {
        managers.push(None);
    }
    if only_user != Some(false) && user.is_some() {
        managers.push(user);
    }
    let mut units = Vec::new();
    let mut missing = Vec::new();
    if want_failed {
        for &manager in &managers {
            units.extend(show(manager, &failed(manager)));
        }
    }
    let mut pending = names;
    for &manager in &managers {
        let found = show(manager, &pending);
        pending.retain(|name| {
            !found.iter().any(|unit| {
                let id = unit["name"].as_str().unwrap_or_default();
                id == name || id.strip_suffix(".service") == Some(name.as_str())
            })
        });
        units.extend(found);
    }
    missing.extend(pending);
    Ok(json!({ "units": units, "missing": missing }))
}
