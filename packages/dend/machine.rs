//! io.denden.Machine.Inspect: hardware, kernel, firmware and storage.

use crate::util;
use serde_json::{Value, json};

fn os_release(key: &str) -> Option<String> {
    let text = std::fs::read_to_string("/etc/os-release").ok()?;
    text.lines().find_map(|line| {
        line.strip_prefix(key)?.strip_prefix('=').map(|value| value.trim_matches('"').to_string())
    })
}

fn cpu() -> (String, usize) {
    let info = std::fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
    let model = info
        .lines()
        .find_map(|line| line.strip_prefix("model name")?.split_once(':').map(|(_, model)| model.trim().to_string()))
        .unwrap_or_default();
    let threads = info.lines().filter(|line| line.starts_with("processor")).count();
    (model, threads)
}

fn memory() -> (u64, u64) {
    let info = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let field = |name: &str| {
        info.lines()
            .find_map(|line| line.strip_prefix(name)?.trim().trim_end_matches(" kB").trim().parse::<u64>().ok())
            .unwrap_or(0)
            * 1024
    };
    (field("MemTotal:"), field("MemAvailable:"))
}

fn gpus() -> Vec<String> {
    // lspci -mm: "slot" "class" "vendor" "device" ...; display controllers only.
    util::output("lspci", &["-mm"])
        .unwrap_or_default()
        .lines()
        .filter_map(|line| {
            let fields: Vec<&str> = line.split('"').skip(1).step_by(2).collect();
            let class = fields.first()?;
            if !(class.contains("VGA") || class.contains("3D") || class.contains("Display")) {
                return None;
            }
            Some(format!("{} {}", fields.get(1)?, fields.get(2)?))
        })
        .collect()
}

fn holds_root(device: &Value) -> bool {
    device["mountpoints"].as_array().is_some_and(|mounts| mounts.iter().any(|mount| mount == "/"))
        || device["children"].as_array().is_some_and(|children| children.iter().any(holds_root))
}

pub fn disks() -> Vec<Value> {
    let tree = util::json("lsblk", &["-J", "-b", "-o", "NAME,MODEL,SIZE,TRAN,RM,TYPE,MOUNTPOINTS"]).unwrap_or_default();
    tree["blockdevices"]
        .as_array()
        .map(|devices| {
            devices
                .iter()
                .filter(|device| device["type"] == "disk")
                .map(|device| {
                    json!({
                        "name": device["name"].as_str().unwrap_or_default(),
                        "model": device["model"].as_str().unwrap_or_default().trim(),
                        "size": device["size"].as_u64().unwrap_or(0),
                        "transport": device["tran"].as_str().unwrap_or_default(),
                        "removable": device["rm"].as_bool().unwrap_or(false),
                        "system": holds_root(device),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn filesystems() -> Vec<Value> {
    let mounts = util::json("findmnt", &["-J", "-b", "-o", "TARGET,SOURCE,FSTYPE,SIZE,AVAIL", "-t", "btrfs,ext4,xfs,vfat,f2fs"])
        .unwrap_or_default();
    let mut found = Vec::new();
    fn walk(node: &Value, found: &mut Vec<Value>) {
        if let Some(target) = node["target"].as_str() {
            found.push(json!({
                "mount": target,
                "source": node["source"].as_str().unwrap_or_default(),
                "fstype": node["fstype"].as_str().unwrap_or_default(),
                "size": node["size"].as_u64().unwrap_or(0),
                "available": node["avail"].as_u64().unwrap_or(0),
            }));
        }
        for child in node["children"].as_array().into_iter().flatten() {
            walk(child, found);
        }
    }
    for node in mounts["filesystems"].as_array().into_iter().flatten() {
        walk(node, &mut found);
    }
    found
}

pub fn inspect() -> Value {
    let (cpu, threads) = cpu();
    let (memory, memory_available) = memory();
    let uptime = util::read("/proc/uptime").split('.').next().and_then(|seconds| seconds.parse::<u64>().ok()).unwrap_or(0);
    let dmi = |name: &str| util::read(&format!("/sys/class/dmi/id/{name}"));
    let board = format!("{} {}", dmi("board_vendor"), dmi("board_name")).trim().to_string();
    let denden = util::output("pacman", &["-Q", "denden-base"])
        .and_then(|line| line.split_whitespace().nth(1).map(str::to_string))
        .unwrap_or_default();
    json!({
        "hostname": util::read("/proc/sys/kernel/hostname"),
        "os": os_release("PRETTY_NAME").unwrap_or_else(|| "Linux".into()),
        "denden": denden,
        "kernel": util::read("/proc/sys/kernel/osrelease"),
        "root_subvolume": util::output("findmnt", &["-n", "-o", "FSROOT", "/"]).unwrap_or_default().trim(),
        "uptime": uptime,
        "cpu": cpu,
        "threads": threads,
        "memory": memory,
        "memory_available": memory_available,
        "gpus": gpus(),
        "board": board,
        "firmware": { "vendor": dmi("bios_vendor"), "version": dmi("bios_version"), "date": dmi("bios_date") },
        "disks": disks(),
        "filesystems": filesystems(),
    })
}
