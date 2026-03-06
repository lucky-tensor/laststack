// capture.bun.ts - Capture screenshot and DOM dump
// Usage: bun run scripts/capture.bun.ts [url] [component-name]
//
// Output: captures/[component-name]/screenshot.png and dom.html

import { chromium } from 'playwright';
import { mkdir, writeFile } from 'fs/promises';
import { existsSync } from 'fs';
import path from 'path';

const url = process.argv[2] || 'http://localhost:8080';
const componentName = process.argv[3] || 'component';
const outputDir = `./captures/dev/${componentName}`;

async function main() {
  console.log(`Capturing from ${url}...`);
  
  // Create output directory
  if (!existsSync(outputDir)) {
    await mkdir(outputDir, { recursive: true });
  }
  
  const browser = await chromium.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  
  const page = await browser.newPage();
  await page.goto(url, { waitUntil: 'networkidle' });
  
  // Wait for content to render
  await page.waitForTimeout(1000);
  
  // Wait for Wasm to initialize (if present)
  try {
    await page.waitForFunction(() => {
      return document.getElementById('root')?.children.length > 0;
    }, { timeout: 5000 });
  } catch (e) {
    console.log('Note: No Wasm initialization detected');
  }
  
  // Take screenshot
  const screenshotPath = path.join(outputDir, 'screenshot.png');
  await page.screenshot({ path: screenshotPath, fullPage: true });
  console.log(`Screenshot: ${screenshotPath}`);
  
  // Get DOM dump
  const domContent = await page.content();
  const domPath = path.join(outputDir, 'dom.html');
  await writeFile(domPath, domContent);
  console.log(`DOM dump: ${domPath}`);
  
  // Get computed styles for #root children
  const styles = await page.evaluate(() => {
    const root = document.getElementById('root');
    if (!root) return null;
    
    const elements = [];
    const walk = (node, depth = 0) => {
      if (depth > 10) return; // Limit depth
      if (node.nodeType === Node.ELEMENT_NODE) {
        const computed = window.getComputedStyle(node);
        elements.push({
          tag: node.tagName.toLowerCase(),
          id: node.id,
          class: node.className,
          style: node.getAttribute('style'),
          computed: {
            backgroundColor: computed.backgroundColor,
            color: computed.color,
            padding: computed.padding,
            margin: computed.margin,
            borderRadius: computed.borderRadius,
            boxShadow: computed.boxShadow,
            fontSize: computed.fontSize,
            fontWeight: computed.fontWeight,
          }
        });
      }
      node.childNodes.forEach(child => walk(child, depth + 1));
    };
    walk(root);
    return elements;
  });
  
  const stylesPath = path.join(outputDir, 'computed-styles.json');
  await writeFile(stylesPath, JSON.stringify(styles, null, 2));
  console.log(`Computed styles: ${stylesPath}`);
  
  await browser.close();
  console.log('Done.');
}

main().catch(console.error);
