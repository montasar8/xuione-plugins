# XUI.ONE Plugins

A small, open plugin framework for the **XUI.ONE 1.5.x** IPTV panel.

It adds a **Plugins** item to the admin menu and a page where you can upload plugin packages, enable/disable them, or install them with one click from a catalog. Plugin pages render **inside the real XUI admin interface** (same header, menu, styling, live stats) and are protected by the panel's own login — no second password, no separate site.

> Not affiliated with XUI.ONE or its author. XUI.ONE is proprietary software; this project contains none of its code. It only *includes* the panel's own `header.php` / `footer.php` at runtime, the same way a WordPress plugin includes WordPress. You need your own XUI.ONE installation.

## Why

XUI.ONE is encoded, so it cannot be modified or extended directly. This framework gives the community a clean, update-safe place to add the features the panel lacks — expiry/renewal reports, Telegram alerts, restream detection, backups, reseller tooling, billing hooks — without touching a single XUI file.

## Install

On the XUI.ONE server, as root:

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/xuione-plugins/main/install.sh -o install.sh
bash install.sh
```

Then hard-refresh the admin panel (`Ctrl+Shift+R`). A **Plugins** menu item appears next to *Management*.

The installer:

- detects your admin access code from `/home/xui/bin/nginx/conf/codes/`
- creates a **read-only** MariaDB user (`xui_custom`, random password) — plugins can never write to XUI's tables by accident
- writes the framework to `/home/xui_plugins/` (outside XUI, so panel updates can't wipe it)
- links `/home/xui/admin/xui_plugins.php` → the framework entry point
- adds the menu button via an nginx `sub_filter` in your access-code conf (backup kept, marker-delimited, idempotent)
- reloads nginx gracefully — no stream interruption

Re-run it any time (after regenerating the access code, or to upgrade). Your `plugins/`, `state.json` and `XP_CATALOG` setting are preserved.

```bash
bash install.sh uninstall           # remove menu button + entry link, keep /home/xui_plugins
bash install.sh uninstall --purge   # also delete /home/xui_plugins and the DB user
bash install.sh install --code ABCDEFGH   # choose an access code when a server has several
```

## Requirements

- XUI.ONE 1.5.x (tested on 1.5.13) on Ubuntu 20.04/22.04
- root shell; `mysql` client with socket access as root (standard on XUI servers)
- XUI's bundled nginx with `http_sub_module` (present in the standard build; the installer warns if not)
- For uploading packages: PHP `ZipArchive` *or* `exec()` + `unzip` in XUI's bundled PHP

## Writing a plugin

A plugin is a folder (or a zip of one) with two files:

```
my-plugin/
├── plugin.php   # manifest: slug, name, version, desc, needs
└── view.php     # the page
```

`plugin.php`:

```php
<?php return [
  'slug'=>'my-plugin', 'name'=>'My Plugin', 'version'=>'1.0.0',
  'desc'=>'What it does, in one line.', 'needs'=>['read-only'],
];
```

`view.php` — boot order matters (XUI's `functions.php` first), then use the helpers:

```php
<?php
chdir('/home/xui/admin'); require_once '/home/xui/admin/functions.php';
require_once dirname(__DIR__,2).'/config.php'; require_once dirname(__DIR__,2).'/layout.php';
$me = xp_require_admin();   // active XUI admin session or 403
$db = xp_db();              // read-only mysqli to the `xui` database

xp_header('My Plugin');
echo '<div class="card"><div class="card-body">Hello '.htmlspecialchars($me['username']).'</div></div>';
xp_footer();
```

Optional `install.php` / `uninstall.php` run when the plugin is enabled/disabled (set up a cron, create a settings file, …). Use Bootstrap 4 markup — XUI's CSS styles it. See [`plugins/example-plugin`](plugins/example-plugin).

Package it: `zip -r my-plugin.zip my-plugin/` and upload it from the Plugins page.

### Helpers (`config.php`)

| Function | Purpose |
|---|---|
| `xp_require_admin()` | Returns the XUI admin row (`id, username, member_group_id, credits`) or exits 403 |
| `xp_user()` | Same, or `null` when not logged in |
| `xp_db()` | Shared read-only `mysqli` to `xui` |
| `xp_csrf()` / `xp_csrf_check()` | Token for your own forms |
| `xp_flash($msg, $type)` | One-shot alert shown on the Plugins page |
| `xp_header($title)` / `xp_footer()` | Render inside XUI's chrome |

### Writing data

The DB user is deliberately **read-only**. To change panel data (create/extend lines, bouquets…), call XUI's own admin API (`/<code>/api.php`) so its internal logic (stream keys, load-balancer sync) runs. Direct writes to XUI's tables can corrupt the panel.

## Catalog (one-click installs)

Host a JSON file and set `XP_CATALOG` in `/home/xui_plugins/config.php` to its URL. Every entry not yet installed shows an **Install** button:

```json
[
  { "slug": "expiring-soon", "name": "Expiring Soon", "version": "1.0.0",
    "desc": "Lines expiring in 1/3/7/30 days, per reseller, with export.",
    "zip": "https://example.com/plugins/expiring-soon.zip" }
]
```

See [`catalog.example.json`](catalog.example.json).

## How it works (for the curious)

- **Auth / SSO:** XUI keeps its admin session in `$_SESSION['hash']` (user id). Plugin pages load XUI's `functions.php` first — which owns the session — then verify the user is an active admin via the DB.
- **Native look:** pages include XUI's real `header.php` / `footer.php` and put content inside `<div class="wrapper">`, which is the container XUI's `navigate()` swaps when you click a menu item. The page also re-arms XUI's `headerStats()` poller, which `navigate()` kills on every navigation.
- **Menu button:** an nginx `sub_filter` injects a tiny script into admin pages that clones the *Management* item, relabels it *Plugins* and swaps the icon. Scoped to the access-code location only — the player API and streams are untouched.
- **Cold loads:** XUI initialises its UI only on a cold load of a native page. A direct/refresh request to the plugins URL is therefore bounced through `dashboard#xp=<url>`; the menu script then navigates to the plugin via AJAX, so you always land on a fully initialised page.
- **Leaving a plugin page** does a normal full page load (instead of XUI's in-place swap) so the next page initialises cleanly. The one visible compromise.

## Security notes

- Everything is admin-only (`member_group_id = 1`) and CSRF-protected.
- Uploaded zips are checked for path traversal and size; the slug is validated before anything is moved into place. Installing a plugin means running its PHP as the panel's user — only install packages you trust.
- Plugin files live in `/home/xui_plugins/plugins/`, owned by the panel user; no XUI file is modified. The only XUI-side changes are a symlink and a marked block in one nginx conf, both removed by `uninstall`.

## Contributing

Plugins welcome — open a PR adding a folder under `plugins/`, or publish your own and submit it to the community catalog. Framework changes: edit `install.sh` (single source of truth) and run `scripts/extract-src.sh`; `scripts/check-sync.sh` must pass.

Ideas people have asked for: expiring/renewals report, Telegram alerts, credential-sharing/restream detector, automatic backups, stream health + auto-repair, reseller dashboard, client self-service portal, bulk tools via the admin API, billing bridges (WHMCS/Stripe/crypto), audit log.

## License

MIT — see [LICENSE](LICENSE).
