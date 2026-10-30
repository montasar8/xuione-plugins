#!/usr/bin/env bash
# =============================================================================
#  install.sh  —  XUI.ONE Plugins framework installer (https://github.com/OWNER/xuione-plugins)
#  Author: Monti <moutih1982@gmail.com>   License: MIT
#
#  Usage (as root on the XUI.ONE server):
#     bash xui-plugins-install.sh                 # install / re-install (keeps plugins + state)
#     bash xui-plugins-install.sh install --code ABCDEFGH   # pick a specific admin access code
#     bash xui-plugins-install.sh uninstall       # remove menu button + entry link (keeps /home/xui_plugins)
#     bash xui-plugins-install.sh uninstall --purge          # also delete /home/xui_plugins and the DB user
#
#  What it does
#     - detects the admin access code from /home/xui/bin/nginx/conf/codes/*.conf
#     - creates MariaDB user xui_custom@localhost (SELECT on xui.*) with a random password
#     - writes /home/xui_plugins/{config.php,layout.php,index.php,plugins/,tmp/}
#     - links /home/xui/admin/xui_plugins.php -> /home/xui_plugins/index.php
#     - patches codes/<CODE>.conf with the "Plugins" menu button (sub_filter), backup kept
#     - gracefully reloads the panel nginx (HUP)
#
#  Re-run any time (e.g. after the access code is regenerated). Safe: idempotent.
# =============================================================================
set -euo pipefail

ACTION="${1:-install}"; [ $# -gt 0 ] && shift || true
CODE=""; ADMIN_GROUP=1; PURGE=0
XUI=/home/xui
DEST=/home/xui_plugins
NGX_CONF_DIR="$XUI/bin/nginx/conf"
DB_USER=xui_custom

while [ $# -gt 0 ]; do
  case "$1" in
    --code)        CODE="$2"; shift 2;;
    --admin-group) ADMIN_GROUP="$2"; shift 2;;
    --purge)       PURGE=1; shift;;
    *) echo "unknown argument: $1"; exit 1;;
  esac
done

log(){  printf '\e[32m[+]\e[0m %s\n' "$*"; }
warn(){ printf '\e[33m[!]\e[0m %s\n' "$*"; }
die(){  printf '\e[31m[x]\e[0m %s\n' "$*"; exit 1; }

[ "$(id -u)" = 0 ] || die "run this as root"
[ -d "$XUI/admin" ] || die "XUI.ONE admin folder not found at $XUI/admin"
[ -d "$NGX_CONF_DIR/codes" ] || die "nginx codes folder not found at $NGX_CONF_DIR/codes"

# ---------------------------------------------------------------- detect access code
if [ -z "$CODE" ]; then
  mapfile -t CANDS < <(grep -l 'alias /home/xui/admin' "$NGX_CONF_DIR"/codes/*.conf 2>/dev/null || true)
  [ "${#CANDS[@]}" -ge 1 ] || die "no access-code conf aliasing /home/xui/admin found — pass --code <CODE>"
  if [ "${#CANDS[@]}" -gt 1 ]; then
    warn "several admin access codes found: $(for f in "${CANDS[@]}"; do basename "$f" .conf; done | tr '\n' ' ')"
    warn "using the first one; override with --code <CODE>"
  fi
  CODE="$(basename "${CANDS[0]}" .conf)"
fi
CONF="$NGX_CONF_DIR/codes/$CODE.conf"
[ -f "$CONF" ] || die "access-code conf not found: $CONF"
log "admin access code: $CODE"

nginx_reload(){
  local n=0
  for p in $(ps -eo pid,args | awk '/nginx: master/ && /xui\/bin\/nginx/{print $1}'); do kill -HUP "$p" && n=$((n+1)); done
  [ "$n" -gt 0 ] && log "nginx reloaded (HUP sent to $n master process(es))" || warn "panel nginx master not found — reload it manually"
}

# ---------------------------------------------------------------- uninstall
if [ "$ACTION" = "uninstall" ]; then
  if grep -q '# >>> xui_plugins' "$CONF"; then
    sed -i '/# >>> xui_plugins/,/# <<< xui_plugins/d' "$CONF"; log "removed menu button from $CONF"
  fi
  rm -f "$XUI/admin/xui_plugins.php" "$XUI/admin/xui_plugins"; log "removed entry links from $XUI/admin"
  nginx_reload
  if [ "$PURGE" = 1 ]; then
    rm -rf "$DEST"; log "deleted $DEST"
    mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" && log "dropped DB user $DB_USER" || warn "could not drop DB user"
  else
    log "kept $DEST (plugins, state, config). Use --purge to delete it."
  fi
  log "uninstall complete"; exit 0
fi

[ "$ACTION" = "install" ] || die "unknown action: $ACTION (use install|uninstall)"

# ---------------------------------------------------------------- database user
command -v mysql >/dev/null || die "mysql client not found"
mysql -e 'SELECT 1' >/dev/null 2>&1 || die "cannot connect to MariaDB as root via socket"
DBPASS="$(openssl rand -hex 16 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 32)"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DBPASS';
          ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DBPASS';
          GRANT SELECT ON xui.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" || die "creating DB user failed"
SOCK="$(mysql -NBe 'SELECT @@socket')"
log "DB user $DB_USER ready (socket $SOCK)"

# keep an existing catalog URL across re-installs
OLD_CATALOG=""
[ -f "$DEST/config.php" ] && OLD_CATALOG="$(grep -oP "const XP_CATALOG='\K[^']*" "$DEST/config.php" || true)"

mkdir -p "$DEST/plugins" "$DEST/tmp"

# ---------------------------------------------------------------- config.php
cat > "$DEST/config.php" <<'PHP'
<?php
const XP_DB_SOCK='__SOCK__';
const XP_DB_USER='__DBUSER__';
const XP_DB_PASS='__DBPASS__';
const XP_DB_NAME='xui';
const XP_ADMIN_GROUP=__ADMIN_GROUP__;
const XP_BASE='/__CODE__';
const XP_PLUG_URL=XP_BASE.'/xui_plugins.php';
const XP_PLUG_DIR=__DIR__.'/plugins';
const XP_STATE=__DIR__.'/state.json';
const XP_TMP=__DIR__.'/tmp';
const XP_CATALOG='__CATALOG__';   // optional: URL or file path of a catalog JSON

function xp_db():mysqli{ static $d=null; if($d===null){ $d=@new mysqli('localhost',XP_DB_USER,XP_DB_PASS,XP_DB_NAME,0,XP_DB_SOCK); if($d->connect_errno){http_response_code(500);exit('DB error');}} return $d; }
function xp_user():?array{ if(empty($_SESSION['hash']))return null; $s=xp_db()->prepare("SELECT id,username,member_group_id,status,credits FROM users WHERE id=?"); $u=(int)$_SESSION['hash']; $s->bind_param('i',$u); $s->execute(); $r=$s->get_result()->fetch_assoc(); return ($r&&(int)$r['status']===1)?$r:null; }
function xp_require_admin():array{ $u=xp_user(); if(!$u||(int)$u['member_group_id']!==XP_ADMIN_GROUP){http_response_code(403);exit('Admins only.');} return $u; }
function xp_csrf():string{ if(empty($_SESSION['plug_csrf']))$_SESSION['plug_csrf']=bin2hex(random_bytes(16)); return $_SESSION['plug_csrf']; }
function xp_csrf_check():void{ if(!hash_equals($_SESSION['plug_csrf']??'x',$_POST['_csrf']??'')){http_response_code(400);exit('Bad CSRF');} }
function xp_flash(?string $m=null,string $t='success'){ if($m===null){ $f=$_SESSION['xp_flash']??null; unset($_SESSION['xp_flash']); return $f; } $_SESSION['xp_flash']=['m'=>$m,'t'=>$t]; }

function xp_plugins():array{ $o=[]; foreach(glob(XP_PLUG_DIR.'/*/plugin.php') as $f){ $m=include $f; if(is_array($m)&&!empty($m['slug'])){$m['_dir']=dirname($f);$o[$m['slug']]=$m;} } ksort($o); return $o; }
function xp_state():array{ return is_file(XP_STATE)?(json_decode(file_get_contents(XP_STATE),true)?:[]):[]; }
function xp_state_set(array $s):void{ file_put_contents(XP_STATE,json_encode($s,JSON_PRETTY_PRINT),LOCK_EX); }
function xp_enabled(string $slug):bool{ return !empty(xp_state()[$slug]['enabled']); }
function xp_enable(string $slug):void{ $p=xp_plugins()[$slug]??null; if(!$p)return; if(is_file($p['_dir'].'/install.php'))include $p['_dir'].'/install.php'; $s=xp_state(); $s[$slug]=['enabled'=>true,'at'=>time()]; xp_state_set($s); }
function xp_disable(string $slug):void{ $p=xp_plugins()[$slug]??null; if($p&&is_file($p['_dir'].'/uninstall.php'))include $p['_dir'].'/uninstall.php'; $s=xp_state(); unset($s[$slug]); xp_state_set($s); }

function xp_rrmdir(string $d):void{ if(!is_dir($d)||is_link($d))return; foreach(scandir($d) as $f){ if($f==='.'||$f==='..')continue; $p="$d/$f"; (is_dir($p)&&!is_link($p))?xp_rrmdir($p):@unlink($p); } @rmdir($d); }

/** Unpack a plugin .zip into plugins/<slug>/ (slug read from plugin.php). Returns slug. */
function xp_install_zip(string $zipPath):string{
  if(!is_dir(XP_TMP)) mkdir(XP_TMP,0750,true);
  $tmp=XP_TMP.'/x'.bin2hex(random_bytes(4)); mkdir($tmp,0750,true);
  try{
    if(class_exists('ZipArchive')){
      $z=new ZipArchive; if($z->open($zipPath)!==true) throw new Exception('Cannot open zip');
      for($i=0;$i<$z->numFiles;$i++){ $n=$z->getNameIndex($i); if($n===false||strpos($n,'..')!==false||$n[0]==='/'||$n[0]==='\\') throw new Exception('Unsafe path in zip: '.$n); }
      if(!$z->extractTo($tmp)) throw new Exception('Extract failed'); $z->close();
    } elseif(function_exists('exec')){
      exec('unzip -q '.escapeshellarg($zipPath).' -d '.escapeshellarg($tmp).' 2>&1',$o,$rc); if($rc!==0) throw new Exception('unzip failed: '.implode(' ',$o));
    } else throw new Exception('No zip support on this PHP (ZipArchive missing, exec disabled)');
    $root=$tmp;
    if(!is_file("$root/plugin.php")){ $dirs=array_values(array_filter(glob("$tmp/*")?:[],'is_dir'));
      if(count($dirs)===1&&is_file($dirs[0].'/plugin.php')) $root=$dirs[0]; else throw new Exception('plugin.php not found in package'); }
    $src=file_get_contents("$root/plugin.php");
    if(!preg_match("/['\"]slug['\"]\s*=>\s*['\"]([a-z0-9_-]{2,40})['\"]/",$src,$m)) throw new Exception('No valid slug in plugin.php');
    $slug=$m[1]; $dest=XP_PLUG_DIR.'/'.$slug;
    if(is_dir($dest)) xp_rrmdir($dest);
    if(!rename($root,$dest)) throw new Exception('Could not move plugin into place');
    return $slug;
  } finally { xp_rrmdir($tmp); }
}
function xp_fetch_url(string $url,string $to):void{
  if(!preg_match('~^https?://~i',$url)) throw new Exception('Only http(s) URLs allowed');
  if(function_exists('curl_init')){ $c=curl_init($url); $fp=fopen($to,'w');
    curl_setopt_array($c,[CURLOPT_FILE=>$fp,CURLOPT_FOLLOWLOCATION=>true,CURLOPT_MAXREDIRS=>3,CURLOPT_TIMEOUT=>60,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_FAILONERROR=>true]);
    $ok=curl_exec($c); $err=curl_error($c); curl_close($c); fclose($fp); if(!$ok) throw new Exception('Download failed: '.$err); }
  else { $d=@file_get_contents($url,false,stream_context_create(['http'=>['timeout'=>60]])); if($d===false) throw new Exception('Download failed'); file_put_contents($to,$d); }
}
function xp_catalog():array{ if(XP_CATALOG==='')return [];
  try{ if(preg_match('~^https?://~i',XP_CATALOG)){ if(!is_dir(XP_TMP)) mkdir(XP_TMP,0750,true); $t=XP_TMP.'/catalog.json'; xp_fetch_url(XP_CATALOG,$t); $raw=file_get_contents($t); } else $raw=@file_get_contents(XP_CATALOG);
    $j=json_decode((string)$raw,true); return is_array($j)?$j:[]; }catch(Throwable $e){ return []; } }
PHP
sed -i "s#__SOCK__#$SOCK#; s#__DBUSER__#$DB_USER#; s#__DBPASS__#$DBPASS#; s#__ADMIN_GROUP__#$ADMIN_GROUP#; s#__CODE__#$CODE#; s#__CATALOG__#$OLD_CATALOG#" "$DEST/config.php"

# ---------------------------------------------------------------- layout.php
cat > "$DEST/layout.php" <<'PHP'
<?php
function xp_header(string $title='Plugins'){
    include '/home/xui/admin/header.php';
    echo '<div class="wrapper"><div class="container-fluid" style="padding:20px"><h4 class="mb-3">'.htmlspecialchars($title).'</h4>';
}
function xp_footer(){
    echo <<<'JS'
<script>(function(){
  function go(){ if(typeof headerStats==="function"){ try{ headerStats(); }catch(e){} } }
  if(document.readyState==="complete") go(); else window.addEventListener("load",go);
  if(!window.__xpHijack){ window.__xpHijack=1;
    document.addEventListener("click",function(e){
      var t=e.target, a=(t&&t.closest)?t.closest("a[href]"):null; if(!a) return;
      var h=a.getAttribute("href")||"";
      if(!h||h.charAt(0)==="#"||/^javascript:/i.test(h)||a.hasAttribute("data-toggle")||a.target==="_blank"||/xui_plugins\.php/.test(h)) return;
      if(!a.closest("#topnav, header, .topnav, .navbar-custom")) return;
      e.preventDefault(); e.stopImmediatePropagation(); window.location.href=a.href;
    },true);
    window.addEventListener("popstate",function(){ window.location.reload(); });
  }
})();</script>
JS;
    echo '</div></div>';
    include '/home/xui/admin/footer.php';
}
PHP

# ---------------------------------------------------------------- index.php (manager + router)
cat > "$DEST/index.php" <<'PHP'
<?php
if($_SERVER['REQUEST_METHOD']==='GET' && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']??'')!=='xmlhttprequest'){
    header('Location: /__CODE__/dashboard#xp='.rawurlencode($_SERVER['REQUEST_URI'])); exit;
}
chdir('/home/xui/admin');
require_once '/home/xui/admin/functions.php';
require_once __DIR__.'/config.php';
require_once __DIR__.'/layout.php';
xp_require_admin();

if($_SERVER['REQUEST_METHOD']==='POST'){
  xp_csrf_check(); $act=$_POST['action']??''; $slug=preg_replace('/[^a-z0-9_-]/','',$_POST['slug']??'');
  try{
    if($act==='enable'){ xp_enable($slug); xp_flash("Enabled $slug"); }
    elseif($act==='disable'){ xp_disable($slug); xp_flash("Disabled $slug",'warning'); }
    elseif($act==='remove'){ xp_disable($slug); if($slug!==''&&is_dir(XP_PLUG_DIR.'/'.$slug)) xp_rrmdir(XP_PLUG_DIR.'/'.$slug); xp_flash("Removed $slug from the server",'warning'); }
    elseif($act==='upload'){
      $f=$_FILES['pkg']??null; if(!$f||$f['error']!==UPLOAD_ERR_OK) throw new Exception('Upload failed (code '.($f['error']??'?').') — check upload_max_filesize');
      if(!preg_match('/\.zip$/i',$f['name'])) throw new Exception('Only .zip packages are accepted');
      if($f['size']>20*1024*1024) throw new Exception('Package too large (20 MB max)');
      if(!is_dir(XP_TMP)) mkdir(XP_TMP,0750,true);
      $tz=XP_TMP.'/up_'.bin2hex(random_bytes(4)).'.zip'; if(!move_uploaded_file($f['tmp_name'],$tz)) throw new Exception('Could not store upload');
      try{ $s=xp_install_zip($tz); } finally { @unlink($tz); }
      xp_flash("Installed $s — click Enable to activate it");
    }
    elseif($act==='fetch'){
      $item=null; foreach(xp_catalog() as $c){ if(($c['slug']??'')===$slug){$item=$c;break;} }
      if(!$item||empty($item['zip'])) throw new Exception('Plugin not found in catalog');
      if(!is_dir(XP_TMP)) mkdir(XP_TMP,0750,true);
      $tz=XP_TMP.'/dl_'.bin2hex(random_bytes(4)).'.zip';
      try{ xp_fetch_url($item['zip'],$tz); $s=xp_install_zip($tz); } finally { @unlink($tz); }
      xp_flash("Installed $s from catalog — click Enable to activate it");
    }
  }catch(Throwable $e){ xp_flash($e->getMessage(),'danger'); }
  header('Location: '.XP_PLUG_URL); exit;
}

$p=preg_replace('/[^a-z0-9_-]/','',$_GET['p']??'');
if($p!==''){ $all=xp_plugins();
  if(isset($all[$p])&&xp_enabled($p)&&is_file($all[$p]['_dir'].'/view.php')){ require $all[$p]['_dir'].'/view.php'; exit; }
  xp_header('Not found'); echo '<div class="card"><div class="card-body">Plugin not found or not enabled.</div></div>'; xp_footer(); exit; }

$all=xp_plugins(); $tok=xp_csrf(); $flash=xp_flash(); $catalog=xp_catalog();
$hid='<input type="hidden" name="_csrf" value="'.$tok.'">';
xp_header('Plugins');
if($flash) echo '<div class="alert alert-'.htmlspecialchars($flash['t']).'">'.htmlspecialchars($flash['m']).'</div>';

echo '<div class="card" style="margin-bottom:18px"><div class="card-body"><h5>Install a plugin package</h5>
<p class="text-muted" style="font-size:13px">Upload a <code>.zip</code> containing <code>plugin.php</code> and <code>view.php</code>. It is unpacked into <code>plugins/&lt;slug&gt;/</code> and appears below.</p>
<form method="post" action="'.XP_PLUG_URL.'" enctype="multipart/form-data" class="form-inline">'.$hid.'<input type="hidden" name="action" value="upload">
<input type="file" name="pkg" accept=".zip" required class="mr-2"> <button class="btn btn-primary btn-sm">Upload &amp; install</button></form></div></div>';

echo '<h5 class="mb-3">Installed on this server</h5><div class="row">';
foreach($all as $s=>$pl){ $on=xp_enabled($s);
  echo '<div class="col-md-4" style="margin-bottom:16px"><div class="card"><div class="card-body">';
  echo '<h5>'.htmlspecialchars($pl['name']).($on?' <span class="badge badge-success">enabled</span>':'').'</h5>';
  echo '<p class="text-muted" style="min-height:40px">'.htmlspecialchars($pl['desc']).'</p>';
  echo '<p class="text-muted" style="font-size:12px">v'.htmlspecialchars($pl['version']); foreach(($pl['needs']??[]) as $n) echo ' · '.htmlspecialchars($n); echo '</p>';
  if($on){ echo '<a class="btn btn-primary btn-sm" href="'.XP_PLUG_URL.'?p='.$s.'">Open</a> <form method="post" action="'.XP_PLUG_URL.'" style="display:inline">'.$hid.'<input type="hidden" name="slug" value="'.$s.'"><button class="btn btn-light btn-sm" name="action" value="disable">Disable</button></form> '; }
  else { echo '<form method="post" action="'.XP_PLUG_URL.'" style="display:inline">'.$hid.'<input type="hidden" name="slug" value="'.$s.'"><button class="btn btn-success btn-sm" name="action" value="enable">Enable</button></form> '; }
  echo '<form method="post" action="'.XP_PLUG_URL.'" style="display:inline" onsubmit="return confirm(\'Remove this plugin from the server?\')">'.$hid.'<input type="hidden" name="slug" value="'.$s.'"><button class="btn btn-outline-danger btn-sm" name="action" value="remove">Remove</button></form>';
  echo '</div></div></div>';
}
if(!$all) echo '<p class="text-muted">No plugins installed yet — upload a package above.</p>';
echo '</div>';

$avail=array_filter($catalog,function($c)use($all){ return !empty($c['slug'])&&!isset($all[$c['slug']]); });
if($avail){ echo '<h5 class="mb-3 mt-3">Available from catalog</h5><div class="row">';
  foreach($avail as $c){ echo '<div class="col-md-4" style="margin-bottom:16px"><div class="card"><div class="card-body"><h5>'.htmlspecialchars($c['name']??$c['slug']).'</h5><p class="text-muted" style="min-height:40px">'.htmlspecialchars($c['desc']??'').'</p><p class="text-muted" style="font-size:12px">v'.htmlspecialchars($c['version']??'').'</p>';
    echo '<form method="post" action="'.XP_PLUG_URL.'">'.$hid.'<input type="hidden" name="slug" value="'.htmlspecialchars($c['slug']).'"><button class="btn btn-success btn-sm" name="action" value="fetch">Install</button></form></div></div></div>'; }
  echo '</div>'; }
xp_footer();
PHP
sed -i "s#__CODE__#$CODE#g" "$DEST/index.php"

chown -R xui:xui "$DEST"
log "framework written to $DEST"

# ---------------------------------------------------------------- entry link in the admin folder
ln -sfn "$DEST/index.php" "$XUI/admin/xui_plugins.php"
chown -h xui:xui "$XUI/admin/xui_plugins.php"
log "linked $XUI/admin/xui_plugins.php -> $DEST/index.php"

# ---------------------------------------------------------------- nginx: Plugins menu button (sub_filter)
[ -f "$CONF.pre-xui_plugins.bak" ] || cp -p "$CONF" "$CONF.pre-xui_plugins.bak"
sed -i '/# >>> xui_plugins/,/# <<< xui_plugins/d' "$CONF"

# NOTE: no single quotes, no backslashes and no $ in this JS (it lives inside an nginx single-quoted string)
JS='(function(){var n=0;function add(){if(document.getElementById("xui-plugins-nav"))return;var a=[].slice.call(document.querySelectorAll("a")).find(function(x){return /Management/i.test(x.textContent)&&x.closest("li");});if(!a){if(n++<10)setTimeout(add,500);return;}var li=a.closest("li");var c=li.cloneNode(true);c.id="xui-plugins-nav";var s=c.querySelector("ul");if(s)s.remove();var la=c.querySelector("a")||c;la.innerHTML=la.innerHTML.replace(/Management/i,"Plugins");la.setAttribute("href","/__CODE__/xui_plugins.php");la.removeAttribute("data-toggle");la.removeAttribute("onclick");var ic=la.querySelector("i");if(ic){var keep=["fa","fas","far","fal","fab","fad","fa-solid","fa-regular","fa-light","fa-brands","fa-duotone","fa-thin","fa-sharp","fa-fw","fa-lg","fa-xs","fa-sm","fa-1x","fa-2x","mdi"];ic.className=ic.className.split(" ").filter(Boolean).map(function(t){if(keep.indexOf(t)>=0)return t;if(t.indexOf("fa-")===0)return "fa-puzzle-piece";if(t.indexOf("mdi-")===0)return "mdi-puzzle";if(t.indexOf("fe-")===0)return "fe-package";if(t.indexOf("ri-")===0)return "ri-puzzle-line";if(t.indexOf("ti-")===0)return "ti-package";if(t.indexOf("uil-")===0)return "uil-puzzle-piece";if(t.indexOf("dripicons-")===0)return "dripicons-toggles";return t;}).join(" ");}else{var sv=la.querySelector("svg");if(sv){var ni=document.createElement("i");ni.className="fas fa-puzzle-piece";sv.parentNode.replaceChild(ni,sv);}}li.parentNode.insertBefore(c,li.nextSibling);}function xp(){var h=location.hash;if(h.indexOf("#xp=")!==0)return;var u=decodeURIComponent(h.slice(4));try{history.replaceState({},"",location.pathname+location.search);}catch(e){}(function go(k){if(typeof navigate==="function"){navigate(u);}else if(k<20){setTimeout(function(){go(k+1);},300);}})(0);}function init(){add();if(document.readyState==="complete")xp();else window.addEventListener("load",xp);}if(document.readyState!=="loading")init();else document.addEventListener("DOMContentLoaded",init);})();'
JS="${JS//__CODE__/$CODE}"

export XP_BLOCK="    # >>> xui_plugins (menu button; managed by xui-plugins-install.sh)
    sub_filter_once on;
    sub_filter '</body>' '<script>${JS}</script></body>';
    # <<< xui_plugins"

if grep -q 'try_files' "$CONF"; then PAT='try_files'; else PAT='alias'; fi
awk -v pat="$PAT" 'BEGIN{done=0;block=ENVIRON["XP_BLOCK"]} {print} !done && index($0,pat){print block; done=1}' "$CONF" > "$CONF.tmp"
mv "$CONF.tmp" "$CONF"; chown xui:xui "$CONF"; chmod 550 "$CONF"
log "patched $CONF (backup: $CONF.pre-xui_plugins.bak)"

# sub_filter module check (warning only)
BIN="$(ps -eo args | grep 'nginx: master' | grep -v grep | grep -o '/home/xui[^ ]*' | head -1 || true)"
if [ -n "$BIN" ] && [ -x "$BIN" ]; then
  "$BIN" -V 2>&1 | grep -q http_sub_module || warn "this nginx build seems to lack http_sub_module — the menu button will not appear"
  "$BIN" -t -p "$XUI/bin/nginx" -c "$NGX_CONF_DIR/nginx.conf" >/dev/null 2>&1 || warn "nginx -t reported a problem; if the menu button does not appear, check: $BIN -t -p $XUI/bin/nginx -c $NGX_CONF_DIR/nginx.conf"
fi
nginx_reload

# ---------------------------------------------------------------- summary
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
log "XUI Plugins installed."
echo "    Open the admin panel, hard-refresh (Ctrl+Shift+R) and use the new  Plugins  menu item."
echo "    Entry URL:   http://${IP:-<server>}/$CODE/xui_plugins.php   (always reach it via the menu)"
echo "    Files:       $DEST   (plugins/ and state.json are preserved on re-install)"
echo "    Catalog:     set XP_CATALOG in $DEST/config.php to a catalog JSON URL for one-click installs"
echo "    Re-run this script after regenerating the access code. Uninstall: bash $0 uninstall [--purge]"
