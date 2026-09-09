#!/usr/bin/env python3
"""Exercise handoff and expired/dead-session refusal without operating any app."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('agent_mode', Path(__file__).with_name('agent-mode.py'))
mode = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mode)


class HandoffTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.directory = Path(self.scratch.name).resolve()
        self.state = dict(token='fixture-session', expires=110, phase='active', pid=123)
        (self.directory / 'ready').write_text(self.state['token'])
        self.path = self.directory / 'session.json'
        mode.write(self.path, self.state)
        for target, kwargs in [
            ('time.time', dict(return_value=100)),
            ('os.kill', dict(return_value=None)),
            ('subprocess.check_output', dict(return_value=f"{self.directory}/Agent Mode.app/Contents/MacOS/agent-banner {self.directory} fixture-session")),
        ]:
            mock = patch.object(getattr(mode, target.split('.')[0]), target.split('.')[1], **kwargs)
            mock.start(); self.addCleanup(mock.stop)

    def command(self, command):
        with patch.object(mode.os.sys, 'argv', ['agent-mode.py', command, '--session', str(self.directory)]):
            mode.main()

    def test_active_check_renews_but_status_does_not(self):
        self.command('status')
        self.assertEqual(json.loads(self.path.read_text())['expires'], 110)
        self.command('check')
        self.assertEqual(json.loads(self.path.read_text())['expires'], 190)

    def test_control_request_survives_heartbeat_and_requires_stop(self):
        (self.directory / 'control-requested').write_text('fixture-session')
        with self.assertRaisesRegex(RuntimeError, 'USER REQUESTED CONTROL'):
            self.command('check')
        self.assertEqual(json.loads(self.path.read_text())['expires'], 110)
        self.command('stop')
        with self.assertRaisesRegex(RuntimeError, 'stopped'):
            self.command('check')

    def test_expiry_cannot_be_silently_renewed(self):
        with patch.object(mode.time, 'time', return_value=110):
            with self.assertRaisesRegex(RuntimeError, 'expired'):
                self.command('check')
        self.assertEqual(json.loads(self.path.read_text())['expires'], 110)

    def test_request_during_renewal_still_blocks_the_action(self):
        original_write = mode.write
        def request_during_write(path, value):
            (self.directory / 'control-requested').write_text('fixture-session')
            original_write(path, value)
        with patch.object(mode, 'write', side_effect=request_during_write):
            with self.assertRaisesRegex(RuntimeError, 'USER REQUESTED CONTROL'):
                self.command('check')

    def test_dead_or_reused_process_blocks_actions(self):
        with patch.object(mode.os, 'kill', side_effect=ProcessLookupError):
            with self.assertRaises(ProcessLookupError):
                self.command('check')
        with patch.object(mode.subprocess, 'check_output', return_value='unrelated process'):
            with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                self.command('check')

    def test_banner_must_acknowledge_current_session(self):
        (self.directory / 'ready').write_text('previous-session')
        with self.assertRaisesRegex(RuntimeError, 'not acknowledged'):
            self.command('check')


unittest.main()
