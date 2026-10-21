// PREVIEW_URL must identify this session's devserve preview with synthetic age-demo fixtures.
const {chromium} = require('playwright');
const fs = require('fs');
const assert = require('node:assert/strict');
const base = process.env.PREVIEW_URL;
if (!/^http:\/\/127\.0\.0\.1:48[89]\d$/.test(base || '')) throw Error('requires devserve preview URL');
(async () => {
  const browser = await chromium.launch({headless: true});
  const out = 'docs/acceptance/fm-age';
  fs.mkdirSync(out, {recursive: true});
  const evidence = [];
  for (const width of [1440, 390]) for (const theme of ['light', 'dark']) {
    const page = await browser.newPage({viewport: {width, height: 1100}, colorScheme: theme});
    await page.addInitScript(value => localStorage.setItem('phx:theme', value), theme);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(base + '/?view=open');
    await page.waitForSelector('.phx-connected');
    await page.locator('#epics [data-bead=age-epic] button[phx-click=toggle]').click();
    await page.locator('#epics [data-bead=age-child] time').waitFor();
    await page.locator('#toggle-standalone').click();
    await page.locator('#toggle-standalone-project-age-demo').click();
    await page.locator('#standalone [data-bead=age-active] time').waitFor();
    await page.locator('#toggle-unplanned').click();
    await page.locator('#toggle-project-age-demo').click();
    await page.locator('#unplanned [data-bead=age-new] time').waitFor();
    const order = await page.locator('#unplanned [data-bead]').evaluateAll(rows => rows.map(row => row.dataset.bead));
    assert.deepEqual(order, ['age-new', 'age-old']);
    assert.equal(await page.locator('#unplanned [data-bead=age-active]').count(), 0);
    const ages = await page.locator('main time').evaluateAll(times => times.map(time => ({text: time.textContent.trim(), datetime: time.dateTime, title: time.title})));
    assert.equal(ages.length, 4);
    assert(ages.every(age => age.title === age.datetime && /ago$/.test(age.text)));
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
    assert.equal(overflow, false);
    await page.screenshot({path: `${out}/initiatives-${width}-${theme}.png`, fullPage: true});
    await page.locator('#unplanned [data-bead=age-new] a').click();
    await page.locator('#ticket-title').waitFor();
    assert.match(await page.locator('#ticket-title').innerText(), /Add keyboard shortcuts/);
    assert.deepEqual(errors, []);
    evidence.push({width, theme, order, ages, overflow, ticketSheet: true, errors});
    await page.close();
  }
  const response = await browser.newPage();
  const api = [];
  for (const path of ['/api/repos', '/api/tickets/age-demo/age-new']) {
    const result = await response.request.get(base + path);
    assert.equal(result.status(), 401);
    api.push({path, status: result.status()});
  }
  await browser.close();
  fs.writeFileSync(out + '/browser.json', JSON.stringify({evidence, api}, null, 2) + '\n');
  console.log(JSON.stringify({screenshots: evidence.length, evidence, api}, null, 2));
})().catch(error => {console.error(error); process.exit(1)});
