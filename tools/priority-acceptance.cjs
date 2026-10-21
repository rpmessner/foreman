const {chromium} = require('playwright');
const fs = require('fs');
const {execFileSync} = require('node:child_process');
const assert = require('node:assert/strict');
const previews = JSON.parse(execFileSync('devserve', ['ls', '--json'], {encoding: 'utf8'}));
const preview = previews.previews.find(p => p.worktree === process.cwd() && p.owner === 'fm-priority');
assert(preview && preview.state === 'running' && preview.branch === 'fm-priority');
const base = preview.url;
const out = 'docs/acceptance/fm-priority';
fs.mkdirSync(out, {recursive: true});
function command(action) {
  const output = execFileSync('mix', ['run', '--no-start', 'tools/priority-preview.exs', action], {
    encoding: 'utf8', env: {...process.env, MIX_ENV: 'test', PRIORITY_PREVIEW_DATABASE: preview.database}
  });
  return output.trim().split('\n').at(-1);
}
(async () => {
  command('seed');
  const browser = await chromium.launch({headless: true});
  const evidence = [];
  for (const width of [1440, 390]) for (const theme of ['light', 'dark']) {
    command('reset');
    const page = await browser.newPage({viewport: {width, height: 1100}, colorScheme: theme});
    await page.addInitScript(value => localStorage.setItem('phx:theme', value), theme);
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(base + '/?view=open');
    await page.waitForSelector('.phx-connected');
    await page.locator('#epics [data-bead=demo-epic] button[phx-click=toggle]').click();
    const planned = page.locator('#epics [data-kind=ticket]');
    await planned.first().waitFor();
    assert.deepEqual(await planned.evaluateAll(rows => rows.map(r => r.dataset.bead)), ['demo-b', 'demo-c', 'demo-a']);
    await page.screenshot({path: `${out}/initiatives-${width}-${theme}.png`, fullPage: true});
    await page.locator('#epics [data-bead=demo-a] a.bb-ticket').click();
    await page.locator('#ticket-priority [data-priority="4"]').waitFor();
    await page.locator('#ticket-priority-select').selectOption('1');
    await page.locator('#ticket-priority [data-priority="1"]').waitFor();
    assert.deepEqual(await planned.evaluateAll(rows => rows.map(r => r.dataset.bead)), ['demo-b', 'demo-a', 'demo-c']);
    await page.screenshot({path: `${out}/sheet-${width}-${theme}.png`, fullPage: true});
    await page.goto(base + '/needs-you');
    await page.waitForSelector('.phx-connected');
    const cards = page.locator('#pending-requests > article');
    const cardTickets = () => cards.evaluateAll(rows => rows.map(r => r.querySelector('a[title="Open ticket"]').textContent.trim()));
    assert.deepEqual(await cardTickets(), ['demo-b', 'demo-a', 'demo-c']);
    const cardA = cards.filter({has: page.locator('a[title="Open ticket"]', {hasText: 'demo-a'})});
    const note = cardA.locator('textarea');
    const choice = cardA.locator('input[type=radio]').first();
    await choice.check();
    await note.fill('Keep this unfinished answer');
    await note.evaluate(el => {window.savedPriorityInput = el});
    await cardA.locator('a[title="Open ticket"]').click();
    await page.locator('#ticket-jump').click();
    await page.locator('#ticket-priority [data-priority="0"]').waitFor();
    await page.waitForFunction(() => document.querySelector('#pending-requests > article a[title="Open ticket"]').textContent.trim() === 'demo-a');
    assert.deepEqual(await cardTickets(), ['demo-a', 'demo-b', 'demo-c']);
    assert.equal(await note.inputValue(), 'Keep this unfinished answer');
    assert.equal(await choice.isChecked(), true);
    assert.equal(await note.evaluate(el => window.savedPriorityInput === el), true);
    await page.screenshot({path: `${out}/needs-you-${width}-${theme}.png`, fullPage: true});
    await page.locator('#ticket-close').click();
    await page.screenshot({path: `${out}/needs-you-list-${width}-${theme}.png`, fullPage: true});
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    assert.deepEqual(errors, []);
    evidence.push({width, theme, initiativesOrder: ['demo-b', 'demo-a', 'demo-c'], needsYouOrder: await cardTickets(), preservedInputNode: true, preservedAnswer: true, errors});
    await page.close();
  }
  const overlay = JSON.parse(command('overlay'));
  assert.equal(overlay.priority_overrides.find(o => o.id === 'demo-a').priority, 0);
  assert.equal(overlay.jumps[0].id, 'demo-a');
  assert.deepEqual(JSON.parse(command('sync')).overrides, []);
  const apiPage = await browser.newPage();
  const api = [];
  for (const path of ['/api/repos', '/api/tickets/priority-demo/demo-a']) {
    const response = await apiPage.request.get(base + path);
    assert.equal(response.status(), 401);
    api.push({path, status: response.status()});
  }
  const response = await apiPage.request.post(base + '/api/commands', {data: {action: 'ls'}});
  assert.equal(response.status(), 401);
  api.push({path: '/api/commands', method: 'POST', status: response.status()});
  await browser.close();
  const result = {preview: {...preview, worktree: '.'}, evidence, overlay, syncCleared: true, api};
  fs.writeFileSync(`${out}/browser.json`, JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
})().catch(e => {console.error(e); process.exit(1)});
