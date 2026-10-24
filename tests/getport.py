#!/usr/bin/env python3
"""Exercise the CLI against an isolated registry and real sockets."""
import contextlib
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/getport"


class GetportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = {**os.environ, "XDG_STATE_HOME": self.tmp.name}
        self.database = Path(self.tmp.name) / "dagelf-utils/ports.sqlite3"

    def cli(self, *args, status=0):
        result = subprocess.run([str(SCRIPT), *args], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, status, result.stderr)
        return result

    def test_url_and_lookup(self):
        first = self.cli("accounting")
        port = int(first.stdout)
        self.assertEqual(first.stderr, f"http://accounting.localhost:{port}\n")
        self.assertEqual(self.cli("accounting").stdout, first.stdout)
        lookup = self.cli("--lookup", "accounting")
        self.assertEqual(lookup.stdout, first.stdout)
        self.assertEqual(lookup.stderr, "")
        # Arbitrary existing names still yield valid, distinct browser origins.
        urls = set()
        for name in ["a:b", "a/b", "!!!", "x" * 100, "測試"]:
            result = self.cli(name)
            self.assertRegex(result.stderr, r"^http://[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.localhost:\d+\n$")
            urls.add(result.stderr)
        self.assertEqual(len(urls), 5)
        anonymous = self.cli()
        self.assertTrue(anonymous.stdout.strip().isdigit())
        self.assertIn(".localhost:" + anonymous.stdout.strip(), anonymous.stderr)

    def test_empty_and_bad_arguments(self):
        self.assertEqual(self.cli("--list").stdout, "")
        self.assertEqual(self.cli("--clean").stdout, "")
        self.cli("--lookup", "absent", status=1)
        self.assertFalse(self.database.exists())
        for args in [("--list", "extra"), ("--clean", "extra"), ("--lookup",), ("--unknown",)]:
            self.cli(*args, status=2)

    def test_cleanup_keeps_bound_ports_and_recycles_unused(self):
        unused = int(self.cli("unused").stdout)
        with contextlib.ExitStack() as stack:
            occupied = []
            for family, address in [(socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::")]:
                for kind in [socket.SOCK_STREAM, socket.SOCK_DGRAM]:
                    port = int(self.cli(f"bound-{family}-{kind}").stdout)
                    sock = stack.enter_context(socket.socket(family, kind))
                    if family == socket.AF_INET6:
                        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
                    sock.bind((address, port))
                    if kind == socket.SOCK_STREAM:
                        sock.listen()
                    occupied.append(port)
            self.assertEqual(len(self.cli("--list").stdout.splitlines()), 5)
            self.assertEqual(self.cli("--clean").stdout, f"{unused}\tunused\n")
            listed = [int(row.split("\t")[0]) for row in self.cli("--list").stdout.splitlines()]
            self.assertEqual(listed, sorted(occupied))
            self.cli("--lookup", "unused", status=1)
            self.assertEqual(int(self.cli("replacement").stdout), unused)

    def test_cleanup_rolls_back_on_failure(self):
        self.cli("first")
        self.cli("second")
        before = self.cli("--list").stdout
        with sqlite3.connect(self.database) as db:
            db.execute("CREATE TRIGGER reject_cleanup BEFORE DELETE ON ports "
                       "WHEN OLD.name = 'second' BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        failed = self.cli("--clean", status=2)
        self.assertEqual(failed.stdout, "")
        self.assertEqual(self.cli("--list").stdout, before)
        with sqlite3.connect(self.database) as db:
            self.assertEqual(db.execute("SELECT count(*) FROM free_ports").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main()
