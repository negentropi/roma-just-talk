import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = Number.parseInt(process.env.ROMA_DEMO_PORT || process.env.PORT || "4173", 10);
const demoCsp = "default-src 'self'; base-uri 'none'; connect-src 'none'; font-src 'self'; form-action 'none'; frame-ancestors 'none'; img-src 'self'; object-src 'none'; script-src 'self'; style-src 'self'";
const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".png", "image/png"],
]);

function json(response, status, body, headers = {}) {
  response.writeHead(status, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    ...headers,
  });
  response.end(JSON.stringify(body));
}

function publicPath(pathname) {
  if (pathname === "/") return "/index.html";
  if (pathname === "/demo") return "/demo/index.html";
  if (pathname === "/pricing") return "/pricing/index.html";
  if (pathname === "/readme") return "/readme/index.html";
  if (pathname === "/changelogs") return "/changelogs/index.html";
  return pathname;
}

async function serveStatic(request, response, pathname) {
  const requested = path.resolve(root, `.${publicPath(pathname)}`);
  if (requested !== root && !requested.startsWith(`${root}${path.sep}`)) {
    json(response, 403, { error: "forbidden" });
    return;
  }
  try {
    const body = await readFile(requested);
    response.writeHead(200, {
      "cache-control": "no-cache",
      ...(pathname === "/demo" || pathname.startsWith("/demo/")
        ? { "content-security-policy": demoCsp }
        : {}),
      "content-type": contentTypes.get(path.extname(requested)) || "application/octet-stream",
      "permissions-policy": "microphone=(self)",
      "referrer-policy": "strict-origin-when-cross-origin",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
    });
    if (request.method === "HEAD") response.end();
    else response.end(body);
  } catch (error) {
    json(response, error?.code === "ENOENT" ? 404 : 500, { error: "not_found" });
  }
}

const server = createServer(async (request, response) => {
  try {
    if (!["GET", "HEAD"].includes(request.method || "")) {
      json(response, 405, { error: "method_not_allowed" }, { allow: "GET, HEAD" });
      return;
    }
    const url = new URL(request.url || "/", `http://${request.headers.host || "127.0.0.1"}`);
    await serveStatic(request, response, url.pathname);
  } catch {
    json(response, 500, { error: "server_error" });
  }
});

server.listen(port, "127.0.0.1", () => {
  process.stdout.write(`Roma demo listening on http://127.0.0.1:${port}\n`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
