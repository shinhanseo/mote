import sqlite3,tempfile,subprocess,os,time,pathlib
os.environ["MOTE_LANGUAGE"]="ko"
binary=pathlib.Path(__file__).resolve().parents[1]/'Mote.app/Contents/MacOS/Mote'
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
