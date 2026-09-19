#!/usr/bin/env node
/**
 * page-shot — render a URL with headless Chromium and write a PNG screenshot.
 *
 * Lets Pi agents visually inspect pages under development. Pair with the
 * built-in `read` tool: the agent reads the resulting PNG, and the model
 * receives it as an image attachment (requires the model to be
 * vision-capable: "input": ["text", "image"] in models.json).
 *
 * Usage:
 *   page-shot <url> <out.png> [options]
 *
 * Options:
 *   --full                 Full-page screenshot (default: viewport only)
 *   --viewport WxH         Viewport size (default: 1280x900)
 *   --wait <ms>            Extra wait after page load (default: 1000)
 *   --selector <css>       Wait for this CSS selector before screenshot
 *
 * Examples:
 *   page-shot http://localhost:3000 /tmp/page.png
 *   page-shot http://localhost:3000 /tmp/full.png --full
 *   page-shot http://localhost:3000 /tmp/page.png --selector "#app" --wait 2000
 *
 * Output (stdout, single-line JSON):
 *   { ok, out, url, status, title, consoleErrors, failedRequests }
 * On failure: { ok: false, error }
 */
'use strict';

const { chromium } = require('playwright');

function parseArgs(argv) {
  const opts = { full: false, viewport: '1280x900', wait: 1000, selector: null, positionals: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--full') opts.full = true;
    else if (a === '--viewport') opts.viewport = argv[++i];
    else if (a === '--wait') opts.wait = Number(argv[++i]);
    else if (a === '--selector') opts.selector = argv[++i];
    else if (a.startsWith('--')) throw new Error(`Unknown flag: ${a}`);
    else opts.positionals.push(a);
  }
  return opts;
}

(async () => {
  const opts = parseArgs(process.argv.slice(2));
  const [url, out] = opts.positionals;
  if (!url || !out) {
    console.error('Usage: page-shot <url> <out.png> [--full] [--viewport WxH] [--wait <ms>] [--selector <css>]');
    process.exit(2);
  }
  const [w, h] = opts.viewport.toLowerCase().split('x').map((n) => parseInt(n, 10));
  if (!w || !h) throw new Error(`Bad --viewport: ${opts.viewport} (expected WxH, e.g. 1280x900)`);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  try {
    const page = await browser.newPage({ viewport: { width: w, height: h } });
    const consoleErrors = [];
    const failedRequests = [];
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => consoleErrors.push(`pageerror: ${err}`));
    page.on('requestfailed', (req) => {
      const ft = req.failure() ? req.failure().errorText : 'unknown';
      failedRequests.push(`${req.method()} ${req.url()} - ${ft}`);
    });

    const response = await page.goto(url, { waitUntil: 'load', timeout: 30000 });
    if (opts.selector) await page.waitForSelector(opts.selector, { timeout: 15000 });
    if (opts.wait > 0) await page.waitForTimeout(opts.wait);

    await page.screenshot({ path: out, fullPage: opts.full });

    console.log(JSON.stringify({
      ok: true,
      out,
      url: page.url(),
      status: response ? response.status() : null,
      title: await page.title(),
      consoleErrors: consoleErrors.slice(0, 15),
      failedRequests: failedRequests.slice(0, 15),
    }));
  } finally {
    await browser.close();
  }
})().catch((err) => {
  console.log(JSON.stringify({ ok: false, error: String(err && err.message ? err.message : err) }));
  process.exit(1);
});
