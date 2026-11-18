//! Running the commands dend reads the system through, and small parsers.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub struct Output {
    pub code: Option<i32>,
    pub stdout: String,
}

impl Output {
    pub fn ok(&self) -> bool {
        self.code == Some(0)
    }
}

/// Run PROGRAM with ARGS under the C locale and collect its output; None if
/// it can't be started or doesn't finish within TIMEOUT (it is then killed).
pub fn run(program: &str, args: &[&str], timeout: Duration) -> Option<Output> {
    let mut child = Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let mut stdout = child.stdout.take()?;
    let reader = std::thread::spawn(move || {
        let mut text = String::new();
        let _ = stdout.read_to_string(&mut text);
        text
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    };
    Some(Output { code: status.code(), stdout: reader.join().unwrap_or_default() })
}

/// Standard output of a command that succeeded.
pub fn output(program: &str, args: &[&str]) -> Option<String> {
    run(program, args, Duration::from_secs(20)).filter(Output::ok).map(|output| output.stdout)
}

pub fn json(program: &str, args: &[&str]) -> Option<serde_json::Value> {
    serde_json::from_str(&output(program, args)?).ok()
}

pub fn read(path: &str) -> String {
    std::fs::read_to_string(path).map(|text| text.trim().to_string()).unwrap_or_default()
}

pub fn user_name(uid: u32) -> Option<String> {
    std::fs::read_to_string("/etc/passwd").ok()?.lines().find_map(|line| {
        let fields: Vec<&str> = line.split(':').collect();
        (fields.len() > 2 && fields[2].parse() == Ok(uid)).then(|| fields[0].to_string())
    })
}

pub fn home(user: &str) -> Option<String> {
    std::fs::read_to_string("/etc/passwd").ok()?.lines().find_map(|line| {
        let fields: Vec<&str> = line.split(':').collect();
        (fields.len() > 5 && fields[0] == user).then(|| fields[5].to_string())
    })
}

pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0)
}

/// Days since 1970-01-01 of a civil date (Howard Hinnant's algorithm).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146097 + day_of_era - 719468
}

/// Seconds since the epoch of "YYYY-MM-DD" and "HH:MM:SS" in UTC.
pub fn epoch(date: &str, time: &str) -> Option<i64> {
    let mut d = date.splitn(3, '-').map(|part| part.parse::<i64>());
    let (year, month, day) = (d.next()?.ok()?, d.next()?.ok()?, d.next()?.ok()?);
    let mut t = time.splitn(3, ':').map(|part| part.parse::<i64>());
    let hour = t.next().and_then(Result::ok).unwrap_or(0);
    let minute = t.next().and_then(Result::ok).unwrap_or(0);
    let second = t.next().and_then(Result::ok).unwrap_or(0);
    Some(days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second)
}

/// pacman's log timestamps: 2026-11-18T17:19:45+0200.
pub fn epoch_iso(stamp: &str) -> Option<i64> {
    let (date, rest) = stamp.split_once('T')?;
    let (time, offset) = rest.split_at(rest.find(['+', '-']).unwrap_or(rest.len()));
    let seconds = epoch(date, time)?;
    let offset = if offset.len() == 5 {
        let sign = if offset.starts_with('-') { -1 } else { 1 };
        sign * (offset[1..3].parse::<i64>().ok()? * 3600 + offset[3..5].parse::<i64>().ok()? * 60)
    } else {
        0
    };
    Some(seconds - offset)
}

/// This machine's current offset from UTC, in seconds.
pub fn local_offset() -> i64 {
    let now = now() as libc::time_t;
    // SAFETY: localtime_r writes one tm.
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&now, &mut tm) };
    tm.tm_gmtoff
}

pub struct Space {
    pub size: u64,
    pub available: u64,
}

pub fn space(path: &str) -> Option<Space> {
    let path = std::ffi::CString::new(path).ok()?;
    // SAFETY: statvfs fills one struct statvfs.
    let mut stats: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(path.as_ptr(), &mut stats) } != 0 {
        return None;
    }
    let block = stats.f_frsize as u64;
    Some(Space { size: stats.f_blocks as u64 * block, available: stats.f_bavail as u64 * block })
}

/// 238.5 GB, as a person reads sizes.
pub fn bytes(size: u64) -> String {
    let units = ["bytes", "KB", "MB", "GB", "TB"];
    let mut value = size as f64;
    let mut unit = 0;
    while value >= 1000.0 && unit < units.len() - 1 {
        value /= 1000.0;
        unit += 1;
    }
    if unit == 0 { format!("{size} bytes") } else { format!("{value:.1} {}", units[unit]) }
}
