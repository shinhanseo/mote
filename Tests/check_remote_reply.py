#!/usr/bin/env python3
"""Exercise real framing/routing against an isolated Codex IPC fixture, never real chats."""
import json,os,pathlib,socket,struct,subprocess,tempfile,threading
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='mote-reply-',dir='/tmp') as tmp:
 p=pathlib.Path(tmp);(p/'ipc').mkdir()
 (p/'main.swift').write_text('''import Foundation
let route=ReplyRoute(thread:"fixture",turn:"turn",requests:ProcessInfo.processInfo.environment["FIXTURE_TOOL"]=="1" ? ["question"]:["[\\\"request_user_input_async\\\",\\\"question\\\",0]"],expiresAt:Date().addingTimeInterval(ProcessInfo.processInfo.environment["EXPIRED"]=="1" ? -1:60))
do{try CodexReplyClient().deliver("fixture answer",route:route,id:"reply-fixture");print("delivered")}catch{print("rejected",error.localizedDescription)}''')
 subprocess.run(['swiftc',*[str(root/x) for x in ['Sources/Localizations.swift','Sources/PresentationPolicy.swift','Sources/LiveObserver.swift','Sources/RemoteReply.swift']],str(p/'main.swift'),'-o',str(p/'test')],check=True)
 for mode in ['active','completed','tool','stale','approval','multi','expired','disconnect']:
  server=socket.socket(socket.AF_UNIX);server.bind(str(p/'ipc/ipc.sock'));server.listen(1);sent=[];failures=[]
  def fixture():
   try:
    conn,_=server.accept();conn.settimeout(12)
    def recv():
     def exact(n):
      data=b''
      while len(data)<n:
       chunk=conn.recv(n-len(data))
       if not chunk:raise EOFError()
       data+=chunk
      return data
     return json.loads(exact(struct.unpack('<I',exact(4))[0]))
    def send(obj):
     b=json.dumps(obj).encode();conn.sendall(struct.pack('<I',len(b))+b)
    init=recv();send(dict(type='response',requestId=init['requestId'],result={'clientId':'fixture-client'}))
    follow=recv();assert follow['params']['conversationId']=='fixture'
    request={'id':'question','method':'item/tool/requestUserInput','params':{'questions':[{'id':'q'}]}}
    requests=[request] if mode in ['tool','multi'] else []
    if mode=='multi':request['params']['questions'].append({'id':'q2'})
    async_item={'id':'question','type':'agentMessage','questions':[{'title':'fixture'}]}
    state={'turns':[{'turnId':'other' if mode=='stale' else 'turn','status':'completed' if mode=='completed' else 'inProgress','turnStartedAtMs':1,'items':[] if requests or mode=='approval' else [async_item]}], 'requests':requests,'threadRuntimeStatus':{'type':'active','activeFlags':['waitingOnApproval' if mode=='approval' else 'waitingOnUserInput']}}
    send(dict(type='broadcast',method='thread-stream-state-changed',version=11,sourceClientId='fixture-owner',params={'hostId':'local','conversationId':'fixture','change':{'type':'snapshot','revision':1,'conversationState':state}}))
    try:
     mutation=recv();sent.append(mutation)
     if mode=='disconnect':conn.close();return
     send(dict(type='response',requestId=mutation['requestId'],resultType='success',result={'ok':True}))
    except EOFError:pass
    conn.close()
   except Exception as e:failures.append(e)
  t=threading.Thread(target=fixture);t.start()
  r=subprocess.run([str(p/'test')],env={**os.environ,'CODEX_HOME':tmp,'FIXTURE_TOOL':'1' if mode in ['tool','multi'] else '0','EXPIRED':'1' if mode=='expired' else '0'},capture_output=True,text=True,timeout=20);t.join();server.close();(p/'ipc/ipc.sock').unlink()
  assert not failures,failures
  if mode=='disconnect':assert len(sent)==1 and 'rejected' in r.stdout and '중복' in r.stdout
  elif mode in ['stale','approval','multi','expired']:assert not sent and 'rejected' in r.stdout,(mode,r.stdout)
  else:
   assert 'delivered' in r.stdout,(mode,r.stdout)
   m=sent[0];assert m['targetClientId']=='fixture-owner'
   expected={'active':'thread-follower-steer-turn','completed':'thread-follower-start-turn','tool':'thread-follower-submit-user-input'}[mode]
   assert m['method']==expected,(mode,m['method'])
   if mode=='tool':assert m['params']['response']['answers']['q']['answers']==['fixture answer']
   elif mode=='active':assert m['params']['input'][0]['text']=='fixture answer' and m['params']['clientUserMessageId']=='reply-fixture'
   else:assert m['params']['turnStart']['request']['input'][0]['text']=='fixture answer' and m['params']['turnStart']['context']=={'inheritThreadSettings':True}
  print('PASS:',mode,'reply routing / stale request guard')
