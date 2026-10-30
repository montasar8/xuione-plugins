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
