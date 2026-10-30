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
