//! io.denden.History.Query: what happened on the machine, from pacman's log,
//! snapper and the journal. (Milestone 7 replaces this with an event log.)

use crate::{Error, invalid, util};
use serde_json::{Value, json};

struct Event {
    time: i64,
    source: &'static str,
    summary: String,
    details: Vec<String>,
}

struct Snapshot {
    config: String,
    number: i64,
    kind: String,
    pre: Option<i64>,
    time: i64,
    description: String,
    cleanup: String,
}

fn snapshots() -> Vec<Snapshot> {
    let all = util::json("snapper", &["--utc", "--jsonout", "list", "--all-configs"]).unwrap_or_default();
    let mut found = Vec::new();
    for (config, list) in all.as_object().into_iter().flatten() {
        for snapshot in list.as_array().into_iter().flatten() {
            let number = snapshot["number"].as_i64().unwrap_or(0);
            let Some((date, time)) = snapshot["date"].as_str().and_then(|stamp| stamp.split_once(' ')) else { continue };
            if number == 0 {
                continue;
            }
            found.push(Snapshot {
                config: config.clone(),
                number,
                kind: snapshot["type"].as_str().unwrap_or_default().into(),
                pre: snapshot["pre-number"].as_i64(),
                time: util::epoch(date, time).unwrap_or(0),
                description: snapshot["description"].as_str().unwrap_or_default().into(),
                cleanup: snapshot["cleanup"].as_str().unwrap_or_default().into(),
            });
        }
    }
    found
}

/// "upgraded 3 packages: a, b, c" with at most a handful of names.
fn phrase(verb: &str, names: &[String]) -> String {
    let shown: Vec<&str> = names.iter().take(6).map(String::as_str).collect();
    let more = names.len().saturating_sub(shown.len());
    let mut text = format!("{verb} {}", shown.join(", "));
    if more > 0 {
        text.push_str(&format!(" and {more} more"));
    }
    text
}

fn transactions(snapshots: &[Snapshot]) -> Vec<Event> {
    let log = std::fs::read_to_string("/var/log/pacman.log").unwrap_or_default();
    let mut events = Vec::new();
    let mut command = String::new();
    let mut open: Option<(i64, Vec<(String, String)>)> = None;
    for line in log.lines() {
        let Some((stamp, rest)) = line.strip_prefix('[').and_then(|line| line.split_once("] ")) else { continue };
        if let Some(run) = rest.strip_prefix("[PACMAN] Running '") {
            command = run.trim_end_matches('\'').to_string();
            continue;
        }
        let Some(message) = rest.strip_prefix("[ALPM] ") else { continue };
        if message == "transaction started" {
            open = Some((util::epoch_iso(stamp).unwrap_or(0), Vec::new()));
        } else if message == "transaction completed" || message == "transaction failed" {
            let Some((time, changes)) = open.take() else { continue };
            if changes.is_empty() {
                continue;
            }
            let mut parts = Vec::new();
            for verb in ["installed", "upgraded", "downgraded", "reinstalled", "removed"] {
                let names: Vec<String> =
                    changes.iter().filter(|(kind, _)| kind == verb).map(|(_, change)| change.split(' ').next().unwrap_or_default().to_string()).collect();
                if !names.is_empty() {
                    parts.push(phrase(verb, &names));
                }
            }
            let mut summary = parts.join("; ");
            if let Some(first) = summary.get(..1) {
                summary = first.to_uppercase() + &summary[1..];
            }
            if message == "transaction failed" {
                summary.push_str(" (failed)");
            }
            let mut details = Vec::new();
            if !command.is_empty() {
                details.push(format!("command: {command}"));
            }
            details.extend(changes.iter().map(|(kind, change)| format!("{kind} {change}")));
            // snap-pac's root snapshots: the pre one is taken just before.
            if let Some(pre) = snapshots
                .iter()
                .filter(|snapshot| snapshot.config == "root" && snapshot.kind == "pre" && (time - 300..=time + 5).contains(&snapshot.time))
                .max_by_key(|snapshot| snapshot.time)
            {
                let post = snapshots.iter().find(|snapshot| snapshot.config == "root" && snapshot.pre == Some(pre.number));
                details.push(match post {
                    Some(post) => format!("root snapshots: {} before, {} after", pre.number, post.number),
                    None => format!("root snapshot: {} before", pre.number),
                });
            }
            events.push(Event { time, source: "packages", summary, details });
            command.clear();
        } else if let Some((verb, change)) = message.split_once(' ') {
            if let Some((_, changes)) = open.as_mut() {
                if ["installed", "upgraded", "downgraded", "reinstalled", "removed"].contains(&verb) {
                    changes.push((verb.to_string(), change.to_string()));
                }
            }
        }
    }
    events
}

fn snapshot_events(snapshots: &[Snapshot]) -> Vec<Event> {
    // Hourly and pacman snapshots are covered elsewhere; these are the rest.
    snapshots
        .iter()
        .filter(|snapshot| snapshot.kind == "single" && snapshot.cleanup != "timeline")
        .map(|snapshot| Event {
            time: snapshot.time,
            source: "snapshot",
            summary: format!("Snapshot {} of {}: {}", snapshot.number, snapshot.config, snapshot.description),
            details: vec![],
        })
        .collect()
}

fn boots() -> Vec<Event> {
    util::json("journalctl", &["--list-boots", "-o", "json", "--no-pager"])
        .and_then(|boots| boots.as_array().cloned())
        .unwrap_or_default()
        .iter()
        .filter_map(|boot| {
            let first = boot["first_entry"].as_i64()? / 1_000_000;
            Some(Event {
                time: first,
                source: "boot",
                summary: "Started".into(),
                details: vec![format!("boot id: {}", boot["boot_id"].as_str().unwrap_or_default())],
            })
        })
        .collect()
}

/// 30m, 12h, 3d, 2w back from now, or YYYY-MM-DD in local time.
fn since(text: &str) -> Option<i64> {
    let unit = text.chars().last()?;
    if let Some(seconds) = match unit {
        'm' => Some(60),
        'h' => Some(3600),
        'd' => Some(86400),
        'w' => Some(7 * 86400),
        _ => None,
    } {
        return Some(util::now() - text[..text.len() - 1].parse::<i64>().ok()? * seconds);
    }
    Some(util::epoch(text, "00:00:00")? - util::local_offset())
}

pub fn query(parameters: &Value) -> Result<Value, Error> {
    let text = match &parameters["text"] {
        Value::Null => None,
        Value::String(text) => Some(text.to_lowercase()),
        _ => return Err(invalid("text")),
    };
    let after = match &parameters["since"] {
        Value::Null => None,
        Value::String(value) => Some(since(value).ok_or_else(|| invalid("since"))?),
        _ => return Err(invalid("since")),
    };
    let limit = match &parameters["limit"] {
        Value::Null => 50,
        value => value.as_u64().filter(|limit| *limit > 0).ok_or_else(|| invalid("limit"))? as usize,
    };
    let snapshots = snapshots();
    let mut events = transactions(&snapshots);
    events.extend(snapshot_events(&snapshots));
    events.extend(boots());
    events.retain(|event| {
        after.is_none_or(|after| event.time >= after)
            && text.as_ref().is_none_or(|text| {
                event.summary.to_lowercase().contains(text) || event.details.iter().any(|detail| detail.to_lowercase().contains(text))
            })
    });
    events.sort_by_key(|event| std::cmp::Reverse(event.time));
    events.truncate(limit);
    let events: Vec<Value> = events
        .into_iter()
        .map(|event| json!({ "time": event.time, "source": event.source, "summary": event.summary, "details": event.details }))
        .collect();
    Ok(json!({ "events": events }))
}
