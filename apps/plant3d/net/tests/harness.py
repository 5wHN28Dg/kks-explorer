"""The multi-instance harness (docs/plant3d/MULTIPLAYER.md §12): N headless Godot processes, each the engine and the
session layer (instance.gd), on their own ports and with their own user data, driven by plans of actions; a replay
(replay.gd) of the host's commits through one engine; the network simulator (netsim.py) between them when asked.

Run under a memory cap (each instance with the first train is about 150 MB of PSS, measured by the instances
themselves: `pss_kb` in their output).
"""
import json
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, '..', '..'))
ROOT = os.path.normpath(os.path.join(PROJECT, '..', '..'))
DATA = os.path.join(ROOT, 'data', 'plant3d')
CODE = 'K3QX9F2MHT4C7PW5'


def godot():
    g = os.environ.get('GODOT')
    if g:
        return g
    return subprocess.run([os.path.join(ROOT, 'tools', 'plant3d', 'bench', 'fetch_godot.sh')], check=True,
                          capture_output=True, text=True).stdout.strip()


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class Instance:
    def __init__(self, h, name, role, plan, args):
        self.h, self.name, self.role = h, name, role
        self.dir = os.path.join(h.tmp, name)
        os.makedirs(os.path.join(self.dir, 'xdg', 'godot'), exist_ok=True)
        self.out = os.path.join(self.dir, 'out.json')
        self.plan_file = os.path.join(self.dir, 'plan.json')
        self.args, self.plan = args, plan
        self.proc = None
        self.result = None
        self.log = os.path.join(self.dir, 'log.txt')

    def start(self):
        if os.path.exists(self.out):
            os.remove(self.out)
        with open(self.plan_file, 'w') as f:
            json.dump(sorted(self.plan, key=lambda a: a.get('t', 0)), f)    # (the instance takes them in order)
        env = dict(os.environ, XDG_DATA_HOME=os.path.join(self.dir, 'xdg'))
        cmd = [self.h.godot, '--headless', '--path', PROJECT, '--script', 'res://net/tests/instance.gd', '--',
               f'--role={self.role}', f'--code={CODE}', f'--data={self.h.data}', f'--scenario={self.h.scenario}',
               f'--name={self.name}', f'--speed={self.h.speed}', f'--plan={self.plan_file}', f'--out={self.out}'] \
            + self.args
        self.logf = open(self.log, 'a')
        self.proc = subprocess.Popen(cmd, stdout=self.logf, stderr=subprocess.STDOUT, env=env)
        return self

    def wait_ready(self, timeout=60):
        t = time.monotonic() + timeout
        while time.monotonic() < t:
            with open(self.log) as f:
                for line in f:
                    if line.startswith('READY'):
                        return [int(x) for x in line.split()[1:]]
            if self.proc.poll() is not None:
                raise RuntimeError(f'{self.name} stopped: ' + open(self.log).read()[-3000:])
            time.sleep(0.05)
        raise RuntimeError(f'{self.name} not ready')

    def kill(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGKILL)
            self.proc.wait()

    def wait(self, timeout):
        try:
            self.proc.wait(timeout)
        except subprocess.TimeoutExpired:
            self.kill()
            raise RuntimeError(f'{self.name} did not finish: ' + open(self.log).read()[-3000:])
        self.logf.close()
        if os.path.exists(self.out):
            with open(self.out) as f:
                self.result = json.load(f)
        return self.result

    def script_errors(self):
        with open(self.log) as f:
            return [ln for ln in f if 'SCRIPT ERROR' in ln]


class Harness:
    def __init__(self, scenario='cold_iron', speed=10, data=DATA):
        self.tmp = tempfile.mkdtemp(prefix='wdp-mp-')
        self.godot = godot()
        self.scenario, self.speed, self.data = scenario, speed, data
        self.disc, self.port = free_port(), free_port()
        self.instances = []
        self.sim = None

    def host(self, plan, name='host'):
        i = Instance(self, name, 'host', plan, [f'--disc={self.disc}', f'--port={self.port}']).start()
        i.wait_ready()
        self.instances.append(i)
        return i

    def join(self, plan, name, link=None, code=None):
        args = [f'--addr=127.0.0.1:{link.disc_port if link else self.disc}', f'--disc={self.disc}']
        if code:
            args.append(f'--code={code}')
        if link:
            args.append(f'--via=127.0.0.1:{link.sess_port}')
        i = Instance(self, name, 'join', plan, args).start()
        self.instances.append(i)
        return i

    def netsim(self):
        from netsim import NetSim
        self.sim = NetSim(self.disc, self.port)
        return self.sim

    def wait_all(self, timeout=180):
        out = {}
        for i in self.instances:
            if i.proc.poll() is None or i.result is None:
                out[i.name] = i.wait(timeout)
        return {i.name: i.result for i in self.instances}

    def replay(self, host_out, to):
        out = os.path.join(self.tmp, f'replay-{to}.json')
        with open(os.path.join(self.tmp, 'host-for-replay.json'), 'w') as f:
            json.dump(host_out, f)
        subprocess.run([self.godot, '--headless', '--path', PROJECT, '--script', 'res://net/tests/replay.gd', '--',
                        f'--data={self.data}', f'--scenario={self.scenario}',
                        f'--host={os.path.join(self.tmp, "host-for-replay.json")}', f'--to={to}', f'--out={out}'],
                       check=True, capture_output=True, timeout=300,
                       env=dict(os.environ, XDG_DATA_HOME=os.path.join(self.tmp, 'replay-xdg')))
        with open(out) as f:
            return json.load(f)

    def close(self):
        for i in self.instances:
            i.kill()
        if self.sim:
            self.sim.stop()
        if not os.environ.get('WDP_KEEP'):
            shutil.rmtree(self.tmp, ignore_errors=True)
