import sqlite3,tempfile,subprocess,os,time,pathlib
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
