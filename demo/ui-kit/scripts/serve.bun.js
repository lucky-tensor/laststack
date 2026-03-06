// serve.bun.js - Static file server using Bun
// Usage: bun run scripts/serve.bun.js [--port N] [--root DIR]
//
// Examples:
//   bun run scripts/serve.bun.js                    # Serve current dir on 8080
//   bun run scripts/serve.bun.js --port 8081        # Serve on custom port
//   bun run scripts/serve.bun.js --root reference   # Serve reference dir

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
    let path = url.pathname;

    if (path === '/') path = '/index.html';

    const filePath = `${root}${path}`;
    
    try {
      const file = Bun.file(filePath);
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
