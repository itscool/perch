#!/usr/bin/env python3
"""Exercise the actual native launcher with a compile-time fixture destination.
No production helper, root execution, Endpoint Security or permission changes.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='perch-collector-test-'))
root.mkdir(parents=True, exist_ok=True)
repo = Path(__file__).resolve().parents[1]
directory = root / 'identity'; directory.mkdir(exist_ok=True); directory.chmod(0o755)
record = directory / 'collector.json'
child = root / 'collector-fixture'
(root / 'fixture.c').write_text(r'''
#include <sys/types.h>
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
    unsigned long long birth=(uint64_t)info.kp_proc.p_starttime.tv_sec*1000000+(uint64_t)info.kp_proc.p_starttime.tv_usec;
    printf("{\"pid\":%d,\"birth\":%llu}\n",getpid(),birth); fflush(stdout);
    struct timespec interval={0,200000000}; nanosleep(&interval,NULL);
    return 0;
}
''')
subprocess.run(['xcrun','clang','-std=c11','-Wall','-Wextra','-Werror',str(root/'fixture.c'),'-o',str(child)],check=True)

def compile_launcher(name, destination=directory, executable=child):
    target = root/name
    subprocess.run(['xcrun','clang','-std=c11','-O2','-Wall','-Wextra','-Werror',
        '-DPERCH_IDENTITY_DIRECTORY='+json.dumps(str(destination)),
        '-DPERCH_COLLECTOR_EXECUTABLE='+json.dumps(str(executable)),
        '-DPERCH_LAUNCHER_OWNER_UID='+str(os.getuid()),
        str(repo/'Sources/PerchEventLauncher.c'),'-o',str(target)],check=True)
    return target
launcher=compile_launcher('launcher-fixture')
def run(expect_record=True, executable=launcher):
    env=dict(os.environ, PERCH_FIXTURE_SECRET='must-not-reach-child')
    with subprocess.Popen([str(executable)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env) as process:
        actual=json.loads(process.stdout.readline())
        assert actual['pid']==process.pid, 'exec created an extra collector process'
        if expect_record:
            observed=json.loads(record.read_text())
            assert observed['pid']==actual['pid'] and observed['birth']==actual['birth'] and observed['schema']==1
            assert record.stat().st_mode & 0o777 == 0o644
        output,error=process.communicate(timeout=5)
        assert process.returncode==0, error
        return actual,error
first,_=run(); second,_=run()
assert first!=second and json.loads(record.read_text())['pid']==second['pid'], 'Restart retained an old identity'
assert subprocess.run([str(launcher),'unexpected'],capture_output=True).returncode==64
outside=root/'outside'; outside.write_text('untouched')
record.unlink(); record.symlink_to(outside)
run(); assert outside.read_text()=='untouched' and not record.is_symlink()
record.unlink(); directory.chmod(0o777)
_,error=run(False); assert not record.exists() and 'identity unavailable' in error
# Metadata failure must not disable event collection.
directory.chmod(0o755)
link=root/'directory-link'; link.symlink_to(directory, target_is_directory=True)
linked=compile_launcher('linked-launcher',destination=link)
_,error=run(False,linked); assert not record.exists() and 'identity unavailable' in error
missing=compile_launcher('failed-exec-launcher',executable=root/'missing-collector')
assert subprocess.run([str(missing)],capture_output=True).returncode==71
# The failed launcher exits; its stale record is rejected by reader liveness checks.
assert json.loads(record.read_text())['pid']>1
subprocess.run(['/bin/sh','-n',str(repo/'Tools/install-event-collector.sh')],check=True)
print('PASS: same PID and birth across exec, restart replacement, fixed arguments/environment, atomic symlink replacement, unsafe directory refusal, continued collection after metadata failure, failed exec and installer syntax; fixture processes only')
