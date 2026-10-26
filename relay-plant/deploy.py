"""Deploys Walkdown Plant's relay, only on an account on the Workers Free plan (docs/plant3d/MULTIPLAYER.md §9.1), and
smoke-tests it. Never prints the relay's address: it goes to the file given with --url-file, which must be outside the
repository (the address never goes into tracked files).

  cd relay-plant && npm ci --ignore-scripts && npx wrangler login
  PLANT_RELAY_BILLING_TOKEN=… python3 deploy.py --url-file ~/somewhere/plant-relay-url.txt
  python3 deploy.py --smoke --url-file ~/somewhere/plant-relay-url.txt      (the smoke test alone)

PLANT_RELAY_BILLING_TOKEN is a Cloudflare API token with the permission Account > Billing > Read (nothing else is
needed): wrangler's own login can't read the account's subscriptions. The plan check fails closed: if the
subscriptions can't be read, nothing is deployed."""
import argparse, json, os, re, subprocess, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
API = 'https://api.cloudflare.com/client/v4'


def stop(msg):
    print('deploy.py: ' + msg, file=sys.stderr)
    sys.exit(1)


def wrangler(*args, capture=True):
    exe = os.path.join(HERE, 'node_modules', '.bin', 'wrangler')
    if not os.path.exists(exe):
        stop('no pinned wrangler: run `npm ci --ignore-scripts` here first')
    return subprocess.run([exe, *args], cwd=HERE, capture_output=capture, text=True,
                          env=dict(os.environ, WRANGLER_SEND_METRICS='false'))


def paid_plans(subscriptions):
    """The subscriptions in an account's list that could be billed: any with a price that is not a number 0, and any
    Workers plan other than the free one. The Workers Paid plan is an account subscription ($5 a month), so an account
    on Workers Free has none of these; anything not understood counts as paid (the check fails closed)."""
    out = []
    for s in subscriptions:
        if not isinstance(s, dict):
            out.append(repr(s)[:40]); continue
        rp = str((s.get('rate_plan') or {}).get('id') or '?')
        price = s.get('price')
        if isinstance(price, bool) or not isinstance(price, (int, float)) or price != 0 or \
                ('worker' in rp.lower() and rp.lower() not in ('workers_free', 'free')):
            out.append(rp)
    return out


def check_free(account, token):
    req = urllib.request.Request(f'{API}/accounts/{account}/subscriptions', headers={'Authorization': f'Bearer {token}'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = json.load(r)
    except Exception as e:   # (an HTTP error, a network error, not JSON: the plan is unknown)
        stop(f'could not read the account\'s subscriptions ({type(e).__name__}): the plan can\'t be confirmed as Workers Free, nothing deployed')
    if not body.get('success') or not isinstance(body.get('result'), list):
        stop('the account\'s subscriptions could not be read: the plan can\'t be confirmed as Workers Free, nothing deployed')
    paid = paid_plans(body['result'])
    if paid:
        stop(f'the account has {", ".join(paid)}: not the Workers Free plan, nothing deployed')


def config_ok():
    with open(os.path.join(HERE, 'wrangler.toml'), encoding='utf-8') as f:
        text = f.read()
    if re.search(r'^\s*\[\s*vars\s*\]|^\s*vars\s*=', text, re.M):
        stop('wrangler.toml sets variables: the deployed relay must run with the spec\'s limits alone')


def smoke(url):
    sys.path.insert(0, HERE)
    from twin import Client, unframe
    room, admit = os.urandom(16).hex(), os.urandom(32)
    a = Client(url, room)
    w = a.hello(admit, True)
    assert w == {'t': 'welcome', 'id': 1, 'peers': [], 'host': 1}, w
    b = Client(url, room)
    w = b.hello(admit, False)
    assert w == {'t': 'welcome', 'id': 2, 'peers': [1], 'host': 1}, w
    assert a.json(10) == {'t': 'joined', 'id': 2}
    p = os.urandom(200)
    b.packets(1, p)
    assert unframe(a.binary(10)) == (2, [p])
    a.packets(0, b'back')
    assert unframe(b.binary(10)) == (1, [b'back'])
    a.text(b'{"t":"ping"}')
    assert a.json(10) == {'t': 'pong'}
    bad = Client(url, room)
    bad.text({'t': 'hello', 'admit': 'A' * 43, 'create': False})
    assert bad.json(10) == {'t': 'error', 'why': 'bad admit'}
    for c in (a, b, bad):
        c.close()
    print('smoke test passed: two clients joined a room and exchanged packets; a wrong admit was refused')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--url-file', required=True, help='where the relay\'s wss:// address is written (outside the repository)')
    ap.add_argument('--smoke', action='store_true', help='only the smoke test, against the address in --url-file')
    args = ap.parse_args()
    url_file = os.path.abspath(os.path.expanduser(args.url_file))
    if url_file == REPO or url_file.startswith(REPO + os.sep):
        stop('--url-file must be outside the repository')
    if args.smoke:
        with open(url_file, encoding='utf-8') as f:
            smoke(f.read().strip())
        return
    config_ok()
    who = wrangler('whoami', '--json')
    try:
        me = json.loads(who.stdout)
    except ValueError:
        me = {}
    if who.returncode or not me.get('loggedIn'):
        stop('wrangler is not logged in (npx wrangler login): nothing deployed')
    accounts = [a['id'] for a in me.get('accounts', [])]
    account = os.environ.get('CLOUDFLARE_ACCOUNT_ID') or (accounts[0] if len(accounts) == 1 else None)
    if not account or account not in accounts:
        stop('one account is needed: set CLOUDFLARE_ACCOUNT_ID to one of wrangler whoami\'s accounts')
    token = os.environ.get('PLANT_RELAY_BILLING_TOKEN')
    if not token:
        stop('PLANT_RELAY_BILLING_TOKEN is not set (an API token with Account > Billing > Read): the plan can\'t be '
             'confirmed as Workers Free, nothing deployed')
    check_free(account, token)
    print('the account is on the Workers Free plan; deploying')
    out = wrangler('deploy')
    if out.returncode:
        stop('wrangler deploy failed:\n' + out.stderr[-3000:])
    m = re.search(r'https://[a-z0-9.-]+\.workers\.dev', out.stdout + out.stderr)
    if not m:
        stop('deployed, but no workers.dev address in wrangler\'s output')
    url = 'wss://' + m[0][len('https://'):]
    fd = os.open(url_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        f.write(url + '\n')
    print(f'deployed; the address is in {url_file}')
    smoke(url)


if __name__ == '__main__':
    main()
