from __future__ import annotations
import ipaddress,json,os,queue,secrets,socket,subprocess,sys,threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT=Path(r"D:\Mira")
ENTRY=ROOT/"brain"/"core"/"main.py"
LOGS=ROOT/"logs"
LOG_FILE=LOGS/"mira_app_server.log"
PORT=8765
PROMPT="You (Enter to send): "
TOKEN=secrets.token_urlsafe(20)

def local_ips():
    found=set()
    try:
        for row in socket.getaddrinfo(socket.gethostname(),None,socket.AF_INET):
            ip=ipaddress.ip_address(row[4][0])
            if ip.is_private and not ip.is_loopback and not ip.is_link_local: found.add(str(ip))
    except OSError: pass
    return sorted(found)

class Backend:
    def __init__(self):
        self.lock=threading.RLock(); self.proc=None; self.events=queue.Queue()
        self.state="starting"; self.error=""
    def log(self,s):
        if not s.strip(): return
        try:
            LOGS.mkdir(parents=True,exist_ok=True)
            with LOG_FILE.open("a",encoding="utf-8") as f:
                f.write("\n["+datetime.now().isoformat(timespec="seconds")+"]\n"+s+"\n")
        except OSError: pass
    def reader(self,proc,events):
        buf=""
        try:
            while True:
                ch=proc.stdout.read(1)
                if not ch: break
                buf+=ch
                if buf.endswith(PROMPT):
                    events.put(("prompt",buf[:-len(PROMPT)])); buf=""
                elif len(buf)>250000: buf=buf[-50000:]
        except Exception as e: events.put(("error",str(e)))
        finally: events.put(("eof",buf))
    def start(self):
        with self.lock:
            if self.proc is not None and self.proc.poll() is None and self.state=="ready": return
            if not ENTRY.is_file():
                self.state,self.error="error","Mira core not found at "+str(ENTRY)
                raise RuntimeError(self.error)
            self.state,self.error="starting",""
            self.events=queue.Queue()
            env=os.environ.copy(); env["PYTHONUTF8"]="1"; env["PYTHONIOENCODING"]="utf-8"
            self.proc=subprocess.Popen([sys.executable,"-u",str(ENTRY)],cwd=str(ROOT),stdin=subprocess.PIPE,
              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding="utf-8",errors="replace",bufsize=1,env=env)
            proc,events=self.proc,self.events
            threading.Thread(target=self.reader,args=(proc,events),daemon=True).start()
            try: kind,out=events.get(timeout=240)
            except queue.Empty:
                self.state,self.error="error","Mira startup exceeded 240 seconds."
                raise RuntimeError(self.error)
            self.log(out)
            if kind!="prompt":
                self.state,self.error="error","Mira did not reach its chat prompt: "+out[-1000:]
                raise RuntimeError(self.error)
            self.state="ready"
    @staticmethod
    def extract(out):
        for marker in ("Mira [conversation]:","Mira [autonomous]:"):
            i=out.rfind(marker)
            if i>=0:
                value=out[i+len(marker):].strip()
                if marker.endswith("[autonomous]:") and " result=" in value:
                    try:
                        import ast
                        x=ast.literal_eval(value.split(" result=",1)[1].strip())
                        if isinstance(x,str): return x
                    except (ValueError,SyntaxError): pass
                return value
        i=out.rfind("Mira error:")
        return out[i:].strip() if i>=0 else out.strip()[-8000:]
    def chat(self,msg):
        with self.lock:
            if self.proc is None or self.proc.poll() is not None or self.state!="ready": self.start()
            self.state="thinking"
            try:
                self.proc.stdin.write(" ".join(msg.splitlines()).strip()+"\n"); self.proc.stdin.flush()
                kind,out=self.events.get(timeout=300)
            except queue.Empty:
                self.state,self.error="error","Mira reply timed out."
                raise RuntimeError(self.error)
            self.log(out)
            if kind!="prompt":
                self.state,self.error="error","Mira stopped before replying."
                raise RuntimeError(self.error)
            answer=self.extract(out) or "Mira က အဖြေပြန်မပေးနိုင်သေးပါ။"
            self.state,self.error="ready",""
            return answer
    def reset(self):
        with self.lock:
            if self.proc is not None and self.proc.poll() is None:
                self.proc.stdin.write("exit\n"); self.proc.stdin.flush(); self.proc.wait(timeout=60)
            self.proc=None; self.events=queue.Queue(); self.start()
    def shutdown(self):
        with self.lock:
            if self.proc is not None and self.proc.poll() is None:
                try: self.proc.stdin.write("exit\n"); self.proc.stdin.flush(); self.proc.wait(timeout=60)
                except Exception as e: self.log("Shutdown: "+str(e))

backend=Backend()

class Handler(BaseHTTPRequestHandler):
    server_version="MiraNativeBridge/1.0"
    def log_message(self,fmt,*args): print("API: "+(fmt%args),flush=True)
    def respond(self,code,obj):
        body=json.dumps(obj,ensure_ascii=False).encode("utf-8")
        self.send_response(code); self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length",str(len(body))); self.send_header("Cache-Control","no-store")
        self.send_header("X-Content-Type-Options","nosniff"); self.end_headers(); self.wfile.write(body)
    def auth(self):
        if secrets.compare_digest(self.headers.get("X-Mira-Token",""),TOKEN): return True
        self.respond(401,{"error":"Access Key မှားနေသည်။"}); return False
    def do_GET(self):
        if urlsplit(self.path).path!="/api/status": self.respond(404,{"error":"Not found"}); return
        if not self.auth(): return
        if backend.proc is not None and backend.proc.poll() is not None and backend.state in ("ready","thinking"):
            backend.state,backend.error="disconnected","Mira process stopped."
        self.respond(200,{"state":backend.state,"error":backend.error})
    def do_POST(self):
        path=urlsplit(self.path).path
        if path not in ("/api/chat","/api/reset"): self.respond(404,{"error":"Not found"}); return
        if not self.auth(): return
        try: size=int(self.headers.get("Content-Length","0"))
        except ValueError: size=0
        if size<1 or size>20000: self.respond(413,{"error":"Request size invalid"}); return
        try: body=json.loads(self.rfile.read(size).decode("utf-8"))
        except (ValueError,UnicodeError): self.respond(400,{"error":"Invalid JSON"}); return
        if path=="/api/reset":
            try: backend.reset(); self.respond(200,{"state":"ready"})
            except Exception as e:
                backend.state,backend.error="error",str(e); self.respond(503,{"state":backend.state,"error":backend.error})
            return
        msg=body.get("message") if isinstance(body,dict) else None
        if not isinstance(msg,str) or not msg.strip() or len(msg)>8000:
            self.respond(400,{"error":"Message is empty or too long"}); return
        try: self.respond(200,{"reply":backend.chat(msg),"state":backend.state})
        except Exception as e:
            backend.state,backend.error="error",str(e); self.respond(503,{"state":backend.state,"error":backend.error})

def main():
    if not ENTRY.is_file(): print("ERROR: Mira core not found at "+str(ENTRY),flush=True); return 2
    LOGS.mkdir(parents=True,exist_ok=True); ips=local_ips()
    server=ThreadingHTTPServer(("0.0.0.0",PORT),Handler)
    print("\n=== MIRA NATIVE APP SERVER ===",flush=True)
    print("COMPUTER_URL=http://127.0.0.1:"+str(PORT),flush=True)
    for ip in ips: print("PHONE_URL=http://"+ip+":"+str(PORT),flush=True)
    if not ips: print("PHONE_URL=Not detected; check ipconfig.",flush=True)
    print("MIRA_ACCESS_KEY="+TOKEN,flush=True)
    print("Keep this window open; use trusted private Wi-Fi only.",flush=True)
    def warm():
        try: backend.start(); print("MIRA_BACKEND_READY=True",flush=True)
        except Exception as e:
            backend.state,backend.error="error",str(e); print("MIRA_BACKEND_START_ERROR="+str(e),flush=True)
    threading.Thread(target=warm,daemon=True).start()
    try: server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt: print("\nStopping Mira server...",flush=True)
    finally:
        server.server_close(); backend.shutdown(); print("MIRA_SERVER_STOPPED=True",flush=True)
    return 0
if __name__=="__main__": raise SystemExit(main())
