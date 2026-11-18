//! io.denden.Package.Query: installed and available packages.

use crate::{Error, invalid, util};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::Path;

struct Available {
    repository: String,
    version: String,
    base: String,
    url: String,
    description: String,
}

/// Every package in the sync databases, in pacman.conf's repository order.
fn sync() -> HashMap<String, Vec<Available>> {
    let mut packages: HashMap<String, Vec<Available>> = HashMap::new();
    for line in util::output("expac", &["-S", "%r\t%n\t%v\t%e\t%u\t%d"]).unwrap_or_default().lines() {
        let fields: Vec<&str> = line.splitn(6, '\t').collect();
        if let [repository, name, version, base, url, description] = fields[..] {
            packages.entry(name.to_string()).or_default().push(Available {
                repository: repository.into(),
                version: version.into(),
                base: base.into(),
                url: url.into(),
                description: description.into(),
            });
        }
    }
    packages
}

struct Installed {
    version: String,
    base: String,
    reason: String,
    size: u64,
    date: i64,
    url: String,
    description: String,
}

fn installed() -> HashMap<String, Installed> {
    let mut packages = HashMap::new();
    let lines = util::output("expac", &["-Q", "--timefmt=%s", "%n\t%v\t%e\t%w\t%m\t%l\t%u\t%d"]).unwrap_or_default();
    for line in lines.lines() {
        let fields: Vec<&str> = line.splitn(8, '\t').collect();
        if let [name, version, base, reason, size, date, url, description] = fields[..] {
            packages.insert(
                name.to_string(),
                Installed {
                    version: version.into(),
                    base: base.into(),
                    reason: reason.into(),
                    size: size.parse().unwrap_or(0),
                    date: date.parse().unwrap_or(0),
                    url: url.into(),
                    description: description.into(),
                },
            );
        }
    }
    packages
}

fn source_tree(name: &str, base: &str) -> Option<String> {
    let tree = format!("/src/{base}");
    if Path::new(&tree).join(".git/den.json").is_file() {
        return Some(tree);
    }
    let recipe = format!("/src/denden/packages/{name}");
    Path::new(&recipe).join("PKGBUILD").is_file().then_some(recipe)
}

fn describe(name: &str, local: Option<&Installed>, available: Option<&Vec<Available>>) -> Value {
    let first = available.and_then(|repos| repos.first());
    let base = local
        .map(|package| package.base.as_str())
        .or(first.map(|package| package.base.as_str()))
        .filter(|base| !base.is_empty())
        .unwrap_or(name);
    let origin = local.and_then(|package| {
        available?.iter().find(|repo| repo.version == package.version).map(|repo| repo.repository.clone())
    });
    json!({
        "name": name,
        "base": base,
        "description": local.map(|package| &package.description).or(first.map(|package| &package.description)),
        "url": local.map(|package| &package.url).or(first.map(|package| &package.url)),
        "version": local.map(|package| &package.version),
        "available": first.map(|package| &package.version),
        "repository": first.map(|package| &package.repository),
        "origin": origin,
        "reason": local.map(|package| if package.reason == "explicit" { "explicit" } else { "dependency" }),
        "installed_size": local.map(|package| package.size),
        "install_date": local.map(|package| package.date),
        "source_tree": source_tree(name, base),
    })
}

pub fn query(parameters: &Value) -> Result<Value, Error> {
    let names = match &parameters["names"] {
        Value::Null => None,
        Value::Array(names) => {
            Some(names.iter().map(|name| name.as_str().map(str::to_string)).collect::<Option<Vec<_>>>().ok_or_else(|| invalid("names"))?)
        }
        _ => return Err(invalid("names")),
    };
    let search = match &parameters["search"] {
        Value::Null => None,
        Value::String(text) => Some(text.to_lowercase()),
        _ => return Err(invalid("search")),
    };
    let local = installed();
    let repos = sync();
    let mut packages = Vec::new();
    let mut missing = Vec::new();
    if let Some(names) = names {
        for name in names {
            if local.contains_key(&name) || repos.contains_key(&name) {
                packages.push(describe(&name, local.get(&name), repos.get(&name)));
            } else {
                missing.push(name);
            }
        }
    } else {
        let mut chosen: Vec<&String> = local
            .iter()
            .filter(|(name, package)| match &search {
                Some(text) => name.to_lowercase().contains(text) || package.description.to_lowercase().contains(text),
                None => package.reason == "explicit",
            })
            .map(|(name, _)| name)
            .collect();
        chosen.sort();
        packages.extend(chosen.into_iter().map(|name| describe(name, local.get(name), repos.get(name))));
    }
    Ok(json!({ "packages": packages, "missing": missing }))
}
