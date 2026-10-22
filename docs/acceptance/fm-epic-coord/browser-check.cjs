// Run with Playwright available on NODE_PATH and the devserve URL as argv[2].
const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({headless: true});
  const results = [];
  try {
    for (const width of [1440, 390]) {
      for (const theme of ['light', 'dark']) {
        const page = await browser.newPage({viewport: {width, height: 1000}, colorScheme: theme});
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        for (const [name, route, selector] of [
          ['board', '/?project=foreman', '#epics [data-bead="fm-3c3"] [phx-click="launch-session"]'],
          ['epic', '/epics/foreman/fm-3c3', '#epic-launch']
        ]) {
          await page.goto(new URL(route, process.argv[2]).href);
          await page.locator('.phx-connected').first().waitFor();
          await page.evaluate(theme => document.documentElement.setAttribute('data-theme', theme), theme);
          const control = page.locator(selector);
          await control.waitFor();
          assert.equal((await control.innerText()).trim(), 'Launch');
          const bounds = await control.boundingBox();
          assert(bounds.x >= 0 && bounds.x + bounds.width <= width, `${name}: control outside viewport`);
          const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
          assert.equal(overflow, false, `${name}: document overflow`);
          assert.deepEqual(errors, []);
          await page.screenshot({path: path.join(__dirname, `${name}-${width}-${theme}.png`), fullPage: true});
          results.push({name, width, theme, control: 'Launch', overflow, errors: [...errors]});
        }
        await page.close();
      }
    }
    fs.writeFileSync(path.join(__dirname, 'browser.json'), JSON.stringify(results, null, 2) + '\n');
    console.log(JSON.stringify(results, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
