import sqlite3,tempfile,subprocess,os,time,pathlib
os.environ["MOTE_LANGUAGE"]="ko"
binary=pathlib.Path(os.environ.get('MOTE_TEST_BINARY',str(pathlib.Path(__file__).resolve().parents[1]/'Mote.app/Contents/MacOS/Mote')))
with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite');c.execute('CREATE TABLE threads(id,title,cwd,archived,agent_path,updated_at)')
 d=sqlite3.connect(h+'/thread_history_1.sqlite');d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)')
 for i,status in enumerate(['inProgress','completed','failed','interrupted','inProgress']):
  key=str(i);c.execute('INSERT INTO threads VALUES(?,?,?,0,NULL,?)',(key,'fixture','/work/project',i));d.execute('INSERT INTO thread_turns VALUES(?,?,?,?,?)',(key,'turn',status,time.time()-(25000 if i==4 else 5),1))
 c.commit();d.commit()
 out=subprocess.check_output([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True)
 for expected in ['0 inProgress','1 completed','2 failed','3 interrupted','4 unknown']:assert expected in out,out
 print('PASS: running, complete, failure, interruption, stale-running -> unknown')
 d.execute('INSERT INTO thread_turns VALUES(?,?,?,?,?)',('0','turn2','completed',time.time(),2));d.commit()
 out=subprocess.check_output([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert '0 completed' in out
 print('PASS: newest turn wins')
# A desktop read receipt must override a stale live snapshot, but only for its published turn.
with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite')
 c.executescript('CREATE TABLE threads(id,title,cwd,archived,agent_path,updated_at); CREATE TABLE thread_read_receipts(thread_id,first_unread_turn,last_published_turn);')
 c.execute('INSERT INTO threads VALUES(?,?,?,0,NULL,1)',('receipt','fixture','/work/project'))
 c.execute('INSERT INTO thread_read_receipts VALUES(?,?,?)',('receipt','turn','turn'));c.commit()
 d=sqlite3.connect(h+'/thread_history_1.sqlite');d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)')
 d.execute('INSERT INTO thread_turns VALUES(?,?,?,?,1)',('receipt','turn','completed',time.time()));d.commit()
 def diagnose():return subprocess.check_output([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert 'unread=true' in diagnose()
 c.execute('UPDATE thread_read_receipts SET first_unread_turn=NULL');c.commit()
 assert 'unread=false' in diagnose()
 c.execute("UPDATE thread_read_receipts SET last_published_turn='older-turn'");c.commit()
 assert 'unread=unknown' in diagnose()
 print('PASS: unread -> desktop read clears receipt; unrelated turn receipt ignored')
with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite');c.execute('CREATE TABLE threads(id,title,cwd,archived,agent_path,updated_at,name)')
 c.execute('INSERT INTO threads VALUES(?,?,?,0,NULL,1,?)',('named','RAW PROMPT MUST NOT DISPLAY','/work/project','사용자가 정한 제목'));c.commit()
 d=sqlite3.connect(h+'/thread_history_1.sqlite');d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)');d.commit()
 # Diagnostic titles are opt-in and used here only with fixtures.
 out=subprocess.check_output([str(binary),'--diagnose','--titles'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert '사용자가 정한 제목' in out and 'RAW PROMPT' not in out
 c.execute('UPDATE threads SET name=NULL');c.commit()
 out=subprocess.check_output([str(binary),'--diagnose','--titles'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert '제목 없는 대화' in out and 'RAW PROMPT' not in out
 print('PASS: conversation name preferred; unnamed conversations never expose first prompt')
with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite');c.execute('CREATE TABLE threads(id,title,cwd,archived,agent_path,updated_at)')
 d=sqlite3.connect(h+'/thread_history_1.sqlite');d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)')
 for i in range(30):
  c.execute('INSERT INTO threads VALUES(?,?,?,0,NULL,?)',(str(i),'fixture','/work/project',30-i))
  d.execute('INSERT INTO thread_turns VALUES(?,?,?,?,1)',(str(i),'turn','inProgress' if i==29 else 'completed',time.time()))
 c.commit();d.commit()
 out=subprocess.check_output([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert '29 inProgress' in out and 'Detected 21 local tasks' in out,out
 print('PASS: active task outside recent 20 stays monitored')

# Unread completed chats outside the recent window must still be visible.
with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite');c.executescript('CREATE TABLE threads(id,title,cwd,archived,agent_path,updated_at); CREATE TABLE thread_read_receipts(thread_id,first_unread_turn,last_published_turn);')
 d=sqlite3.connect(h+'/thread_history_1.sqlite');d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)')
 for i in range(25):
  c.execute('INSERT INTO threads VALUES(?,?,?,0,NULL,?)',(str(i),'fixture','/work/project',25-i))
  d.execute('INSERT INTO thread_turns VALUES(?,?,?,?,1)',(str(i),'turn','completed',time.time()))
 c.execute('INSERT INTO thread_read_receipts VALUES(?,?,?)',('24','turn','turn'));c.commit();d.commit()
 out=subprocess.check_output([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert '24 completed unread=true' in out,out
 print('PASS: unread conversation outside recent 20 stays monitored')

# Older/different desktop schemas may omit optional columns and rotate history versions.
with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_7.sqlite');c.execute('CREATE TABLE threads(id,name)')
 c.execute('INSERT INTO threads VALUES(?,?)',('portable','Portable title'));c.commit()
 d=sqlite3.connect(h+'/thread_history_2.sqlite');d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,rollout_ordinal)')
 d.execute('INSERT INTO thread_turns VALUES(?,?,?,?)',('portable','t','inProgress',1));d.commit()
 out=subprocess.check_output([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True)
 assert 'portable inProgress' in out,out
 print('PASS: optional thread columns, missing start time and rotated history version')

with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite');c.execute('CREATE TABLE threads(id)');c.commit()
 out=subprocess.run([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True,capture_output=True)
 assert out.returncode==0 and 'Detected 0 local tasks' in out.stdout,out
 print('PASS: missing status database preserves available conversation list')

with tempfile.TemporaryDirectory() as h:
 c=sqlite3.connect(h+'/state_5.sqlite');c.execute('CREATE TABLE threads(unexpected)');c.commit()
 out=subprocess.run([str(binary),'--diagnose'],env={**os.environ,'CODEX_HOME':h},text=True,capture_output=True)
 assert out.returncode==1 and 'threads.id' in out.stderr,out
 print('PASS: unsupported required schema identifies database and field')

# Reproduce schema-open failures independently from thread column compatibility.
for kind in ['not-a-database','corrupt','unsupported-collation','busy']:
 with tempfile.TemporaryDirectory() as h:
  c=sqlite3.connect(h+'/state_5.sqlite');c.execute('CREATE TABLE threads(id,name,cwd)');c.execute('INSERT INTO threads VALUES(?,?,?)',('survivor','PRIVATE TITLE','/private/project'));c.commit()
  path=h+'/thread_history_1.sqlite'
  locker=None
  if kind=='not-a-database':pathlib.Path(path).write_bytes(b'not a SQLite file; PRIVATE SECRET')
  elif kind=='corrupt':
   d=sqlite3.connect(path);d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)');d.commit();d.close()
   data=bytearray(pathlib.Path(path).read_bytes());data[100]=0;pathlib.Path(path).write_bytes(data)
  else:
   d=sqlite3.connect(path)
   if kind=='unsupported-collation':
    d.create_collation('fixture_collation',lambda a,b:(a>b)-(a<b));d.execute('CREATE TABLE thread_turns(thread_id TEXT PRIMARY KEY COLLATE fixture_collation,turn_id,status,started_at,rollout_ordinal)')
   else:d.execute('CREATE TABLE thread_turns(thread_id,turn_id,status,started_at,rollout_ordinal)')
   d.commit();d.close()
   if kind=='busy':locker=sqlite3.connect(path);locker.execute('BEGIN EXCLUSIVE')
  env={**os.environ,'CODEX_HOME':h}
  out=subprocess.check_output([str(binary),'--diagnose'],env=env,text=True)
  assert 'survivor unknown' in out and 'Detected 1 local tasks' in out,out
  diagnostic=subprocess.check_output([str(binary),'--schema'],env=env,text=True)
  assert 'SQLite ' in diagnostic and kind in diagnostic,diagnostic
  assert all(secret not in diagnostic for secret in ['PRIVATE TITLE','PRIVATE SECRET','survivor','/private/project',h]),diagnostic
  if locker:locker.rollback();locker.close()
  print('PASS: '+kind+' retains list, reports safe SQLite cause, never invents completion')
