// serve.bun.ts - Static file server using Bun
// Usage: bun run scripts/serve.bun.ts [--port N] [--root DIR]

const args = process.argv.slice(2);
let port = 8080;
let root = '.';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--port' && args[i + 1]) {
    port = parseInt(args[i + 1], 10);
    i++;
  } else if (args[i] === '--root' && args[i + 1]) {
    root = args[i + 1];
    i++;
  }
}

console.log(`Serving ${root} on http://localhost:${port}`);

const server = Bun.serve({
  port,
  fetch(req) {
    const url = new URL(req.url);
    let filePath = url.pathname;

    if (filePath === '/') filePath = '/index.html';

    const fullPath = `${root}${filePath}`;
    
    try {
      const file = Bun.file(fullPath);
      if (file.exists()) {
        return new Response(file);
      }
    } catch (e) {
      // File not found
    }

    return new Response('Not Found', { status: 404 });
  },
});

console.log(`Server running at http://localhost:${server.port}`);

export {};
