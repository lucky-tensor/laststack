// dev.bun.js - Full development loop
// Usage: bun run scripts/dev.bun.js
//
// Steps:
// 1. Build Wasm from .ll files
// 2. Serve the webpage
// 3. Take screenshot (optional)
// 4. Evaluate (manual)

// Configuration
const PORT = 8080;
const SCREENSHOT_PATH = 'screenshot.png';
const DEMO_DIR = './';

import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function runBuild() {
  console.log('📦 Building Wasm...');
  
  const buildProcess = spawn('./build.sh', [], {
    cwd: path.join(__dirname, DEMO_DIR),
    shell: true
  });
  
  return new Promise((resolve, reject) => {
    buildProcess.on('close', (code) => {
      if (code === 0) {
        console.log('✅ Build complete');
        resolve();
      } else {
        reject(new Error(`Build failed with code ${code}`));
      }
    });
    buildProcess.on('error', reject);
  });
}

async function startServer() {
  console.log(`🌐 Starting server on port ${PORT}...`);
  
  const server = Bun.serve({
    port: PORT,
    fetch(req) {
      const url = new URL(req.url);
      let filePath = url.pathname === '/' ? '/index.html' : url.pathname;
      
      const file = Bun.file(path.join(__dirname, DEMO_DIR, filePath));
      
      if (file.exists()) {
        return new Response(file);
      }
      return new Response('Not Found', { status: 404 });
    },
  });
  
  console.log(`   Server running at http://localhost:${server.port}`);
  return server;
}

async function takeScreenshot(url = `http://localhost:${PORT}`) {
  console.log(`📸 Taking screenshot...`);
  
  // Check if playwright is available
  try {
    const { chromium } = await import('playwright');
    
    const browser = await chromium.launch({ 
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: 'networkidle' });
    
    // Wait for Wasm to initialize
    await page.waitForFunction(() => {
      return document.getElementById('root')?.children.length > 0;
    }, { timeout: 5000 }).catch(() => {});
    
    await page.waitForTimeout(500);
    await page.screenshot({ path: SCREENSHOT_PATH, fullPage: true });
    await browser.close();
    
    console.log(`   Screenshot saved to ${SCREENSHOT_PATH}`);
  } catch (e) {
    console.log(`   ⚠️  Playwright not available: ${e.message}`);
    console.log(`   Install with: bun add -d playwright && bunx playwright install chromium`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const screenshot = args.includes('--screenshot') || args.includes('-s');
  const buildOnly = args.includes('--build') || args.includes('-b');
  
  try {
    // Step 1: Build
    await runBuild();
    
    if (buildOnly) {
      console.log('✅ Build only mode - skipping server');
      return;
    }
    
    // Step 2: Start server
    const server = await startServer();
    
    // Step 3: Screenshot (optional)
    if (screenshot) {
      await takeScreenshot();
    } else {
      console.log(`\n🔗 Open http://localhost:${PORT} in browser`);
      console.log('   Or run with --screenshot to capture automatically');
    }
    
    // Keep server running
    console.log('\n🛑 Press Ctrl+C to stop');
    
  } catch (e) {
    console.error('❌ Error:', e.message);
    process.exit(1);
  }
}

main();
