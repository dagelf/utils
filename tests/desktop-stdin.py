#!/usr/bin/env python3
"""Regression: a password-fed RDP client must still accept terminal responses."""
import errno
import os
from pathlib import Path
import pty
import select
import signal
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as fixture:
    viewer = Path(fixture) / 'rdesktop'
    viewer.write_text('''#!/usr/bin/env python3
import os, sys
assert 'DESKTOP_PASSWORD' not in os.environ
assert 'fixture-secret' not in sys.argv
assert sys.stdin.readline() == 'fixture-secret\\n'
print('Trust certificate (yes/no)?', flush=True)
answer = sys.stdin.readline().strip()
print('ANSWER=' + answer, flush=True)
sys.exit(0 if answer == 'yes' else 7)
''')
    viewer.chmod(0o755)
    for answer, expected in ((b'yes\n', 0), (b'no\n', 7), (b'\x04', 7)):
        pid, master = pty.fork()
        if pid == 0:
            os.environ['PATH'] = f'{fixture}:{repo}/scripts:' + os.environ['PATH']
            script = '''source <(sed -n '/^function __desktop_password_launch () {/,/^function rd () {/p' "$1/aliases" | head -n -1)
__desktop_password_launch fixture-secret rdesktop
'''
            os.execvp('bash', ['bash', '--noprofile', '--norc', '-c', script, 'bash', str(repo)])
        output = b''
        sent = False
        deadline = time.monotonic() + 5
        try:
            while True:
                remaining = deadline - time.monotonic()
                assert remaining > 0, 'terminal interaction timed out'
                readable, _, _ = select.select([master], [], [], remaining)
                assert readable, 'terminal interaction timed out'
                try:
                    data = os.read(master, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                output += data
                if b'Trust certificate (yes/no)?' in output and not sent:
                    os.write(master, answer)
                    sent = True
            _, status = os.waitpid(pid, 0)
            pid = None
            assert os.waitstatus_to_exitcode(status) == expected, output
            response = b'' if answer == b'\x04' else answer.strip()
            assert sent and b'ANSWER=' + response in output, output
            assert b'fixture-secret' not in output, 'password echoed to terminal'
        finally:
            os.close(master)
            if pid is not None:
                os.killpg(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
print('PASS: foreground RDP accepts yes/no after password input; no password in argv, env or terminal output; relay exits with client.')
