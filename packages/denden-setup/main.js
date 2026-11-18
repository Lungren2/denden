// Den Den Setup: one window, in T3 Code's dialog style, that connects
// GitHub, Tailscale and backups. It opens by itself at the first login
// (`--first-run`) and from the launcher any time after.
//
// The window is the dialog: niri draws its hairline, corners and shadow
// (a window rule in Den Den's niri config), and the page draws the rest.
// Everything privileged goes through `sudo -n`, which Den Den allows the
// user without a password; the page only calls the few actions below.
'use strict';

const { app, BrowserWindow, ipcMain, shell, clipboard } = require('electron');
const { spawn, execFile } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const stateDir = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state'), 'denden');
const doneMarker = path.join(stateDir, 'setup-done');
const firstRun = process.argv.includes('--first-run');

app.setName('denden-setup');
app.setDesktopName('denden-setup.desktop');

function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout: 30000, ...opts }, (error, stdout, stderr) => {
      resolve({ ok: !error, code: error ? error.code : 0, stdout: String(stdout), stderr: String(stderr) });
    });
  });
}

function markDone() {
  fs.mkdirSync(stateDir, { recursive: true });
  fs.writeFileSync(doneMarker, new Date().toISOString() + '\n');
}

// ---- What is set up already -------------------------------------------------

async function github() {
  const status = await run('gh', ['auth', 'status', '--hostname', 'github.com']);
  if (!status.ok) return { done: false };
  const user = await run('gh', ['api', 'user', '--jq', '.login']);
  return { done: true, login: user.ok ? user.stdout.trim() : '' };
}

async function tailscale() {
  const res = await run('tailscale', ['status', '--json']);
  if (!res.ok && !res.stdout) return { done: false };
  try {
    const s = JSON.parse(res.stdout);
    if (s.BackendState !== 'Running') return { done: false };
    return {
      done: true,
      name: (s.Self?.DNSName || '').split('.')[0] || s.Self?.HostName || '',
      ip: (s.Self?.TailscaleIPs || [])[0] || '',
    };
  } catch {
    return { done: false };
  }
}

// The Den Den stick: a USB disk with a partition labelled DENDEN_*.
async function backups() {
  const configured = fs.existsSync('/etc/denden/backup.conf');
  const res = await run('lsblk', ['-J', '-b', '-o', 'NAME,TRAN,TYPE,LABEL,PARTLABEL,SIZE,MODEL,VENDOR']);
  let stick = null;
  try {
    for (const d of JSON.parse(res.stdout).blockdevices || []) {
      if (d.type !== 'disk' || d.tran !== 'usb') continue;
      const parts = d.children || [];
      if (!parts.some((p) => /^DENDEN_/.test(p.label || ''))) continue;
      const gb = Math.round(Number(d.size) / 1e9);
      const name = [d.vendor, d.model].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
      stick = { name: name || 'USB stick', size: `${gb} GB`, hasData: parts.some((p) => p.partlabel === 'DENDEN_DATA') };
    }
  } catch {}
  return { done: configured, stick };
}

ipcMain.handle('state', async () => ({
  github: await github(),
  tailscale: await tailscale(),
  backups: await backups(),
}));
ipcMain.handle('backups', backups);

// ---- Actions ----------------------------------------------------------------

let win;
let pending = null; // the sign-in that is running, so a second click doesn't start another
const send = (channel, data) => win && !win.isDestroyed() && win.webContents.send(channel, data);

ipcMain.handle('github:sign-in', () => {
  if (pending) return;
  // Without a terminal, gh prints the one-time code and the page to enter it
  // on, then waits until the browser sign-in completes.
  const gh = spawn('gh', ['auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web', '--skip-ssh-key'],
    { stdio: ['ignore', 'pipe', 'pipe'] });
  pending = gh;
  let out = '', opened = false;
  const scan = (chunk) => {
    out += chunk;
    const code = out.match(/code[^A-Z0-9]*\(?([A-Z0-9]{4}-[A-Z0-9]{4})/);
    const url = out.match(/https:\/\/github\.com\/login\/device\S*/);
    if (code && url && !opened) {
      opened = true;
      clipboard.writeText(code[1]);
      send('github:code', { code: code[1], url: url[0] });
      shell.openExternal(url[0]);
    }
  };
  gh.stdout.on('data', scan);
  gh.stderr.on('data', scan);
  gh.on('close', async (status) => {
    pending = null;
    if (status === 0) {
      await run('gh', ['auth', 'setup-git', '--hostname', 'github.com']);
      // Bring the repositories into ~/Projects now rather than at the next hour.
      await run('systemctl', ['--user', 'start', '--no-block', 'denden-repos.service']);
    }
    send('github:done', { ok: status === 0, ...(await github()) });
  });
});

ipcMain.handle('tailscale:connect', async () => {
  if (pending) return;
  const enable = await run('sudo', ['-n', 'systemctl', 'enable', '--now', 'tailscaled.service']);
  if (!enable.ok) return send('tailscale:done', { ok: false });
  const user = os.userInfo().username;
  const ts = spawn('sudo', ['-n', 'tailscale', 'up', `--operator=${user}`, '--ssh', '--json', '--timeout=15m'],
    { stdio: ['ignore', 'pipe', 'pipe'] });
  pending = ts;
  let buf = '', sent = false;
  ts.stdout.on('data', async (chunk) => {
    buf += chunk;
    const m = buf.match(/"AuthURL"\s*:\s*"([^"]+)"/);
    if (m && !sent) {
      sent = true;
      const qr = await run('qrencode', ['-t', 'SVG', '-m', '0', '--inline', '--svg-path', '-o', '-', m[1]]);
      send('tailscale:url', { url: m[1], qr: qr.ok ? qr.stdout : '' });
      shell.openExternal(m[1]);
    }
  });
  ts.on('close', async (status) => {
    pending = null;
    send('tailscale:done', { ok: status === 0, ...(await tailscale()) });
  });
});

// Adds the backup partition to the stick. The page asks first: this is the
// user's go-ahead for that disk.
ipcMain.handle('backups:setup', async () => {
  const res = await run('sudo', ['-n', 'denden-backup', 'setup', '--yes'], { timeout: 10 * 60 * 1000 });
  if (!res.ok) return { ok: false };
  const key = await run('sudo', ['-n', 'denden-backup', 'key']);
  return { ok: key.ok, key: key.stdout.trim() };
});

ipcMain.handle('open', (_e, url) => {
  if (/^https:\/\//.test(url)) shell.openExternal(url);
});
ipcMain.handle('copy', (_e, text) => clipboard.writeText(String(text)));
ipcMain.handle('resize', (_e, height) => {
  if (!win) return;
  const [w] = win.getContentSize();
  win.setContentSize(w, Math.min(Math.max(Math.ceil(height), 300), 900));
});
ipcMain.handle('close', () => {
  markDone();
  if (pending) pending.kill();
  app.quit();
});

// ---- Window -----------------------------------------------------------------

app.whenReady().then(async () => {
  if (firstRun) {
    if (fs.existsSync(doneMarker)) return app.quit();
    // A machine set up some other way doesn't need the wizard.
    const [g, t, b] = await Promise.all([github(), tailscale(), backups()]);
    if (g.done && t.done && b.done) {
      markDone();
      return app.quit();
    }
  }
  win = new BrowserWindow({
    width: 560,
    height: 460,
    title: 'Set up Den Den',
    frame: false,
    resizable: false,
    show: false,
    backgroundColor: '#000000',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.once('ready-to-show', () => win.show());
  win.loadFile(path.join(__dirname, 'index.html'));
  win.on('closed', () => {
    markDone();
    if (pending) pending.kill();
  });
});

app.on('window-all-closed', () => app.quit());
