#!/usr/bin/env python3
"""Exercise the actual native launcher with a compile-time fixture destination,
and the installer's event-pipe repair and job definition in fixture directories.
No production helper, root execution, launchd, Endpoint Security or permission changes.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import select
import stat
import sys; sys.path.insert(0, str(Path(__file__).resolve().parent))
from perch_sources import source as perch_source
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='perch-collector-test-'))
root.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parents[1]
directory = root / 'identity'; directory.mkdir(exist_ok=True); directory.chmod(0o755)
record = directory / 'collector.json'
fifo = directory / 'events.pipe'
marker = root / 'collector-ran.json'
child = root / 'collector-fixture'
# The stand-in collector records that it ran and what its stdout is, in a marker
# file and on stdout itself.
(root / 'fixture.c').write_text(r'''
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
int main(int argc, char **argv) {
    if (argc != 4 || strcmp(argv[1],"fork") || strcmp(argv[2],"exec") || strcmp(argv[3],"exit") || getenv("PERCH_FIXTURE_SECRET")) return 2;
    struct kinfo_proc info = {0}; size_t size=sizeof(info);
    int mib[]={CTL_KERN,KERN_PROC,KERN_PROC_PID,getpid()};
    if (sysctl(mib,4,&info,&size,NULL,0)) return 3;
    struct stat out;
    if (fstat(STDOUT_FILENO,&out)) return 4;
    unsigned long long birth=(uint64_t)info.kp_proc.p_starttime.tv_sec*1000000+(uint64_t)info.kp_proc.p_starttime.tv_usec;
    char line[256];
    snprintf(line,sizeof(line),"{\"pid\":%d,\"birth\":%llu,\"stdoutFIFO\":%d,\"stdoutDevice\":%llu,\"stdoutInode\":%llu,\"descriptor3\":%d}\n",
        getpid(),birth,S_ISFIFO(out.st_mode)?1:0,(unsigned long long)out.st_dev,(unsigned long long)out.st_ino,fcntl(3,F_GETFD)!=-1);
    FILE *ran=fopen(MARKER,"w"); if (!ran) return 5; fputs(line,ran); fclose(ran);
    fputs(line,stdout); fflush(stdout);
    struct timespec interval={0,200000000}; nanosleep(&interval,NULL);
    return 0;
}
''')
subprocess.run(['xcrun','clang','-std=c11','-Wall','-Wextra','-Werror','-include','fcntl.h','-DMARKER='+json.dumps(str(marker)),str(root/'fixture.c'),'-o',str(child)],check=True)

def compile_launcher(name, destination=directory, executable=child):
    target = root/name
    subprocess.run(['xcrun','clang','-std=c11','-O2','-Wall','-Wextra','-Werror',
        '-DPERCH_IDENTITY_DIRECTORY='+json.dumps(str(destination)),
        '-DPERCH_COLLECTOR_EXECUTABLE='+json.dumps(str(executable)),
        '-DPERCH_LAUNCHER_OWNER_UID='+str(os.getuid()),
        str(perch_source('PerchEventLauncher.c')),'-o',str(target)],check=True)
    return target
launcher=compile_launcher('launcher-fixture')
environment=dict(os.environ, PERCH_FIXTURE_SECRET='must-not-reach-child')
def start(executable=launcher):
    return subprocess.Popen([str(executable)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True,env=environment)
def read_line(reader, process):
    # A FIFO with no writer reads as empty; wait for the collector's one line.
    data, deadline = b'', time.monotonic()+5
    while not data.endswith(b'\n'):
        assert time.monotonic() < deadline and process.poll() is None, 'collector wrote nothing to its event pipe'
        select.select([reader],[],[],0.05)
        try: chunk = os.read(reader, 4096)
        except BlockingIOError: chunk = b''
        if not chunk: time.sleep(0.01)
        data += chunk
    return json.loads(data)
def make_pipe(mode=0o600):
    if fifo.is_symlink() or fifo.exists(): fifo.unlink()
    os.mkfifo(fifo, 0o600); fifo.chmod(mode)
def run(expect_record=True, executable=launcher):
    make_pipe(); marker.unlink(missing_ok=True)
    with start(executable) as process:
        reader=os.open(fifo, os.O_RDONLY|os.O_NONBLOCK)
        try: actual=read_line(reader, process)
        finally: os.close(reader)
        assert actual['pid']==process.pid, 'exec created an extra collector process'
        piped=os.stat(fifo)
        assert actual['stdoutFIFO']==1 and (actual['stdoutDevice'],actual['stdoutInode'])==(piped.st_dev,piped.st_ino), 'collector stdout is not events.pipe'
        assert actual['descriptor3']==0, 'the launcher leaked its pipe descriptor into the collector'
        if expect_record:
            observed=json.loads(record.read_text())
            assert observed['pid']==actual['pid'] and observed['birth']==actual['birth'] and observed['schema']==1
            assert record.stat().st_mode & 0o777 == 0o644
        _,error=process.communicate(timeout=5)
        assert process.returncode==0, error
        return actual,error
def refused(expect, reader=False, executable=launcher):
    marker.unlink(missing_ok=True)
    held=os.open(fifo, os.O_RDONLY|os.O_NONBLOCK) if reader else None
    try: result=subprocess.run([str(executable)],stdin=subprocess.DEVNULL,capture_output=True,text=True,env=environment,timeout=5)
    finally:
        if held is not None: os.close(held)
    assert result.returncode==78, (expect, result.returncode, result.stderr)
    assert not marker.exists(), 'the collector started despite a refused event pipe: '+expect
    assert result.stderr.count('\n')==1 and expect in result.stderr and str(fifo) in result.stderr, result.stderr
first,_=run(); second,_=run()
assert first!=second and json.loads(record.read_text())['pid']==second['pid'], 'Restart retained an old identity'
assert subprocess.run([str(launcher),'unexpected'],capture_output=True).returncode==64

# Before Perch's reader attaches the launcher waits in its open, as launchd's
# StandardOutPath open did: it neither fails nor starts the collector.
make_pipe(); marker.unlink(missing_ok=True)
with start() as process:
    time.sleep(0.5)
    assert process.poll() is None and not marker.exists(), 'the launcher did not wait for a reader'
    reader=os.open(fifo, os.O_RDONLY|os.O_NONBLOCK)
    try: assert read_line(reader, process)['pid']==process.pid
    finally: os.close(reader)
    process.communicate(timeout=5); assert process.returncode==0

# (a) An ordinary file at events.pipe is refused and left exactly as it was.
fifo.unlink(); fifo.write_bytes(b'existing bytes\n'); os.utime(fifo,(1_000_000_000,1_000_000_000)); before=os.stat(fifo)
refused('is not a named pipe')
after=os.stat(fifo)
assert fifo.read_bytes()==b'existing bytes\n' and (after.st_ino,after.st_size,after.st_mtime,after.st_mode)==(before.st_ino,before.st_size,before.st_mtime,before.st_mode), 'the launcher changed an ordinary file'
# (b) A missing events.pipe is refused and nothing is created.
fifo.unlink(); refused('is missing'); assert not os.path.lexists(fifo), 'the launcher created events.pipe'
# (c) A symlink is refused, to a FIFO or to a file, and its target is untouched.
outside_pipe=root/'outside.pipe'; os.mkfifo(outside_pipe,0o600)
fifo.symlink_to(outside_pipe); refused('is a symbolic link'); fifo.unlink()
outside=root/'outside'; outside.write_text('untouched')
fifo.symlink_to(outside); refused('is a symbolic link'); assert outside.read_text()=='untouched' and fifo.is_symlink()
# A FIFO with the wrong mode, or a second link, is refused once a reader attaches.
make_pipe(0o644); refused('is not mode 0600', reader=True)
make_pipe(); extra=root/'second-link.pipe'; os.link(fifo, extra)
refused('has more than one link', reader=True); extra.unlink()
# (d) and every run() above: a FIFO with a reader becomes the collector's stdout.

outside.write_text('untouched')
record.unlink(missing_ok=True); record.symlink_to(outside)
run(); assert outside.read_text()=='untouched' and not record.is_symlink()
record.unlink(); directory.chmod(0o777)
_,error=run(False); assert not record.exists() and 'identity unavailable' in error
# Metadata failure must not disable event collection.
directory.chmod(0o755)
link=root/'directory-link'; link.symlink_to(directory, target_is_directory=True)
linked=compile_launcher('linked-launcher',destination=link)
_,error=run(False,linked); assert not record.exists() and 'identity unavailable' in error
missing=compile_launcher('failed-exec-launcher',executable=root/'missing-collector')
make_pipe(); held=os.open(fifo, os.O_RDONLY|os.O_NONBLOCK)
try: assert subprocess.run([str(missing)],capture_output=True).returncode==71
finally: os.close(held)
# The failed launcher exits; its stale record is rejected by reader liveness checks.
assert json.loads(record.read_text())['pid']>1

installer=(repo/'Tools/install-event-collector.sh').read_text()
subprocess.run(['/bin/sh','-n',str(repo/'Tools/install-event-collector.sh')],check=True)
# The job launchd loads names no StandardOutPath, so launchd never creates that path.
job=plistlib.loads(re.search(r"<<PLIST\n(.*?)\nPLIST\n", installer, re.S).group(1).encode())
assert 'StandardOutPath' not in job and job['StandardErrorPath']=='/dev/null', 'the collector job lets launchd create its output path'
assert job['ProgramArguments']==['/Library/Application Support/Perch Events/PerchEventLauncher'] and job['ProcessType']=='Interactive'
# The installer's pipe repair, run as written against a fixture directory.
function=re.search(r"^perch_prepare_pipe\(\) \{\n.*?^\}\n", installer, re.S | re.M).group(0)
repair=root/'repair'; repair.mkdir(exist_ok=True)
def prepare():
    return subprocess.run(['/bin/sh','-eu','-c',function+'perch_prepare_pipe "$1" "$2"','prepare',str(repair),str(os.getuid())],capture_output=True,text=True)
def is_pipe(path):
    info=os.lstat(path)
    return stat.S_ISFIFO(info.st_mode) and info.st_mode & 0o7777 == 0o600 and info.st_uid == os.getuid()
pipe=repair/'events.pipe'
result=prepare(); assert result.returncode==0 and is_pipe(pipe) and result.stdout=='', result
kept=os.stat(pipe).st_ino; pipe.chmod(0o644)
result=prepare(); assert result.returncode==0 and is_pipe(pipe) and os.stat(pipe).st_ino==kept and result.stdout=='', 'repair replaced an existing FIFO'
pipe.unlink(); pipe.write_bytes(b'x'*4096)
result=prepare(); assert result.returncode==0 and is_pipe(pipe), result
assert 'Replacing the ordinary file' in result.stdout and str(pipe) in result.stdout, 'repair did not say it replaced the file'
pipe.unlink(); pipe.symlink_to(outside)
result=prepare(); assert result.returncode==2 and pipe.is_symlink() and outside.read_text()=='untouched', 'repair followed or replaced a symlink'
pipe.unlink(); pipe.mkdir()
result=prepare(); assert result.returncode==2 and pipe.is_dir(), 'repair replaced a directory'
print('PASS: same PID and birth across exec, restart replacement, fixed arguments/environment, waiting for a reader, '
      'events.pipe as stdout with no leaked descriptor, refusal of an ordinary file (unchanged), a missing path (nothing created), '
      'symlinks, wrong mode and extra links, atomic symlink replacement, unsafe directory refusal, continued collection after '
      'metadata failure, failed exec, installer syntax, no StandardOutPath, and pipe repair (create, keep, replace a file, refuse '
      'a symlink or directory); fixture processes only')
