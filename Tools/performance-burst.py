"""Read-only XPC/native observer and bounded true burst. No real panic or grants."""
import subprocess,time,pathlib,json,threading,sys,re
repo=pathlib.Path(__file__).resolve().parents[1]
exe=repo/'build/Perch.app/Contents/MacOS/Perch'
probe=pathlib.Path('/private/tmp/perch-perf-counters')
subprocess.run(['xcrun','clang','-std=c11','-O2',str(repo/'Tools/perf-counters.c'),'-o',str(probe)],check=True)
observer=subprocess.Popen([str(exe),'--status-stream'],stdout=subprocess.PIPE,text=True)
latest={}; lock=threading.Lock()
def consume():
 for line in observer.stdout:
  try:
   value=json.loads(line)
   with lock:latest.clear();latest.update(value)
  except (ValueError,TypeError):pass
threading.Thread(target=consume,daemon=True).start()
def snapshot():
 with lock:return dict(latest)
def fresh(value):return time.time()-(value.get('timestamp',0)+978307200)<4

def counters(pids):
 rows=subprocess.check_output(['/bin/ps','-p',','.join(map(str,pids.values())),'-o','pid=,time=,rss='],text=True).splitlines()
 values={}
 for row in rows:
  pid,t,rss=row.split();values[int(pid)]={'cpu':sum(float(x)*60**j for j,x in enumerate(reversed(t.split(':')))),'rss':int(rss)*1024}
 native=json.loads(subprocess.check_output([str(probe)]+list(map(str,pids.values())),text=True))
 return {name:dict(values[pid],native=native.get(str(pid))) for name,pid in pids.items()}
try:
 deadline=time.monotonic()+15
 while time.monotonic()<deadline:
  s=snapshot();guardian=s.get('guardian',{});inputs=s.get('input',{})
  if fresh(guardian) and fresh(inputs) and guardian.get('eventCoverage')=='Process events active' and inputs.get('trusted'):break
  time.sleep(.05)
 else:raise RuntimeError('Fresh, healthy helper status not available; no burst started')
 pids={'monitor':guardian['watcherPID'],'input':inputs['pid'],'observer':observer.pid}
 job=subprocess.check_output(['/bin/launchctl','print','system/local.scott.perch.events'],text=True)
 match=re.search(r'^\s*pid = (\d+)\s*$',job,re.M)
 if not match:raise RuntimeError('Perch collector PID unavailable')
 pids['eslogger']=int(match.group(1))
 for row in subprocess.check_output(['/bin/ps','-axo','pid=,comm='],text=True).splitlines():
  fields=row.strip().split(None,1)
  if len(fields)==2 and fields[1]==str(exe) and int(fields[0])!=observer.pid:pids['menu']=int(fields[0])
 if 'menu' not in pids:raise RuntimeError('Menu app unavailable')
 duration=120 if '--long' in sys.argv else 30
 phases=[('no added workload',0)] if '--quiet-only' in sys.argv else [('no added workload',0),('50 execs/sec',50),('recovery',0)]
 results=[]
 for phase,rate in phases:
  before=counters(pids); start=time.monotonic(); history=[]; memory=[before]; last_sample=-1; last_memory=0
  maintenance_before=snapshot().get('guardian',{}).get('maintenance',{})
  for n in range(duration*(rate or 1)):
   if rate:subprocess.run(['/usr/bin/true'],check=True)
   now=time.monotonic()-start
   if int(now)!=last_sample:
    last_sample=int(now);s=snapshot();st=s.get('guardian',{});ins=s.get('input',{})
    healthy=fresh(st) and fresh(ins) and st.get('eventCoverage')=='Process events active' and st.get('watcherPID')==pids['monitor'] and ins.get('pid')==pids['input']
    history.append({'time':round(now,2),'healthy':healthy,'coverage':st.get('eventCoverage'),'error':st.get('error'),'events':st.get('processEventCount'),'inputTrusted':ins.get('trusted'),'inputActive':ins.get('active'),'diagnostics':st.get('eventDiagnostics')})
   if now-last_memory>=30:memory.append(counters(pids));last_memory=now
   time.sleep(max(0,start+(n+1)/(rate or 1)-time.monotonic()))
  after=counters(pids);elapsed=time.monotonic()-start;memory.append(after)
  usage={k:round((after[k]['cpu']-before[k]['cpu'])*100/elapsed,3) for k in pids}
  resources={}
  for k in pids:
   a=before[k]['native']; b=after[k]['native']
   if a and b and a['birth']==b['birth']:
    resources[k]={'footprintMiBStart':round(a['footprint']/2**20,3),'footprintMiBEnd':round(b['footprint']/2**20,3),'footprintMiBPeakSample':round(max(x[k]['native']['footprint'] for x in memory if x[k]['native'])/2**20,3),'interruptWakeupsPerSec':round((b['interruptWakeups']-a['interruptWakeups'])/elapsed,3),'packageWakeupsPerSec':round((b['packageWakeups']-a['packageWakeups'])/elapsed,3),'bytesWritten':b['bytesWritten']-a['bytesWritten'],'cpuIncludingCompletedUtilities':round((b['cpu']+b['childrenCPU']-a['cpu']-a['childrenCPU'])*100/elapsed,3)}
   else:resources[k]={'rssMiBStart':round(before[k]['rss']/2**20,3),'rssMiBEnd':round(after[k]['rss']/2**20,3),'nativeCounters':'unavailable'}
  maintenance_after=snapshot().get('guardian',{}).get('maintenance',{})
  result={'phase':phase,'seconds':round(elapsed,2),'CPU':usage,'total_without_observer':round(sum(v for k,v in usage.items() if k!='observer'),3),'resources':resources,'maintenance':{k:maintenance_after.get(k,0)-v for k,v in maintenance_before.items()},'health_samples':len(history),'degraded_details':[h for h in history if not h['healthy']],'first_events':history[0]['events'],'last_events':history[-1]['events'],'last':history[-1]}
  results.append(result);print(json.dumps(result),flush=True)
 destination='/private/tmp/perch-housekeeping-'+('long' if '--long' in sys.argv else 'short')+('-quiet' if '--quiet-only' in sys.argv else '')+'-results.json'
 pathlib.Path(destination).write_text(json.dumps(results,indent=2))
 print('Saved '+destination,flush=True)
finally:
 observer.terminate()
 try:observer.wait(timeout=3)
 except subprocess.TimeoutExpired:observer.kill();observer.wait()
