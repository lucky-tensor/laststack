// screenshot.bun.ts - Take screenshot using Playwright
// Usage: bun run scripts/screenshot.bun.ts [url] [output]
//
// Requires: bun add -d playwright && bunx playwright install chromium

import { chromium } from 'playwright';

const url = process.argv[2] || 'http://localhost:8080';
const output = process.argv[3] || 'screenshot.png';

async function main() {
  console.log(`Launching headless browser...`);
  
  const browser = await chromium.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  
  console.log(`Navigating to ${url}...`);
  await page.goto(url, { waitUntil: 'networkidle' });
  
  // Wait for Wasm to initialize
  await page.waitForFunction(() => {
    return document.getElementById('root')?.children.length > 0;
  }, { timeout: 5000 }).catch(() => {
    console.log('Warning: Wasm may not have initialized');
  });
  
  // Give a moment for any animations
  await page.waitForTimeout(500);
  
  console.log(`Saving screenshot to ${output}...`);
  await page.screenshot({ path: output, fullPage: true });
  
  await browser.close();
  console.log('Done.');
}

main().catch(console.error);
