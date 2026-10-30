<?php
/**
 * Plugin manifest. The folder name should equal the slug.
 *  slug    : [a-z0-9_-], unique — used in URLs and state.json
 *  needs   : free-form tags shown on the card (e.g. "read-only", "writes via XUI API", "cron")
 */
return [
    'slug'    => 'example-plugin',
    'name'    => 'Example Plugin',
    'version' => '1.0.0',
    'desc'    => 'Minimal template: shows the logged-in admin and a live count from the database.',
    'needs'   => ['read-only'],
];
