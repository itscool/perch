#!/usr/bin/env python3
"""Offline wrapper tests: temporary cache and mocked runner, no release operations."""
from contextlib import redirect_stdout, redirect_stderr
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_launcher', Path(__file__).with_name('release-launcher.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def invoke(arguments):
    try:
        with patch.object(sys, 'argv', ['release.sh', *arguments]), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            m.main()
    except SystemExit as error:
        return error.code
    return 0

for arguments in [[], ['--help'], ['--wat'], ['--publish'], ['--prepare-tools', '--publish'], ['--output', 'x', '--wait-seconds', '-1']]:
    with patch.object(m, 'prepare_tools') as prepare, patch.object(m.subprocess, 'run') as run:
        code = invoke(arguments)
        assert code == (0 if arguments == ['--help'] else 2)
        prepare.assert_not_called(); run.assert_not_called()
with patch.object(m, 'prepare_tools', return_value=Path('/fixture/python')) as prepare, patch.object(m.subprocess, 'run') as run:
    assert invoke(['--prepare-tools']) == 0
    prepare.assert_called_once(); run.assert_not_called()
with patch.object(m, 'prepare_tools', side_effect=subprocess.CalledProcessError(1, ['fixture-pip'])), patch.object(m.subprocess, 'run') as run:
    try: invoke(['--output', '/tmp/unused', '--publish'])
    except subprocess.CalledProcessError: pass
    else: raise AssertionError('Failed tool preparation reached release orchestration')
    run.assert_not_called()
for publish in [False, True]:
    arguments = ['--output', '/tmp/release folder with spaces', '--source-ref', 'fixture-ref', '--wait-seconds', '12']
    if publish: arguments += ['--publish', '--profile', 'Custom Profile']
    with patch.object(m, 'prepare_tools', return_value=Path('/fixture/python with spaces')), patch.object(m.subprocess, 'run', return_value=subprocess.CompletedProcess([], 7)) as run:
        assert invoke(arguments) == 7, 'Pipeline failure was hidden'
        command = run.call_args.args[0]
        assert command[0] == '/fixture/python with spaces'
        assert command[command.index('--output') + 1] == str(Path('/tmp/release folder with spaces').resolve())
        assert command[command.index('--profile') + 1] == ('Custom Profile' if publish else 'Perch')
        assert ('--publish' in command) == publish
        assert command[-2:] == ['--source-ref', 'fixture-ref']

for warm, broken in [(False, False), (True, False), (True, True)]:
    with tempfile.TemporaryDirectory() as directory:
        env = Path(directory) / 'tools'; calls = []; probes = []
        def fake_run(command, **options):
            calls.append(command)
            if '-c' in command:
                probes.append(command)
                return subprocess.CompletedProcess(command, 1 if (broken or not warm) and len(probes) == 1 else 0)
            return subprocess.CompletedProcess(command, 0)
        with patch.object(m, 'ENVIRONMENT', env), patch.dict(os.environ, {'PERCH_RELEASE_PYTHON': '/fixture/bootstrap'}), \
             patch.object(m, 'usable_python', side_effect=lambda value: str(value) == '/fixture/bootstrap' or warm), \
             patch.object(m.subprocess, 'run', side_effect=fake_run), redirect_stdout(io.StringIO()):
            result = m.prepare_tools()
        assert result == env / 'bin/python3'
        assert any('venv' in call for call in calls) == (not warm)
        assert any('install' in call for call in calls) == (broken or not warm)
with tempfile.TemporaryDirectory() as directory:
    with patch.object(m, 'ENVIRONMENT', Path(directory) / 'tools'), patch.object(m, 'usable_python', return_value=False), patch.object(m.subprocess, 'run') as run:
        try: m.prepare_tools()
        except SystemExit as error: assert 'Python 3.10+' in str(error)
        else: raise AssertionError('Missing Python did not stop bootstrap')
        run.assert_not_called()
print('PASS: help/invalid arguments have no effects; prepare-only cannot release; profile, spaced paths, retry arguments, publish opt-in and failure status preserved; environment reuse/repair and missing Python checked offline')
