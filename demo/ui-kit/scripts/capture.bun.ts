// capture.bun.ts - Capture screenshot and DOM dump using Playwright
// Usage: bun run scripts/capture.bun.ts [html-file] [output-name]

import { chromium } from 'playwright';
import { mkdir, writeFile } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';

const htmlFile = process.argv[2] || 'index.html';
const outputName = process.argv[3] || 'capture';
const outputDir = `/tmp/alien-stack-captures/${outputName}`;

async function capture() {
  console.log(`Starting server...`);

  // Create output directory
  if (!existsSync(outputDir)) {
    await mkdir(outputDir, { recursive: true });
  }

  // Start a simple HTTP server
  const server = Bun.serve({
    port: 0,
    fetch(req) {
      const url = new URL(req.url);
      let filePath = url.pathname;
      if (filePath === '/') filePath = '/' + htmlFile;

      const fullPath = process.cwd() + filePath;
      const file = Bun.file(fullPath);

      if (file.exists()) {
        return new Response(file);
      }
      return new Response('Not Found', { status: 404 });
    },
  });

  const url = `http://localhost:${server.port}/${htmlFile}`;
  console.log(`Loading ${url}...`);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  const context = await browser.newContext();
  const page = await context.newPage();

  // Listen for console messages
  page.on('console', msg => console.log('CONSOLE:', msg.text()));
  page.on('pageerror', err => console.log('ERROR:', err.message));

  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 10000 });
    await page.waitForTimeout(2000);

    // Take screenshot
    const screenshotPath = path.join(outputDir, 'screenshot.png');
    await page.screenshot({ path: screenshotPath, fullPage: true });
    console.log(`Screenshot: ${screenshotPath}`);

    // Get DOM dump
    const domContent = await page.content();
    const domPath = path.join(outputDir, 'dom.html');
    await writeFile(domPath, domContent);
    console.log(`DOM dump: ${domPath}`);

    console.log('Done.');

  } catch (e) {
    console.error('Error:', e);
  } finally {
    await context.close();
    await browser.close();
    server.stop();
  }
}

capture();
