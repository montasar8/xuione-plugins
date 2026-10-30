<?php
/**
 * Plugin page. Rendered inside the real XUI.ONE admin chrome.
 *
 * Boot order matters: XUI's functions.php MUST be loaded before anything else
 * (it owns the session and authentication), then the framework config + layout.
 * When this view is reached through xui_plugins.php?p=<slug> these are already
 * loaded and the require_once calls are no-ops.
 */
chdir('/home/xui/admin');
require_once '/home/xui/admin/functions.php';
require_once dirname(__DIR__, 2).'/config.php';
require_once dirname(__DIR__, 2).'/layout.php';

$me = xp_require_admin();          // 403 unless an active XUI admin session
$db = xp_db();                      // read-only MariaDB handle (xui_custom)

$lines = $db->query("SELECT COUNT(*) AS n FROM `lines`")->fetch_assoc()['n'] ?? 0;

xp_header('Example Plugin');        // XUI header + opens the .wrapper content area
?>
<div class="row">
  <div class="col-md-4">
    <div class="card"><div class="card-body">
      <h3><?= (int)$lines ?></h3>
      <div class="text-muted">Lines on this panel</div>
    </div></div>
  </div>
  <div class="col-md-8">
    <div class="card"><div class="card-body">
      <h5>Hello, <?= htmlspecialchars($me['username']) ?></h5>
      <p class="text-muted mb-0">
        Edit <code>plugins/example-plugin/view.php</code>, zip the folder and upload it from the Plugins page.
        Use Bootstrap 4 classes — the page is styled by XUI's own CSS.
      </p>
    </div></div>
  </div>
</div>
<?php
xp_footer();                        // closes .wrapper, re-arms XUI's header stats, XUI footer
