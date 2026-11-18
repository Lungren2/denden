'use strict';
// The three steps, each a small state machine drawn into the panel and the
// footer. System work happens in main.js; this only shows it.

const $ = (id) => document.getElementById(id);
const api = window.setup;

// Lucide icons, as T3 Code uses.
const ICONS = {
  github: '<path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4"/><path d="M9 18c-4.51 2-5-2-7-2"/>',
  monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><path d="M8 21h8M12 17v4"/>',
  drive: '<path d="M10 2v4M14 2v4"/><rect x="6" y="6" width="12" height="16" rx="2"/><path d="M10 12h4"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  copy: '<rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
  external: '<path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
};
const svg = (name) => `<svg class="i" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`;

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') node.className = v;
    else if (k === 'html') node.innerHTML = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else if (v !== false && v != null) node.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) if (c != null && c !== false) node.append(c);
  return node;
}
const button = (label, kind, onclick, opts = {}) =>
  el('button', { class: `btn ${kind}${opts.small ? ' small' : ''}`, onclick, disabled: opts.disabled }, label);
const wait = (text) => el('div', { class: 'wait' }, el('div', { class: 'spin' }), text);
const icon = (name, ok) => el('div', { class: ok ? 'icon ok' : 'icon', html: svg(ok ? 'check' : name) });

const STEPS = ['github', 'tailscale', 'backups'];
const TITLES = { github: 'GitHub', tailscale: 'Tailscale', backups: 'Backups' };
const s = {
  step: 0,
  github: { phase: 'loading' },      // loading | idle | waiting | done | error
  tailscale: { phase: 'loading' },
  backups: { phase: 'loading' },     // loading | nostick | ready | working | key | done | error
};

function next() {
  if (s.step < STEPS.length - 1) { s.step += 1; render(); } else api.close();
}

// ---- Panels -----------------------------------------------------------------

function githubPanel(g) {
  if (g.phase === 'done') return [icon('github', true), el('div', { class: 'body' },
    el('h2', {}, g.login ? `Signed in as ${g.login}` : 'Signed in to GitHub'),
    el('p', {}, 'Your repositories, and your organisations\', are kept up to date in Projects.'))];
  if (g.phase === 'waiting') return [icon('github'), el('div', { class: 'body' },
    el('h2', {}, 'Enter this code on GitHub'),
    el('p', {}, g.code ? 'It\'s copied already: paste it on the page that opened in the browser.' : 'Opening GitHub in the browser…'),
    g.code && el('div', { class: 'code' }, el('span', {}, g.code),
      button(el('span', { html: svg('copy') }), 'ghost small', () => api.copy(g.code))),
    wait('Waiting for sign-in'))];
  return [icon('github'), el('div', { class: 'body' },
    el('h2', {}, 'Your repositories'),
    el('p', {}, 'Sign in to GitHub, and every repository you and your organisations own is kept in Projects, up to date.'),
    g.phase === 'error' && el('p', { class: 'error' }, 'Sign-in didn\'t finish. Try again.'))];
}

function tailscalePanel(t) {
  if (t.phase === 'done') return [icon('monitor', true), el('div', { class: 'body' },
    el('h2', {}, 'Reachable from anywhere'),
    el('p', {}, `Your other devices can reach this computer as ${t.name || 'this computer'}${t.ip ? ` (${t.ip})` : ''}.`))];
  if (t.phase === 'waiting') return [
    t.qr ? el('div', { class: 'qr', html: t.qr }) : icon('monitor'),
    el('div', { class: 'body' },
      el('h2', {}, 'Sign in to Tailscale'),
      el('p', {}, t.url ? 'In the browser that opened, or scan the code with your phone.' : 'Starting Tailscale…'),
      wait('Waiting for sign-in'))];
  return [icon('monitor'), el('div', { class: 'body' },
    el('h2', {}, 'Reach this computer from anywhere'),
    el('p', {}, 'Connect it to your Tailscale network, and your phone and other computers can open it wherever they are.'),
    t.phase === 'error' && el('p', { class: 'error' }, 'Tailscale didn\'t connect. Try again.'))];
}

function backupsPanel(b) {
  if (b.phase === 'done') return [icon('drive', true), el('div', { class: 'body' },
    el('h2', {}, 'Backups are on'),
    el('p', {}, 'Your files back up to the Den Den stick when it\'s plugged in, and every day while it stays in.'))];
  if (b.phase === 'key') return [icon('drive', true), el('div', { class: 'body' },
    el('h2', {}, 'Save your recovery key'),
    el('p', {}, 'Keep it in your password manager. Without it, the backups can\'t be restored.'),
    el('div', { class: 'code key' }, el('span', {}, b.key),
      button(el('span', { html: svg('copy') }), 'ghost small', () => api.copy(b.key))),
    el('label', { class: 'check' },
      el('input', { type: 'checkbox', checked: b.saved, onchange: (e) => { b.saved = e.target.checked; render(); } }),
      'I\'ve saved the key'))];
  if (b.phase === 'working') return [icon('drive'), el('div', { class: 'body' },
    el('h2', {}, 'Setting up backups'), el('p', {}, 'Preparing the stick. This takes a moment.'), wait('Working'))];
  if (b.phase === 'ready') return [icon('drive'), el('div', { class: 'body' },
    el('h2', {}, `Back up to your ${b.stick.name}`),
    el('p', {}, b.stick.hasData
      ? 'It already has room for backups. Den Den will use it.'
      : `Den Den adds a backup space to this ${b.stick.size} stick, after the Den Den part, which keeps working. Anything else stored on the stick is erased.`),
    b.error && el('p', { class: 'error' }, 'Backups couldn\'t be set up. Try again.'))];
  return [icon('drive'), el('div', { class: 'body' },
    el('h2', {}, 'Back up to the Den Den stick'),
    el('p', {}, 'Plug in the USB stick Den Den was installed from. Your projects and settings back up to it.'),
    wait('Looking for the stick'))];
}

// ---- Footer -----------------------------------------------------------------

function primary() {
  const g = s.github, t = s.tailscale, b = s.backups;
  switch (STEPS[s.step]) {
    case 'github':
      if (g.phase === 'done') return button('Continue', 'primary', next);
      if (g.phase === 'waiting') return button(el('span', {}, 'Open GitHub'), 'primary', () => g.url && api.open(g.url), { disabled: !g.url });
      return button('Sign in with GitHub', 'primary', () => { s.github = { phase: 'waiting' }; render(); api.githubSignIn(); });
    case 'tailscale':
      if (t.phase === 'done') return button('Continue', 'primary', next);
      if (t.phase === 'waiting') return button('Open sign-in page', 'primary', () => t.url && api.open(t.url), { disabled: !t.url });
      return button('Connect', 'primary', () => { s.tailscale = { phase: 'waiting' }; render(); api.tailscaleConnect(); });
    case 'backups':
      if (b.phase === 'done') return button('Finish', 'primary', () => api.close());
      if (b.phase === 'key') return button('Finish', 'primary', () => api.close(), { disabled: !b.saved });
      if (b.phase === 'ready') return button(b.stick.hasData ? 'Set up backups' : 'Erase and set up', 'primary', setupBackups);
      return button('Set up backups', 'primary', null, { disabled: true });
  }
}

async function setupBackups() {
  s.backups = { ...s.backups, phase: 'working', error: false };
  render();
  const res = await api.backupsSetup();
  s.backups = res.ok ? { phase: 'key', key: res.key, saved: false } : { ...s.backups, phase: 'ready', error: true };
  render();
}

function render() {
  const steps = $('steps');
  steps.replaceChildren(...STEPS.map((name, i) => {
    const done = s[name].phase === 'done' || (name === 'backups' && s.backups.phase === 'key');
    return el('button', {
      class: done ? 'step done' : 'step', 'aria-current': i === s.step ? 'step' : null,
      onclick: () => { s.step = i; render(); },
    }, el('span', { class: 'num', html: done ? svg('check') : String(i + 1) }), TITLES[name]);
  }));
  const name = STEPS[s.step];
  const panel = { github: githubPanel, tailscale: tailscalePanel, backups: backupsPanel }[name](s[name]);
  $('panel').replaceChildren(...panel.filter(Boolean));
  const last = s.step === STEPS.length - 1;
  const finished = s[name].phase === 'done' || s[name].phase === 'key';
  $('footer').replaceChildren(
    !finished && button(last ? 'Not now' : 'Skip', 'ghost', next) || '',
    el('div', { class: 'spacer' }),
    s.step > 0 ? button('Back', 'outline', () => { s.step -= 1; render(); }) : '',
    primary());
  requestAnimationFrame(() => api.resize(document.getElementById('dialog').offsetHeight));
}

// ---- Events from the system -------------------------------------------------

api.onGithubCode(({ code, url }) => { Object.assign(s.github, { code, url }); render(); });
api.onGithubDone((r) => { s.github = r.ok && r.done ? { phase: 'done', login: r.login } : { phase: 'error' }; render(); });
api.onTailscaleUrl(({ url, qr }) => { Object.assign(s.tailscale, { url, qr }); render(); });
api.onTailscaleDone((r) => { s.tailscale = r.ok && r.done ? { phase: 'done', name: r.name, ip: r.ip } : { phase: 'error' }; render(); });

// Watch for the stick while it's needed.
setInterval(async () => {
  const b = s.backups;
  if (STEPS[s.step] !== 'backups' || !['nostick', 'ready'].includes(b.phase)) return;
  const r = await api.backups();
  const phase = r.done ? 'done' : r.stick ? 'ready' : 'nostick';
  if (phase !== b.phase || JSON.stringify(r.stick) !== JSON.stringify(b.stick)) { s.backups = { phase, stick: r.stick }; render(); }
}, 2000);

(async () => {
  render();
  const st = await api.state();
  s.github = st.github.done ? { phase: 'done', login: st.github.login } : { phase: 'idle' };
  s.tailscale = st.tailscale.done ? { phase: 'done', name: st.tailscale.name, ip: st.tailscale.ip } : { phase: 'idle' };
  s.backups = st.backups.done ? { phase: 'done' } : { phase: st.backups.stick ? 'ready' : 'nostick', stick: st.backups.stick };
  // Start at the first step that isn't done.
  const first = STEPS.findIndex((n) => s[n].phase !== 'done');
  s.step = first === -1 ? 0 : first;
  render();
})();
