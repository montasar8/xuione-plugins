# Plugin package format

```
<slug>/
├── plugin.php        required — manifest (returns an array)
├── view.php          required — the page, rendered inside XUI's chrome
├── install.php       optional — runs once when the plugin is enabled
└── uninstall.php     optional — runs once when the plugin is disabled/removed
```

Manifest keys: `slug` (must match folder, `[a-z0-9_-]{2,40}`), `name`, `version`, `desc`, `needs` (array of tags).

Zip the folder itself (`zip -r slug.zip slug/`) or its contents — both are accepted.
On upload the framework validates every path in the archive, reads the slug from `plugin.php`
and moves the folder to `/home/xui_plugins/plugins/<slug>/`, replacing any previous version.
Enabled state is kept in `/home/xui_plugins/state.json`.
