const {chromium} = require('playwright');
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const out = 'docs/acceptance/fm-orphans';
fs.mkdirSync(out, {recursive:true});
const previews = JSON.parse(execFileSync('devserve', ['ls','--json'], {encoding:'utf8'})).previews;
const preview = previews.find(p => p.worktree === process.cwd() && p.owner === 'fm-orphans' && p.state === 'running');
assert(preview, 'owned running devserve preview');
const ticket = 'orphan-' + Date.now();
const transcript = {ticket, preview: {...preview, worktree: '<checkout>/fm-orphans'}, steps:[]};
function command(...args) {
  const output = execFileSync('mix', ['run','--no-start','tools/orphans-preview.exs',...args], {
    env: {...process.env, MIX_ENV:'test', ORPHANS_PREVIEW_DATABASE:preview.database, ORPHANS_PREVIEW_TICKET:ticket}, encoding:'utf8'
  }).trim();
  transcript.steps.push({command:args, output});
  return output;
}
(async () => {
  const browser = await chromium.launch({headless:true});
  try {
    const context = await browser.newContext({viewport:{width:1440,height:1000}});
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.context().addInitScript(() => {
      window.notifications = [];
      window.Notification = class {
        static permission = 'granted';
        constructor(title, options) { window.notifications.push({title,...options}); }
        close() {}
      };
      if (!localStorage.getItem('foreman:notifications:v1')) localStorage.setItem('foreman:notifications:v1', JSON.stringify({seen:{}}));
    });
    await page.goto(preview.url + '/needs-you');
    await page.locator('.phx-connected').waitFor();
    const other = await page.context().newPage();
    await other.goto(preview.url + '/needs-you');
    await other.locator('.phx-connected').waitFor();
    const id = JSON.parse(command('ask').split('\n').at(-1)).id;
    assert.equal(JSON.parse(command('timeout',id).split('\n').at(-1)).state, 'pending');
    command('report');
    await page.locator(`#request-${id}`).waitFor();
    await page.locator(`#option-${id}-1`).check();
    await page.locator(`#decision-note-${id}`).fill('Keep the shortcuts.');
    await page.locator(`#submit-answer-${id}`).click();
    await page.locator(`#uncollected-${id}`).waitFor();
    assert.match(await page.locator(`#uncollected-${id}`).innerText(), /fm-orphans-preview/);
    assert.match(await page.locator(`#uncollected-${id}`).innerText(), /Compact/);
    await other.locator(`#uncollected-${id}`).waitFor();
    await other.locator('#needs-you-badge').click();
    await other.locator(`#drawer-uncollected-${id}`).waitFor();
    await page.waitForFunction(() => localStorage.getItem('foreman:notifications:v1').includes(':answer'));
    for (const theme of ['light','dark']) {
      await page.evaluate(theme => { document.documentElement.dataset.theme = theme; }, theme);
      await page.locator('#not-picked-up').screenshot({path:`${out}/${theme}.png`});
    }
    transcript.notifications = [...await page.evaluate(() => window.notifications), ...await other.evaluate(() => window.notifications)];
    assert.equal(transcript.notifications.filter(n => n.title === `Answer not picked up · ${ticket}`).length, 1);
    const consumed = JSON.parse(command('wait',id).split('\n').at(-1));
    assert.equal(consumed.state,'answered');
    assert.equal(consumed.outcome.answer,'Compact');
    await page.locator(`#uncollected-${id}`).waitFor({state:'detached'});
    await other.locator(`#drawer-uncollected-${id}`).waitFor({state:'detached'});
    const api = await page.request.post(preview.url + '/api/commands', {data:{action:'wait',id}});
    transcript.apiStatus = api.status();
    assert.equal(api.status(),401);
    assert.deepEqual(errors,[]);
    transcript.result = 'PASS: timeout, report, browser answer, one notification, later pickup clears section';
    fs.writeFileSync(`${out}/transcript.json`, JSON.stringify(transcript,null,2));
    console.log(transcript.result);
  } finally { await browser.close(); }
})().catch(e => {console.error(e); process.exitCode=1;});
