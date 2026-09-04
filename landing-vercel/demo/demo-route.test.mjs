import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const contentTypes = {
  ".css": "text/css",
  ".html": "text/html",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
};

test("the exact public /demo rewrite resolves runnable local assets", async () => {
  const landingRoot = new URL("../", import.meta.url);
  const config = JSON.parse(await readFile(new URL("../vercel.json", import.meta.url), "utf8"));
  const rewrites = new Map(config.rewrites.map(({ source, destination }) => [source, destination]));
  const header = (source, name) => config.headers
    .find((entry) => entry.source === source)
    ?.headers.find(({ key }) => key === name)
    ?.value || "";
  const resolveRequest = async (requestPath) => {
    const requestedPath = new URL(requestPath, "https://roma.example").pathname;
    const pathname = rewrites.get(requestedPath) || requestedPath;
    const filePath = path.resolve(landingRoot.pathname, `.${pathname}`);
    return {
      body: await readFile(filePath, "utf8"),
      contentType: contentTypes[path.extname(filePath)] || "application/octet-stream",
    };
  };

  const page = await resolveRequest("/demo");
  assert.equal(page.contentType, "text/html");
  assert.match(page.body, /data-demo-root/);
  assert.match(page.body, /data-dictation-input/);
  assert.match(page.body, /class="environment-stack"[^>]+inert/);
  assert.match(page.body, /Roma servers receive or store no audio or text/);
  assert.equal((page.body.match(/data-environment=/g) || []).length, 9);
  assert.match(page.body, /<template data-site-bar-template>/);
  assert.match(page.body, /data-site-bar-toggle/);
  assert.match(page.body, /<nav class="site-bar"[^>]+aria-label="Site"/);
  assert.doesNotMatch(page.body, /<nav class="topline"|demo-intro|demo-controls|context-rail|shuffle context/i);
  assert.doesNotMatch(page.body, /<script(?![^>]+src=)[^>]*>\s*\S/i);
  assert.doesNotMatch(page.body, /<script[^>]+src="https:/i);
  assert.doesNotMatch(page.body, /analytics|insights|raw\.githubusercontent\.com/i);
  assert.equal(header("/(.*)", "Permissions-Policy"), "microphone=(self)");
  assert.match(header("/demo", "Content-Security-Policy"), /default-src 'self'/);
  assert.doesNotMatch(page.body, /botid|\/api\/transcribe|AI Gateway|OpenAI/);
  const assetReferences = [...page.body.matchAll(/<(?:link|script)[^>]+(?:href|src)="([^"]+)"/g)]
    .map((match) => match[1])
    .filter((reference) => !reference.startsWith("https://") && !reference.startsWith("/_vercel/"));

  assert.match(page.body, /<link[^>]+href="\/demo\/[^"?]+\.css(?:\?[^\"]*)?"/);
  assert.match(page.body, /<script[^>]+type="module"[^>]+src="\/demo\/[^"?]+\.mjs(?:\?[^\"]*)?"/);
  let demoCss = "";
  for (const reference of assetReferences) {
    const assetUrl = new URL(reference, "https://roma.example/demo");
    const asset = await resolveRequest(assetUrl.pathname);
    assert.match(asset.contentType, /^(?:text\/css|text\/javascript)/, reference);
    assert.ok(asset.body.length > 0, reference);
    if (assetUrl.pathname === "/demo/demo.css") demoCss = asset.body;
  }

  const cssImports = [...demoCss.matchAll(/@import url\("([^"]+)"\)/g)].map((match) => match[1]);
  for (const reference of cssImports) {
    const assetUrl = new URL(reference, "https://roma.example/demo/demo.css");
    const asset = await resolveRequest(assetUrl.pathname);
    assert.equal(asset.contentType, "text/css", reference);
    assert.ok(asset.body.length > 0, reference);
  }
});
