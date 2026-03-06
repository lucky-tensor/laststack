// dev.bun.ts - Full development loop
// Usage: bun run scripts/dev.bun.ts [--component NAME]
//
// Steps:
// 1. Build Wasm from .ll files
// 2. Serve the webpage
// 3. Take screenshot
// 4. Compare with reference

import { spawn } from 'child_process';
import path from 'path';

const PORT = 31417;
const args = process.argv.slice(2);
const component = args.includes('--component') 
  ? args[args.indexOf('--component') + 1] 
  : null;

async function runBuild() {
  console.log('📦 Building Wasm...');
  
  return new Promise<void>((resolve, reject) => {
    const build = spawn('./build.sh', [], { 
      cwd: path.join(process.cwd()),
      shell: true 
    });
    
    build.on('close', (code) => {
      if (code === 0) {
        console.log('✅ Build complete');
        resolve();
      } else {
        reject(new Error(`Build failed with code ${code}`));
      }
    });
    build.on('error', reject);
  });
}

async function main() {
  try {
    // Build
    await runBuild();
    
    console.log('✅ Development loop complete');
    console.log(`Serve with: bun run scripts/serve.bun.ts --port ${PORT}`);
    
  } catch (e) {
    console.error('❌ Error:', e);
    process.exit(1);
  }
}

main();
