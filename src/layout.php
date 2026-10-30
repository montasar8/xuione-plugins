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
