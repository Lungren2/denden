//! dend: Den Den's machine API. A Varlink service on /run/den/io.denden that
//! agents (through `den` and its MCP server) and people query for the
//! machine's state. Everything here is read-only; changes to the system will
//! come through the broker, which isn't built yet.
//!
//! Varlink is JSON messages, each ended by a NUL byte, over a Unix socket:
//! https://varlink.org. `varlinkctl introspect /run/den/io.denden` lists the
//! interfaces.

mod doctor;
mod history;
mod machine;
mod package;
mod service;
mod util;

use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::net::{UnixListener, UnixStream};

const INTERFACES: &[(&str, &str)] = &[
    ("org.varlink.service", include_str!("org.varlink.service.varlink")),
    ("io.denden.Machine", include_str!("io.denden.Machine.varlink")),
    ("io.denden.Package", include_str!("io.denden.Package.varlink")),
    ("io.denden.Service", include_str!("io.denden.Service.varlink")),
    ("io.denden.History", include_str!("io.denden.History.varlink")),
];

/// Who is asking, from the socket's peer credentials.
pub struct Caller {
    pub uid: u32,
    /// The caller's user name; None for root and system users, whose
    /// "user session" checks are skipped.
    pub user: Option<String>,
}

/// A Varlink error: its qualified name and parameters.
pub type Error = (String, Value);

pub fn invalid(parameter: &str) -> Error {
    ("org.varlink.service.InvalidParameter".into(), json!({ "parameter": parameter }))
}

fn dispatch(method: &str, parameters: &Value, caller: &Caller) -> Result<Value, Error> {
    match method {
        "org.varlink.service.GetInfo" => Ok(json!({
            "vendor": "Den Den",
            "product": "dend",
            "version": env!("CARGO_PKG_VERSION"),
            "url": "https://github.com/Lungren2/denden",
            "interfaces": INTERFACES.iter().map(|(name, _)| *name).collect::<Vec<_>>(),
        })),
        "org.varlink.service.GetInterfaceDescription" => {
            let wanted = parameters.get("interface").and_then(Value::as_str).ok_or_else(|| invalid("interface"))?;
            INTERFACES
                .iter()
                .find(|(name, _)| *name == wanted)
                .map(|(_, description)| json!({ "description": description }))
                .ok_or_else(|| ("org.varlink.service.InterfaceNotFound".into(), json!({ "interface": wanted })))
        }
        "io.denden.Machine.Inspect" => Ok(machine::inspect()),
        "io.denden.Machine.Doctor" => Ok(doctor::doctor(caller)),
        "io.denden.Package.Query" => package::query(parameters),
        "io.denden.Service.Status" => service::status(parameters, caller),
        "io.denden.History.Query" => history::query(parameters),
        _ => {
            let interface = method.rsplit_once('.').map(|(interface, _)| interface).unwrap_or("");
            if INTERFACES.iter().any(|(name, _)| *name == interface) {
                Err(("org.varlink.service.MethodNotFound".into(), json!({ "method": method })))
            } else {
                Err(("org.varlink.service.InterfaceNotFound".into(), json!({ "interface": interface })))
            }
        }
    }
}

fn caller(stream: &UnixStream) -> Caller {
    let mut credentials = libc::ucred { pid: 0, uid: u32::MAX, gid: u32::MAX };
    let mut length = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    // SAFETY: SO_PEERCRED fills a ucred of the length given.
    let result = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            (&raw mut credentials).cast(),
            &mut length,
        )
    };
    let uid = if result == 0 { credentials.uid } else { u32::MAX };
    // Regular users only (UID_MIN in login.defs is 1000; nobody is 65534).
    let user = (1000..60000)
        .contains(&uid)
        .then(|| util::user_name(uid))
        .flatten();
    Caller { uid, user }
}

fn serve(stream: UnixStream) {
    let caller = caller(&stream);
    let Ok(writer) = stream.try_clone() else { return };
    let mut writer = std::io::BufWriter::new(writer);
    let mut reader = BufReader::new(stream);
    let mut message = Vec::new();
    loop {
        message.clear();
        match reader.read_until(0, &mut message) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        if message.last() == Some(&0) {
            message.pop();
        }
        let Ok(request) = serde_json::from_slice::<Value>(&message) else { return };
        let Some(method) = request.get("method").and_then(Value::as_str) else { return };
        let parameters = request.get("parameters").cloned().unwrap_or_else(|| json!({}));
        if !parameters.is_object() {
            return;
        }
        let reply = match dispatch(method, &parameters, &caller) {
            Ok(parameters) => json!({ "parameters": parameters }),
            Err((error, parameters)) => json!({ "error": error, "parameters": parameters }),
        };
        if request.get("oneway").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        let mut bytes = serde_json::to_vec(&reply).unwrap_or_default();
        bytes.push(0);
        if writer.write_all(&bytes).and_then(|()| writer.flush()).is_err() {
            return;
        }
    }
}

/// The socket systemd passes (dend.socket), or one bound for testing with
/// `dend --listen PATH`.
fn listener() -> std::io::Result<UnixListener> {
    let mut args = std::env::args().skip(1);
    if let (Some(flag), Some(path)) = (args.next(), args.next()) {
        if flag == "--listen" {
            let _ = std::fs::remove_file(&path);
            return UnixListener::bind(path);
        }
    }
    let ours = std::env::var("LISTEN_PID").ok().and_then(|pid| pid.parse::<u32>().ok()) == Some(std::process::id());
    let count = std::env::var("LISTEN_FDS").ok().and_then(|count| count.parse::<u32>().ok()).unwrap_or(0);
    if !ours || count < 1 {
        return Err(std::io::Error::other("no socket from systemd (start dend.socket), and no --listen PATH"));
    }
    // SAFETY: systemd passes the listening socket as fd 3. Close it on exec,
    // so the commands dend runs don't inherit it.
    unsafe {
        libc::fcntl(3, libc::F_SETFD, libc::FD_CLOEXEC);
        Ok(UnixListener::from_raw_fd(3))
    }
}

fn main() {
    let listener = match listener() {
        Ok(listener) => listener,
        Err(error) => {
            eprintln!("dend: {error}");
            std::process::exit(1);
        }
    };
    for stream in listener.incoming().flatten() {
        std::thread::spawn(move || serve(stream));
    }
}
