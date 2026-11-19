"""den session: an agent's unit of work. One task, one sandbox, one reviewable
result.

  den session create <project> [--name N] [--secret NAME…]
  den session run <session> [-- command…]   in the sandbox (default: a shell)
  den session list
  den session review <session> [--stat]
  den session commit <session> [-m MESSAGE] [--merge]
  den session discard <session>

The workspace is a Btrfs snapshot of the project's base: a clone of the
project at its current commit with its dependencies installed, kept in
~/.cache/den/bases and brought up to date when a session starts. Measured on
T3 Code's monorepo (docs/session-storage.md), a snapshot is ready in 0.05 s
and costs no space until it changes; a git worktree with `pnpm install` took
7.6 s and 370 MB. Both the base and every session see the tree at /workspace,
so absolute paths that tools write (virtualenvs, Cargo fingerprints) stay
valid across the snapshot.

The sandbox is bubblewrap in a systemd scope under den-sessions.slice: the
system read-only, no sudo (no new privileges), the home directory hidden
except the shared package caches and the agents' own settings, the
workspace writable at /workspace, the machine API at /system. Each session
gets its own ports (PORT, DEN_PORTS), Compose project name and memory and CPU
limits, and only the secrets it was granted, in its environment and in
/secrets. Docker stays out unless the session is made with --docker: its
socket is root on this machine, so such a session isn't sandboxed from it. At most DEN_SESSIONS_MAX sessions run at once.

Commit brings the session's work back to the project as branch den/<name>
(and with --merge fast-forwards the project's current branch onto it);
discard throws the workspace away.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets as random
import shutil
import subprocess
import sys
import time

HOME = Path.home()
UID = os.getuid()
DATA = Path(os.environ.get('XDG_DATA_HOME', HOME / '.local/share')) / 'den'
SESSIONS = DATA / 'sessions'
LOG = DATA / 'sessions.log'
BASES = Path(os.environ.get('XDG_CACHE_HOME', HOME / '.cache')) / 'den' / 'bases'
WORKSPACE = '/workspace'
DOCKER_SOCKETS = ('/run/docker.sock', '/run/containerd/containerd.sock', '/run/podman/podman.sock')
DOCKER_WARNING = ("this session can use Docker, which is root on this machine: the sandbox "
                  "doesn't hold anything back from it until rootless Docker (milestone 6)")
MAX_RUNNING = int(os.environ.get('DEN_SESSIONS_MAX', max(2, (os.cpu_count() or 4) // 3)))
PORT_BASE, PORTS_EACH, SLOTS = 20000, 100, 100
LIMITS = {'MemoryHigh': '6G', 'MemoryMax': '8G', 'CPUQuota': f'{(os.cpu_count() or 4) * 50}%',
          'TasksMax': '4096'}

# How a base gets its dependencies: the first lockfile found, unless the
# project has an executable .den/setup.
INSTALLERS = (
    ('pnpm-lock.yaml', ['pnpm', 'install', '--frozen-lockfile']),
    ('bun.lock', ['bun', 'install', '--frozen-lockfile']),
    ('bun.lockb', ['bun', 'install', '--frozen-lockfile']),
    ('package-lock.json', ['npm', 'ci']),
    ('yarn.lock', ['yarn', 'install', '--immutable']),
    ('uv.lock', ['uv', 'sync', '--frozen']),
    ('Cargo.lock', ['cargo', 'fetch', '--locked']),
)
# Shared with every session and the user: package caches (read-write), the
# tools and settings a shell and the agents need (read-only), and the agents'
# own state and sign-ins (read-write, until the broker hands those out too).
CACHES = ('.local/share/pnpm', '.cache/pnpm', '.npm', '.bun/install/cache', '.cargo/registry',
          '.cargo/git', '.cache/uv', '.cache/pip', '.cache/go-build', '.cache/mise')
READ_ONLY = ('.local/bin', '.local/share/mise', '.config/mise', '.rustup', '.cargo/bin', '.bun/bin',
             '.gitconfig', '.config/git', '.config/fish', '.config/starship.toml', '.bashrc',
             '.bash_profile', '.profile', '.config/ghostty')
AGENTS = ('.claude', '.claude.json', '.codex')


class Fail(Exception):
    pass


def say(*parts):
    print('den:', *parts, file=sys.stderr, flush=True)


def git(tree, *args, check=True, capture=True, env=None):
    result = subprocess.run(['git', '-C', str(tree), *args], text=True,
                            env=dict(os.environ, **env) if env else None,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if check and result.returncode:
        raise Fail(f'git {" ".join(args[:2])} failed in {tree}: {(result.stderr or "").strip()}')
    return (result.stdout or '').rstrip()


def identity(project):
    """Who the session's commits are by: the project's git identity, else
    the GitHub account's (with its noreply address), else the login name."""
    name = git(project, 'config', '--get', 'user.name', check=False)
    email = git(project, 'config', '--get', 'user.email', check=False)
    if name and email:
        return {'name': name, 'email': email}
    account = subprocess.run(['gh', 'api', 'user', '--jq', '[.id, .login, .name] | @tsv'],
                             text=True, capture_output=True, timeout=20)
    if account.returncode == 0 and account.stdout.count('\t') == 2:
        number, login, full = account.stdout.rstrip('\n').split('\t')
        return {'name': full or login, 'email': f'{number}+{login}@users.noreply.github.com'}
    user = os.environ.get('USER', 'user')
    return {'name': user, 'email': f'{user}@{os.uname().nodename}.local'}


def identity_env(session):
    who = session['identity']
    return {'GIT_AUTHOR_NAME': who['name'], 'GIT_AUTHOR_EMAIL': who['email'],
            'GIT_COMMITTER_NAME': who['name'], 'GIT_COMMITTER_EMAIL': who['email']}


# Sessions on disk --------------------------------------------------------------

def load(name):
    path = SESSIONS / name / 'session.json'
    if not path.is_file():
        matches = [p.parent.name for p in SESSIONS.glob('*/session.json') if p.parent.name.startswith(name)]
        if len(matches) != 1:
            raise Fail(f'no session {name}' if not matches else f'{name} matches {", ".join(matches)}')
        path = SESSIONS / matches[0] / 'session.json'
    return json.loads(path.read_text())


def save(session):
    path = SESSIONS / session['id'] / 'session.json'
    path.write_text(json.dumps(session, indent=2) + '\n')


def record(session, event, **extra):
    DATA.mkdir(parents=True, exist_ok=True)
    with open(LOG, 'a') as log:
        log.write(json.dumps({'time': int(time.time()), 'event': event, 'session': session['id'],
                              'project': session['project'], **extra}) + '\n')


def all_sessions():
    return sorted((json.loads(p.read_text()) for p in SESSIONS.glob('*/session.json')),
                  key=lambda s: s['created'])


def running():
    """Sessions with a process in the sandbox now, from their scopes."""
    units = subprocess.run(['systemctl', '--user', 'list-units', '--type=scope', '--state=running',
                            '--plain', '--no-legend', 'den-session-*'],
                           text=True, capture_output=True).stdout
    return {m[1] for m in re.finditer(r'^den-session-(.+)-\d+\.scope', units, re.M)}


def lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = open(path, 'w')
    fcntl.flock(handle, fcntl.LOCK_EX)
    return handle


# The sandbox -------------------------------------------------------------------

def sandbox(workspace, command, session=None, project=None, grants=()):
    """argv for COMMAND in the sandbox with WORKSPACE at /workspace, and the
    file descriptors carrying granted secrets."""
    # A tmpfs root holding the system read-only, so /workspace and /system
    # can be made in it.
    args = ['bwrap', '--tmpfs', '/']
    for entry in sorted(os.scandir('/'), key=lambda entry: entry.name):
        if entry.name in ('dev', 'proc', 'tmp', 'workspace', 'system', 'secrets', 'lost+found'):
            continue
        if entry.is_symlink():
            args += ['--symlink', os.readlink(entry.path), entry.path]
        elif entry.is_dir():
            args += ['--ro-bind', entry.path, entry.path]
    args += ['--dev', '/dev', '--proc', '/proc', '--tmpfs', '/tmp', '--tmpfs', '/var/tmp',
             '--tmpfs', f'/run/user/{UID}', '--tmpfs', str(HOME)]
    for name in CACHES:
        path = HOME / name
        path.mkdir(parents=True, exist_ok=True)
        args += ['--bind', str(path), str(path)]
    for name in READ_ONLY:
        if (HOME / name).exists():
            args += ['--ro-bind', str(HOME / name), str(HOME / name)]
    for name in AGENTS:
        if (HOME / name).exists():
            args += ['--bind', str(HOME / name), str(HOME / name)]
    if project:
        # The base's git objects live in the project (a shared clone).
        args += ['--ro-bind', str(project), str(project)]
    if Path('/run/den').is_dir():
        args += ['--ro-bind', '/run/den', '/system']
    # Docker's socket is root on this machine (`docker run -v /:/host`), so it
    # stays out of the sandbox unless the session was made with --docker.
    if not (session and session.get('docker')):
        for socket in DOCKER_SOCKETS:
            if os.path.exists(socket):
                args += ['--ro-bind', '/dev/null', socket]
    args += ['--bind', str(workspace), WORKSPACE, '--chdir', WORKSPACE,
             '--unshare-pid', '--unshare-ipc', '--unshare-uts', '--unshare-cgroup-try',
             '--die-with-parent', '--hostname', f'den-{session["id"]}' if session else 'den-setup']
    if not sys.stdin.isatty():
        args.append('--new-session')
    env = {'HOME': str(HOME), 'XDG_RUNTIME_DIR': f'/run/user/{UID}', 'DEN_WORKSPACE': WORKSPACE}
    for name in ('DBUS_SESSION_BUS_ADDRESS', 'SSH_AUTH_SOCK', 'WAYLAND_DISPLAY', 'DISPLAY',
                 'GNOME_KEYRING_CONTROL', 'GH_TOKEN', 'GITHUB_TOKEN', 'DOCKER_HOST'):
        args += ['--unsetenv', name]
    if session:
        first = PORT_BASE + session['slot'] * PORTS_EACH
        env.update(identity_env(session))
        env.update({'DEN_SESSION': session['id'], 'PORT': str(first),
                    'DEN_PORTS': f'{first}-{first + PORTS_EACH - 1}',
                    'COMPOSE_PROJECT_NAME': f'den-{session["id"]}'})
    fds = []
    if grants:
        args += ['--tmpfs', '/secrets']
        for name in grants:
            value = secret_value(name)
            env[name] = value
            read, write = os.pipe()
            os.write(write, value.encode())
            os.close(write)
            fds.append(read)
            args += ['--perms', '0400', '--file', str(read), f'/secrets/{name}']
    for key, value in env.items():
        args += ['--setenv', key, value]
    scope = ['systemd-run', '--user', '--scope', '--quiet', '--collect', '--slice=den-sessions.slice',
             f'--unit=den-session-{session["id"]}-{os.getpid()}' if session else f'--unit=den-base-{os.getpid()}']
    for key, value in LIMITS.items():
        scope += ['-p', f'{key}={value}']
    return scope + args + ['--', *command], fds


def run_sandboxed(argv, fds, **kwargs):
    try:
        return subprocess.run(argv, pass_fds=fds, **kwargs).returncode
    finally:
        for fd in fds:
            os.close(fd)


# Secrets: names the user stored with `den secret set`, granted per session --

def secret_value(name):
    result = subprocess.run(['secret-tool', 'lookup', 'service', 'den', 'name', name],
                            text=True, capture_output=True)
    if result.returncode or not result.stdout:
        raise Fail(f'no secret {name} (den secret set {name})')
    return result.stdout


def secret_names():
    result = subprocess.run(['secret-tool', 'search', '--all', 'service', 'den'],
                            text=True, capture_output=True)
    return sorted(set(re.findall(r'^attribute\.name = (.+)$', result.stdout + result.stderr, re.M)))


def cmd_secret(args):
    if args.secret_cmd == 'list':
        for name in secret_names():
            print(name)
    elif args.secret_cmd == 'set':
        if not re.fullmatch(r'[A-Z_][A-Z0-9_]*', args.name):
            raise Fail('a secret name is an environment variable name, like ANTHROPIC_API_KEY')
        value = sys.stdin.read().strip() if not sys.stdin.isatty() else __import__('getpass').getpass(f'{args.name}: ')
        if not value:
            raise Fail('empty value')
        subprocess.run(['secret-tool', 'store', '--label', f'Den Den: {args.name}', 'service', 'den',
                        'name', args.name], input=value, text=True, check=True)
    elif args.secret_cmd == 'remove':
        subprocess.run(['secret-tool', 'clear', 'service', 'den', 'name', args.name], check=True)
    return 0


# Bases -------------------------------------------------------------------------

def setup_command(tree):
    if os.access(tree / '.den/setup', os.X_OK):
        return ['./.den/setup'], ['.den/setup']
    for lockfile, command in INSTALLERS:
        if (tree / lockfile).is_file():
            return command, [lockfile]
    return None, []


def fingerprint(tree, files):
    digest = hashlib.sha256()
    for name in files:
        digest.update(name.encode() + b'\0' + (tree / name).read_bytes())
    return digest.hexdigest()


def base(project):
    """The project's base, at the project's current commit with its
    dependencies installed; made or brought up to date as needed."""
    key = str(project.relative_to(HOME) if project.is_relative_to(HOME) else project).strip('/').replace('/', '_').lstrip('.')
    tree = BASES / key
    meta_path = BASES / f'{key}.json'
    held = lock(BASES / f'{key}.lock')
    head = git(project, 'rev-parse', 'HEAD')
    meta = json.loads(meta_path.read_text()) if meta_path.is_file() else {}
    if not tree.exists():
        say(f'preparing {project.name} for sessions (the first time installs its dependencies)')
        subprocess.run(['btrfs', 'subvolume', 'create', str(tree)], check=True, stdout=subprocess.DEVNULL)
        git(tree, 'clone', '--quiet', '--shared', '--no-checkout', str(project), '.')
    if meta.get('commit') != head:
        git(tree, 'fetch', '--quiet', 'origin')
        git(tree, 'checkout', '--quiet', '--force', '--detach', head)
    command, files = setup_command(tree)
    stamp = fingerprint(tree, files)
    if command and meta.get('setup') != stamp:
        say(f'installing {project.name}\'s dependencies: {" ".join(command)}')
        argv, fds = sandbox(tree, command, project=project)
        if run_sandboxed(argv, fds, stdout=sys.stderr):
            raise Fail(f'{" ".join(command)} failed in the base; fix the project, then try again')
    meta = {'project': str(project), 'commit': head, 'setup': stamp, 'updated': int(time.time())}
    meta_path.write_text(json.dumps(meta, indent=2) + '\n')
    return tree, meta, held


def delete_tree(path):
    """A snapshot goes at once when the filesystem lets users delete their
    subvolumes (user_subvol_rm_allowed); otherwise file by file."""
    if subprocess.run(['btrfs', 'subvolume', 'delete', str(path)], capture_output=True).returncode:
        shutil.rmtree(path)


# Commands ----------------------------------------------------------------------

def cmd_create(args):
    project = Path(args.project).expanduser().resolve()
    if not (project / '.git').exists():
        raise Fail(f'{project} is not a git repository')
    name = args.name or f'{project.name}-{random.token_hex(2)}'
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
        raise Fail('a session name is letters, digits, dots, dashes and underscores')
    if (SESSIONS / name).exists():
        raise Fail(f'there is already a session {name}')
    for grant in args.secret or ():
        secret_value(grant)
    tree, meta, held = base(project)
    used = {s['slot'] for s in all_sessions()}
    slot = next((n for n in range(SLOTS) if n not in used), None)
    if slot is None:
        raise Fail(f'{SLOTS} sessions are open; commit or discard some')
    folder = SESSIONS / name
    folder.mkdir(parents=True)
    workspace = folder / 'workspace'
    subprocess.run(['btrfs', 'subvolume', 'snapshot', str(tree), str(workspace)], check=True,
                   stdout=subprocess.DEVNULL)
    held.close()
    git(workspace, 'switch', '--quiet', '-c', f'den/{name}')
    branch = git(project, 'symbolic-ref', '--quiet', '--short', 'HEAD', check=False) or 'detached HEAD'
    session = {'id': name, 'project': str(project), 'branch': branch, 'base': meta['commit'],
               'created': int(time.time()), 'slot': slot, 'secrets': sorted(set(args.secret or ())),
               'identity': identity(project), 'docker': bool(args.docker),
               'workspace': str(workspace)}
    save(session)
    record(session, 'create', base=meta['commit'])
    if session['docker']:
        say(DOCKER_WARNING)
    if git(project, 'status', '--porcelain', '--untracked-files=no'):
        say(f'{project.name} has uncommitted changes; the session starts from its last commit')
    if args.json:
        print(json.dumps(session, indent=2))
    else:
        print(name)
        say(f'workspace {workspace}; start it with: den session run {name}')
    return 0


def cmd_run(args):
    session = load(args.session)
    active = running()
    if session['id'] not in active and len(active) >= MAX_RUNNING:
        raise Fail(f'{len(active)} sessions are running, the most at once (DEN_SESSIONS_MAX={MAX_RUNNING}): '
                   + ', '.join(sorted(active)))
    if session.get('docker'):
        say(DOCKER_WARNING)
    command = args.command or [os.environ.get('SHELL', '/bin/bash')]
    if command[0] == '--':
        command = command[1:]
    argv, fds = sandbox(session['workspace'], command, session=session,
                        project=Path(session['project']), grants=session['secrets'])
    return run_sandboxed(argv, fds)


def changes(session):
    workspace = session['workspace']
    commits = git(workspace, 'log', '--format=%h %s', f'{session["base"]}..HEAD').splitlines()
    status = git(workspace, 'status', '--porcelain').splitlines()
    stat = git(workspace, 'diff', '--stat', session['base'])
    untracked = [line[3:] for line in status if line.startswith('??')]
    return {'commits': commits, 'uncommitted': [line for line in status if not line.startswith('??')],
            'untracked': untracked, 'stat': stat}


def cmd_list(args):
    sessions = all_sessions()
    active = running()
    rows = []
    for session in sessions:
        found = changes(session) if Path(session['workspace']).exists() else {}
        rows.append({**session, 'running': session['id'] in active,
                     'commits': len(found.get('commits', [])),
                     'changed_files': len(found.get('uncommitted', [])) + len(found.get('untracked', []))})
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    if not rows:
        print('No sessions.')
    for row in rows:
        state = 'running' if row['running'] else 'idle'
        print(f"{row['id']:28} {Path(row['project']).name:20} {state:8} "
              f"{row['commits']} commit(s), {row['changed_files']} changed file(s)")
    return 0


def cmd_review(args):
    session = load(args.session)
    found = changes(session)
    if args.json:
        found['diff'] = git(session['workspace'], 'diff', session['base'])
        # Sessions can't change the system yet: that comes with the broker.
        found['system_changes'] = []
        print(json.dumps({'session': session, **found}, indent=2))
        return 0
    print(f"{session['id']}: {Path(session['project']).name} from {session['branch']} at {session['base'][:10]}")
    for line in found['commits']:
        print(f'  commit {line}')
    for line in found['uncommitted']:
        print(f'  changed {line[3:]}')
    for line in found['untracked']:
        print(f'  new {line}')
    if not (found['commits'] or found['uncommitted'] or found['untracked']):
        print('  no changes')
        return 0
    print('No changes to the system (sessions can\'t make any yet).')
    if args.stat:
        print(found['stat'])
    else:
        subprocess.run(['git', '-C', session['workspace'], '--no-pager', 'diff', session['base']])
    return 0


def close(session, event, **extra):
    workspace = Path(session['workspace'])
    if workspace.exists():
        delete_tree(workspace)
    shutil.rmtree(SESSIONS / session['id'], ignore_errors=True)
    record(session, event, **extra)


def cmd_commit(args):
    session = load(args.session)
    if session['id'] in running():
        raise Fail(f"{session['id']} is still running; stop it first")
    workspace = session['workspace']
    if git(workspace, 'status', '--porcelain'):
        git(workspace, 'add', '--all')
        git(workspace, 'commit', '--quiet', '-m', args.message or f"Work from session {session['id']}",
            env=identity_env(session))
    commits = git(workspace, 'rev-list', '--count', f'{session["base"]}..HEAD')
    if commits == '0':
        raise Fail('nothing to commit; discard the session instead')
    project = Path(session['project'])
    branch = f"den/{session['id']}"
    git(project, 'fetch', '--quiet', workspace, f'HEAD:refs/heads/{branch}')
    merged = False
    if args.merge:
        current = git(project, 'symbolic-ref', '--quiet', '--short', 'HEAD', check=False)
        clean = not git(project, 'status', '--porcelain', '--untracked-files=no')
        if not (current and clean):
            say(f'{project.name} has uncommitted changes or no branch checked out; left on {branch}')
        elif subprocess.run(['git', '-C', str(project), 'merge', '--quiet', '--ff-only', branch],
                            capture_output=True).returncode:
            say(f'{current} has moved on since the session started; merge {branch} yourself')
        else:
            merged = True
    close(session, 'commit', branch=branch, commits=int(commits), merged=merged)
    print(f'{commits} commit(s) on {branch} in {project}' + (f', merged into {current}' if merged else ''))
    return 0


def cmd_discard(args):
    session = load(args.session)
    if session['id'] in running():
        raise Fail(f"{session['id']} is still running; stop it first")
    close(session, 'discard')
    print(f"Discarded {session['id']}.")
    return 0


def add_parsers(top):
    p = top.add_parser('session', help='sandboxed agent sessions').add_subparsers(dest='cmd', required=True)
    c = p.add_parser('create', help='a new session on a project')
    c.add_argument('project')
    c.add_argument('--name')
    c.add_argument('--secret', action='append', metavar='NAME', help='grant a stored secret (repeatable)')
    c.add_argument('--docker', action='store_true',
                   help='let the session use Docker (root on this machine: gives up the sandbox)')
    c.add_argument('--json', action='store_true')
    c.set_defaults(fn=cmd_create)
    r = p.add_parser('run', help='run a command (default: a shell) in the session\'s sandbox')
    r.add_argument('session')
    r.add_argument('command', nargs='*')
    r.set_defaults(fn=cmd_run)
    ls = p.add_parser('list')
    ls.add_argument('--json', action='store_true')
    ls.set_defaults(fn=cmd_list)
    v = p.add_parser('review', help='what the session changed')
    v.add_argument('session')
    v.add_argument('--stat', action='store_true')
    v.add_argument('--json', action='store_true')
    v.set_defaults(fn=cmd_review)
    m = p.add_parser('commit', help='bring the work back to the project as branch den/<session>')
    m.add_argument('session')
    m.add_argument('-m', '--message')
    m.add_argument('--merge', action='store_true', help='also fast-forward the project\'s branch')
    m.set_defaults(fn=cmd_commit)
    d = p.add_parser('discard')
    d.add_argument('session')
    d.set_defaults(fn=cmd_discard)

    s = top.add_parser('secret', help='secrets sessions can be granted').add_subparsers(dest='secret_cmd', required=True)
    s.add_parser('list').set_defaults(fn=cmd_secret)
    for name in ('set', 'remove'):
        q = s.add_parser(name)
        q.add_argument('name')
        q.set_defaults(fn=cmd_secret)


def main(args):
    if os.geteuid() == 0:
        say('run den session as your normal user')
        return 2
    try:
        return args.fn(args)
    except Fail as error:
        say(error)
        return 1
    except subprocess.CalledProcessError as error:
        say(f'{" ".join(map(str, error.cmd[:3]))} … failed (exit {error.returncode})')
        return 1
