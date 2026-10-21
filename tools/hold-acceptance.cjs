const {chromium} = require('playwright');
const fs = require('fs');
const {execFileSync} = require('node:child_process');
const assert = require('node:assert/strict');
const previews = JSON.parse(execFileSync('devserve', ['ls', '--json'], {encoding: 'utf8'}));
const preview = previews.previews.find(p => p.worktree === process.cwd() && p.owner === 'fm-parked');
assert(preview && preview.state === 'running' && preview.branch === 'fm-parked');
execFileSync('mix', ['run', '--no-start', 'tools/hold-preview.exs'], {env: {...process.env, MIX_ENV: 'test', HOLD_PREVIEW_DATABASE: preview.database}, stdio: 'inherit'});
const out = 'docs/acceptance/fm-parked';
fs.mkdirSync(out, {recursive: true});
(async () => {
  const browser = await chromium.launch({headless: true});
  const evidence = [];
  for (const width of [1440, 390]) for (const theme of ['light', 'dark']) {
    const page = await browser.newPage({viewport: {width, height: 1100}, colorScheme: theme});
    await page.addInitScript(value => localStorage.setItem('phx:theme', value), theme);
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(preview.url + '/?view=open');
    await page.waitForSelector('.phx-connected');
    await page.locator('#epics [data-bead=hold-epic] button[phx-click=toggle]').click();
    await page.locator('#epics [data-bead=hold-child] [data-ticket-status=on_hold]').waitFor();
    await page.locator('#toggle-on-hold').click();
    await page.locator('#toggle-on-hold-project-hold-demo').click();
    await page.locator('#on-hold [data-bead=hold-free]').waitFor();
    assert.deepEqual(await page.locator('#on-hold [data-bead]').evaluateAll(rows => rows.map(r => r.dataset.bead)), ['hold-child', 'hold-free']);
    assert.match(await page.locator('#on-hold [data-bead=hold-child]').innerText(), /hold-epic · Improve the build board/);
    assert.equal(await page.locator('#standalone [data-bead=hold-free], #unplanned [data-bead=hold-free]').count(), 0);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    await page.screenshot({path: `${out}/initiatives-${width}-${theme}.png`, fullPage: true});
    await page.locator('#on-hold [data-bead=hold-free] a.bb-ticket').click();
    await page.locator('#ticket-on-hold-reason').waitFor();
    assert.equal((await page.locator('#ticket-status').innerText()).trim(), 'On hold');
    assert.equal((await page.locator('#ticket-planning-state').innerText()).trim(), 'parked');
    assert.match(await page.locator('#ticket-on-hold-reason').innerText(), /Awaiting a replacement test device/);
    assert.equal(await page.locator('#ticket-on-hold-since time').getAttribute('title'), '2026-10-21T00:00:00Z');
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    await page.locator('#ticket-sheet [role=dialog]').evaluate(async el => {
      await Promise.all(el.getAnimations({subtree: true}).map(animation => animation.finished));
    });
    await page.screenshot({path: `${out}/sheet-${width}-${theme}.png`, fullPage: true});
    await page.goto(preview.url + '/?view=stale');
    await page.waitForSelector('.phx-connected');
    await page.locator('#toggle-on-hold').click();
    assert.equal(await page.locator('#on-hold [data-bead]').count(), 0);
    assert.deepEqual(errors, []);
    evidence.push({width, theme, onHoldOrder: ['hold-child', 'hold-free'], epicMembership: true, sheetReason: true, distinctPlanningState: true, excludedFromStale: true, overflow: false, errors});
    await page.close();
  }
  const apiPage = await browser.newPage();
  const api = [];
  for (const path of ['/api/repos', '/api/tickets/hold-demo/hold-free']) {
    const response = await apiPage.request.get(preview.url + path);
    assert.equal(response.status(), 401);
    api.push({path, status: response.status()});
  }
  await browser.close();
  const result = {preview: {...preview, worktree: '.'}, evidence, api};
  fs.writeFileSync(`${out}/browser.json`, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
})().catch(e => {console.error(e); process.exit(1)});
