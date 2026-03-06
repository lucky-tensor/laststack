// compare.bun.ts - Compare screenshots and DOM
// Usage: bun run scripts/compare.bun.ts [ref-dir] [dev-dir]

import { existsSync, readFileSync, readdirSync, statSync } from 'fs';
import path from 'path';

const refDir = process.argv[2] || './captures/reference/card';
const devDir = process.argv[3] || './captures/dev/card';

interface CompareResult {
  screenshotMatch: boolean;
  domMatch: boolean;
  differences: string[];
}

async function compareDirs(ref: string, dev: string): Promise<CompareResult> {
  const result: CompareResult = {
    screenshotMatch: false,
    domMatch: false,
    differences: []
  };
  
  // Check screenshot (basic file comparison for now)
  const refScreenshot = path.join(ref, 'screenshot.png');
  const devScreenshot = path.join(dev, 'screenshot.png');
  
  if (existsSync(refScreenshot) && existsSync(devScreenshot)) {
    const refStat = statSync(refScreenshot);
    const devStat = statSync(devScreenshot);
    
    // Size comparison as proxy for content
    const sizeMatch = refStat.size === devStat.size;
    result.screenshotMatch = sizeMatch;
    
    if (!sizeMatch) {
      result.differences.push(`Screenshot size differs: ref=${refStat.size} vs dev=${devStat.size}`);
    }
  } else {
    result.differences.push('Missing screenshot in one or both directories');
  }
  
  // Check DOM
  const refDom = path.join(ref, 'dom.html');
  const devDom = path.join(dev, 'dom.html');
  
  if (existsSync(refDom) && existsSync(devDom)) {
    const refContent = readFileSync(refDom, 'utf-8');
    const devContent = readFileSync(devDom, 'utf-8');
    
    // Compare DOM structure (simplified)
    const refTags = extractTags(refContent);
    const devTags = extractTags(devContent);
    
    result.domMatch = JSON.stringify(refTags) === JSON.stringify(devTags);
    
    if (!result.domMatch) {
      result.differences.push(`DOM structure differs: ${JSON.stringify(refTags)} vs ${JSON.stringify(devTags)}`);
    }
  } else {
    result.differences.push('Missing DOM dump in one or both directories');
  }
  
  return result;
}

function extractTags(html: string): string[] {
  const tags: string[] = [];
  const regex = /<(\w+)[^>]*>/g;
  let match;
  while ((match = regex.exec(html)) !== null) {
    tags.push(match[1]);
  }
  return [...new Set(tags)]; // Unique tags
}

async function main() {
  console.log(`Comparing:\n  Reference: ${refDir}\n  Development: ${devDir}\n`);
  
  if (!existsSync(refDir)) {
    console.error(`Reference directory not found: ${refDir}`);
    process.exit(1);
  }
  if (!existsSync(devDir)) {
    console.error(`Development directory not found: ${devDir}`);
    process.exit(1);
  }
  
  const result = await compareDirs(refDir, devDir);
  
  console.log('--- Results ---');
  console.log(`Screenshot match: ${result.screenshotMatch ? '✓' : '✗'}`);
  console.log(`DOM match: ${result.domMatch ? '✓' : '✗'}`);
  
  if (result.differences.length > 0) {
    console.log('\nDifferences:');
    result.differences.forEach(d => console.log(`  - ${d}`));
    process.exit(1);
  } else {
    console.log('\n✓ All checks passed!');
  }
}

main().catch(console.error);
