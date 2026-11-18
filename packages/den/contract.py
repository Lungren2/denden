"""den's read-only contract: the machine, packages, services, history and
health, from dend (the Varlink service on /run/den/io.denden), for people
(`den doctor`), scripts (`--json`) and agents (`den mcp`, an MCP server with
the same operations as tools)."""
import json
import os
import socket
import sys
import time

SOCKET = os.environ.get('DEN_SOCKET', '/run/den/io.denden')
VERSION = '0.1.0'


class Unavailable(Exception):
    pass


def call(method, **parameters):
    """One Varlink call to dend; parameters left as None are omitted."""
    request = {'method': method, 'parameters': {k: v for k, v in parameters.items() if v is not None}}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(60)
            connection.connect(SOCKET)
            connection.sendall(json.dumps(request).encode() + b'\0')
            reply = b''
            while not reply.endswith(b'\0'):
                chunk = connection.recv(1 << 16)
                if not chunk:
                    break
                reply += chunk
    except OSError as error:
        raise Unavailable(f"can't reach dend at {SOCKET} ({error.strerror or error}); "
                          'start it with: sudo systemctl start dend.socket') from None
    reply = json.loads(reply.rstrip(b'\0') or b'{}')
    if 'error' in reply:
        detail = ', '.join(f'{k}: {v}' for k, v in reply.get('parameters', {}).items())
        raise Unavailable(f"dend: {reply['error']}" + (f' ({detail})' if detail else ''))
    return reply.get('parameters', {})


# The operations, shared by the command line and the MCP server.
OPERATIONS = {
    'machine_inspect': {
        'method': 'io.denden.Machine.Inspect',
        'title': 'Inspect the machine',
        'description': 'Hardware, kernel, firmware, disks and free space of the Den Den machine. '
                       'Sizes are in bytes, uptime in seconds; root_subvolume names a snapshot when '
                       'the machine was started from one.',
        'schema': {},
    },
    'machine_doctor': {
        'method': 'io.denden.Machine.Doctor',
        'title': 'Check the machine\'s health',
        'description': 'Health checks, each ok, warn or fail with a readable detail: disk space, disk '
                       '(SMART) health, failed systemd units, T3 Code running, Tailscale, the last '
                       'backup, snapshots, Den Den package updates. Run it first when something on '
                       'the machine seems wrong.',
        'schema': {},
    },
    'package_query': {
        'method': 'io.denden.Package.Query',
        'title': 'Look up packages',
        'description': 'Packages from pacman\'s databases as last synced: installed version, the '
                       'repository upgrades come from and its version, the repository the installed '
                       'version came from (origin; denden-local means changed on this machine with den '
                       'src), install reason and date, and the source tree in /src if there is one. '
                       'Give names for exact packages (installed or not), search for installed ones '
                       'whose name or description contains a word, or neither for every explicitly '
                       'installed package.',
        'schema': {
            'names': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Exact package names.'},
            'search': {'type': 'string', 'description': 'Text in an installed package\'s name or description.'},
        },
    },
    'service_status': {
        'method': 'io.denden.Service.Status',
        'title': 'Check services',
        'description': 'systemd units of the system and of your user session: load, active and sub '
                       'state, enablement, last result, since when (seconds since the epoch). Give '
                       'names (".service" may be left off); user true looks only in your session, '
                       'false only in the system. With failed, or no names, lists every failed unit.',
        'schema': {
            'names': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Unit names.'},
            'user': {'type': 'boolean', 'description': 'true: your session only; false: the system only.'},
            'failed': {'type': 'boolean', 'description': 'Also list every failed unit.'},
        },
    },
    'history_query': {
        'method': 'io.denden.History.Query',
        'title': 'Search the machine\'s history',
        'description': 'What happened on the machine, newest first: package transactions (each change, '
                       'the command, and the root snapshots before and after, which the recovery menu '
                       'can start), manual snapshots, and boots. text matches case-insensitively; since '
                       'is 30m, 12h, 3d, 2w or a YYYY-MM-DD date; limit defaults to 50.',
        'schema': {
            'text': {'type': 'string', 'description': 'Text to find, e.g. a package name.'},
            'since': {'type': 'string', 'description': '30m, 12h, 3d, 2w, or YYYY-MM-DD.'},
            'limit': {'type': 'integer', 'minimum': 1, 'description': 'Most events to return (50).'},
        },
    },
}


# For people ------------------------------------------------------------------

def size(value):
    value = float(value or 0)
    for unit in ('bytes', 'KB', 'MB', 'GB', 'TB'):
        if value < 1000 or unit == 'TB':
            return f'{value:.0f} bytes' if unit == 'bytes' else f'{value:.1f} {unit}'
        value /= 1000


def when(seconds):
    if not seconds:
        return ''
    stamp = time.localtime(seconds)
    if time.strftime('%Y-%m-%d', stamp) == time.strftime('%Y-%m-%d'):
        return time.strftime('today %H:%M', stamp)
    return time.strftime('%Y-%m-%d %H:%M', stamp)


def duration(seconds):
    days, rest = divmod(int(seconds), 86400)
    hours, rest = divmod(rest, 3600)
    minutes = rest // 60
    parts = [f'{days} d'] * bool(days) + [f'{hours} h'] * bool(hours) + [f'{minutes} min']
    return ' '.join(parts[:2])


def show_machine(info):
    print(f"{info['hostname']}: Den Den {info['denden']} on {info['os']}, kernel {info['kernel']}")
    print(f"Up {duration(info['uptime'])}, started from {info['root_subvolume'] or '/'}")
    rows = [
        ('CPU', f"{info['cpu']} ({info['threads']} threads)"),
        ('Memory', f"{size(info['memory'])} ({size(info['memory_available'])} available)"),
        *[('GPU', gpu) for gpu in info['gpus']],
        ('Board', f"{info['board']}; firmware {info['firmware']['vendor']} {info['firmware']['version']} "
                  f"({info['firmware']['date']})"),
    ]
    for disk in info['disks']:
        notes = [disk['transport']] + ['removable'] * disk['removable'] + ['Den Den'] * disk['system']
        rows.append(('Disk', f"{disk['name']}: {disk['model']}, {size(disk['size'])} ({', '.join(n for n in notes if n)})"))
    # One line per filesystem; Btrfs subvolumes share their filesystem's space.
    groups = {}
    for fs in info['filesystems']:
        device = fs['source'].split('[')[0]
        groups.setdefault(device, []).append(fs)
    for device, mounts in groups.items():
        first = mounts[0]
        where = ', '.join(fs['mount'] for fs in mounts)
        rows.append(('Space', f"{size(first['available'])} free of {size(first['size'])} on {device} "
                              f"({first['fstype']}: {where})"))
    for label, value in rows:
        print(f'{label:8} {value}')


MARK = {'ok': '✓', 'warn': '!', 'fail': '✗'}


def show_doctor(report):
    width = max(len(check['title']) for check in report['checks'])
    for check in report['checks']:
        print(f"{MARK[check['status']]} {check['title']:{width}}  {check['detail']}")


def show_packages(result, long):
    packages = result['packages']
    if long:
        for package in packages:
            installed = package['version'] or 'not installed'
            print(f"{package['name']} {installed}")
            for key, value in (
                ('Description', package['description']),
                ('From', package['origin'] or ('no repository has this version' if package['version'] else '')),
                ('Upgrades from', f"{package['repository']} ({package['available']})" if package['repository'] else 'no repository'),
                ('Installed', f"{when(package['install_date'])}, as {package['reason']}, "
                              f"{size(package['installed_size'])}" if package['version'] else ''),
                ('Source', package['source_tree'] or ''),
                ('URL', package['url']),
            ):
                if value:
                    print(f'  {key + ":":14} {value}')
    else:
        width = max([len(p['name']) for p in packages] + [4])
        for package in packages:
            origin = package['origin'] or '?'
            newer = f" → {package['available']}" if package['available'] and package['version'] and package['available'] != package['version'] else ''
            print(f"{package['name']:{width}}  {package['version'] or '-'} ({origin}){newer}  {package['description']}")
    for name in result['missing']:
        print(f'{name}: no such package', file=sys.stderr)


def show_units(result):
    for unit in result['units']:
        state = f"{unit['active']} ({unit['sub']})"
        since = f" since {when(unit['since'])}" if unit['since'] else ''
        result_note = f", last result {unit['result']}" if unit['result'] not in ('', 'success') else ''
        print(f"{unit['name']} [{unit['scope']}]: {state}{since}, {unit['enabled']}{result_note} — {unit['description']}")
    if not result['units'] and not result['missing']:
        print('No failed units.')
    for name in result['missing']:
        print(f'{name}: no such unit', file=sys.stderr)


def show_history(result, verbose):
    for event in result['events']:
        print(f"{when(event['time']):16}  {event['summary']}")
        if verbose:
            for detail in event['details']:
                print(f'{"":18}{detail}')


def command(args):
    """Run one `den machine|doctor|package|service|history` command."""
    try:
        if args.area == 'machine':
            result = call('io.denden.Machine.Inspect')
            print(json.dumps(result, indent=2)) if args.json else show_machine(result)
        elif args.area == 'doctor':
            result = call('io.denden.Machine.Doctor')
            print(json.dumps(result, indent=2)) if args.json else show_doctor(result)
            return 1 if result['status'] == 'fail' else 0
        elif args.area == 'package':
            result = call('io.denden.Package.Query', names=args.names or None, search=args.search)
            print(json.dumps(result, indent=2)) if args.json else show_packages(result, bool(args.names))
            return 1 if result['missing'] else 0
        elif args.area == 'service':
            user = True if args.user else False if args.system else None
            result = call('io.denden.Service.Status', names=args.names or None, user=user,
                          failed=True if args.failed else None)
            print(json.dumps(result, indent=2)) if args.json else show_units(result)
            return 1 if result['missing'] else 0
        elif args.area == 'history':
            result = call('io.denden.History.Query', text=args.text, since=args.since, limit=args.limit)
            print(json.dumps(result, indent=2)) if args.json else show_history(result, args.verbose)
    except Unavailable as error:
        print(f'den: {error}', file=sys.stderr)
        return 2
    return 0


# For agents: an MCP server on stdin/stdout -----------------------------------

INSTRUCTIONS = ('Den Den\'s machine API, read-only: inspect the hardware and storage, check health '
                '(machine_doctor), look up packages and services, and search what happened on the '
                'machine (package changes with their snapshots, boots). Prefer these to parsing '
                'shell output.')


def tools():
    return [{
        'name': name,
        'title': operation['title'],
        'description': operation['description'],
        'inputSchema': {'type': 'object', 'properties': operation['schema'], 'additionalProperties': False},
        'annotations': {'title': operation['title'], 'readOnlyHint': True, 'openWorldHint': False},
    } for name, operation in OPERATIONS.items()]


def handle(message):
    method = message.get('method')
    params = message.get('params') or {}
    if method == 'initialize':
        return {
            'protocolVersion': params.get('protocolVersion', '2025-06-18'),
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'den', 'title': 'Den Den', 'version': VERSION},
            'instructions': INSTRUCTIONS,
        }
    if method == 'ping':
        return {}
    if method == 'tools/list':
        return {'tools': tools()}
    if method == 'tools/call':
        operation = OPERATIONS.get(params.get('name'))
        if not operation:
            raise LookupError(f"unknown tool: {params.get('name')}")
        arguments = {k: v for k, v in (params.get('arguments') or {}).items() if k in operation['schema']}
        try:
            result = call(operation['method'], **arguments)
        except Unavailable as error:
            return {'content': [{'type': 'text', 'text': str(error)}], 'isError': True}
        return {'content': [{'type': 'text', 'text': json.dumps(result)}], 'structuredContent': result}
    raise NotImplementedError(method)


def mcp():
    """JSON-RPC 2.0, one message per line (MCP's stdio transport)."""
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            reply = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'parse error'}}
            print(json.dumps(reply), flush=True)
            continue
        if 'id' not in message:
            continue                        # a notification, e.g. notifications/initialized
        reply = {'jsonrpc': '2.0', 'id': message['id']}
        try:
            reply['result'] = handle(message)
        except NotImplementedError as error:
            reply['error'] = {'code': -32601, 'message': f'method not found: {error}'}
        except LookupError as error:
            reply['error'] = {'code': -32602, 'message': str(error)}
        print(json.dumps(reply), flush=True)
    return 0
