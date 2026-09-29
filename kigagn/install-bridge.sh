#!/data/data/com.termux/files/usr/bin/sh
set -eu

D="$HOME/kigagn-server"
B="$D/engine/update-bridge.cjs"
BOOT="$HOME/.termux/boot/start-server"

mkdir -p "$D/engine" "$D/logs" "$D/backups" "$HOME/.termux/boot"

cat > "$B" <<'EOF'
const http=require('http');
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');

const ROOT=path.resolve(process.env.HOME,'kigagn-server');
const PORT=8091;
const MANIFEST='https://raw.githubusercontent.com/woofoner/locautomoto-web/kigagn-updates/kigagn/manifest.json';

function json(res,code,obj){
  res.writeHead(code,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
  res.end(JSON.stringify(obj));
}
function safePath(rel){
  const p=path.resolve(ROOT,String(rel||''));
  if(!(p===ROOT||p.startsWith(ROOT+path.sep))) throw new Error('Chemin interdit');
  return p;
}
function sha256(s){return crypto.createHash('sha256').update(s).digest('hex');}
async function fetchText(url){
  const r=await fetch(url,{headers:{'Cache-Control':'no-cache'}});
  if(!r.ok) throw new Error('HTTP '+r.status+' '+url);
  return await r.text();
}
function localVersionCode(){
  try{
    const s=fs.readFileSync(path.join(ROOT,'public/index.html'),'utf8');
    let m=s.match(/KIGAGN_APP_VERSION_CODE\s*=\s*(\d+)/);
    if(m)return Number(m[1])||0;
    m=s.match(/code\s+(\d+)/i);
    return m?Number(m[1])||0:0;
  }catch{return 0;}
}
async function loadManifest(){
  return JSON.parse(await fetchText(MANIFEST+'?t='+Date.now()));
}
function backupFile(src,stamp){
  if(!fs.existsSync(src))return;
  const rel=path.relative(ROOT,src);
  const dst=path.join(ROOT,'backups','update-'+stamp,rel);
  fs.mkdirSync(path.dirname(dst),{recursive:true});
  fs.copyFileSync(src,dst);
}
async function applyBundle(manifest){
  if(!manifest.bundle) throw new Error('Bundle absent');
  const base=MANIFEST.replace(/\/manifest\.json(?:\?.*)?$/,'/');
  const url=new URL(manifest.bundle,base).href;
  const bundle=JSON.parse(await fetchText(url+'?t='+Date.now()));
  const ops=Array.isArray(bundle.operations)?bundle.operations:[];
  const stamp=new Date().toISOString().replace(/[:.]/g,'-');

  for(const op of ops){
    const dest=safePath(op.path);
    backupFile(dest,stamp);
    fs.mkdirSync(path.dirname(dest),{recursive:true});

    if(op.type==='replace'){
      let s=fs.readFileSync(dest,'utf8');
      const old=String(op.old??'');
      const neu=String(op.new??'');
      if(!old||!s.includes(old)) throw new Error('Texte cible introuvable: '+op.path);
      const count=Number(op.count||1);
      for(let i=0;i<count;i++){
        const at=s.indexOf(old);
        if(at<0)break;
        s=s.slice(0,at)+neu+s.slice(at+old.length);
      }
      const tmp=dest+'.update-tmp';
      fs.writeFileSync(tmp,s);
      fs.renameSync(tmp,dest);
    } else if(op.type==='append'){
      fs.appendFileSync(dest,String(op.content??''));
    } else if(op.type==='write'){
      let content='';
      if(op.url){
        content=await fetchText(new URL(op.url,base).href+'?t='+Date.now());
      }else{
        content=String(op.content??'');
      }
      if(op.sha256 && sha256(content)!==String(op.sha256).toLowerCase()){
        throw new Error('SHA256 invalide: '+op.path);
      }
      const tmp=dest+'.update-tmp';
      fs.writeFileSync(tmp,content);
      fs.renameSync(tmp,dest);
    } else {
      throw new Error('Opération inconnue');
    }
  }
  return {operations:ops.length,backup:'backups/update-'+stamp};
}

const server=http.createServer(async(req,res)=>{
  try{
    if(req.method==='GET'&&req.url.startsWith('/health')){
      return json(res,200,{ok:true,bridge:'KIGAGN-S20-BRIDGE-1',port:PORT,source:'GitHub',hatchable:false});
    }
    if(req.method==='GET'&&req.url.startsWith('/check')){
      const m=await loadManifest();
      const local=localVersionCode();
      return json(res,200,{ok:true,localVersionCode:local,remoteVersion:m.appVersion,remoteVersionCode:m.versionCode,updateAvailable:Number(m.versionCode)>local});
    }
    if(req.method==='POST'&&req.url.startsWith('/update')){
      const m=await loadManifest();
      const local=localVersionCode();
      if(Number(m.versionCode)<=local){
        return json(res,200,{ok:true,updated:false,localVersionCode:local,message:'Déjà à jour'});
      }
      const result=await applyBundle(m);
      return json(res,200,{ok:true,updated:true,from:local,to:Number(m.versionCode),version:m.appVersion,...result});
    }
    return json(res,404,{ok:false,error:'not_found'});
  }catch(e){
    return json(res,500,{ok:false,error:e.message});
  }
});

server.listen(PORT,'127.0.0.1',()=>console.log('KiGagn update bridge listening on 127.0.0.1:'+PORT));
EOF

chmod 700 "$B"

tmux kill-session -t kigagn-update-bridge 2>/dev/null || true
tmux new-session -d -s kigagn-update-bridge "cd $D && exec node engine/update-bridge.cjs >> logs/update-bridge.log 2>&1"

touch "$BOOT"
LINE='tmux has-session -t kigagn-update-bridge 2>/dev/null || tmux new-session -d -s kigagn-update-bridge "cd $D && exec node engine/update-bridge.cjs >> logs/update-bridge.log 2>&1"'
grep -F "$LINE" "$BOOT" >/dev/null 2>&1 || printf '\n%s\n' "$LINE" >> "$BOOT"

sleep 2
curl -fsS http://127.0.0.1:8091/health
echo
echo "PONT KIGAGN S20 INSTALLE"
