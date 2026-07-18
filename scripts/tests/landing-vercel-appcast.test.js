const assert = require("node:assert/strict");
const test = require("node:test");

const appcastHandler = require("../../landing-vercel/api/appcast");

const release = {
  tag_name: "v1.95",
  html_url: "https://github.com/happyf-weallareeuropean/roma-just-talk/releases/tag/v1.95",
  published_at: "2026-06-17T05:54:21Z",
  draft: false,
  prerelease: false,
  assets: [{ name: "roma.just.talk.app.zip", state: "uploaded" }],
};

function mockResponse() {
  const headers = new Map();
  return {
    body: undefined,
    headers,
    statusCode: 0,
    setHeader(name, value) {
      headers.set(name.toLowerCase(), value);
    },
    end(body) {
      this.body = body;
    },
  };
}

test("maps release versions to the app build-number scheme", () => {
  assert.deepEqual(appcastHandler.releaseVersion("v1.95"), { build: "195", short: "1.95" });
  assert.equal(appcastHandler.releaseVersion("v1.95.1"), null);
});

test("builds an informational appcast without an install enclosure", () => {
  const appcast = appcastHandler.buildAppcast(release);

  assert.match(appcast, /<sparkle:version>195<\/sparkle:version>/);
  assert.match(appcast, /<sparkle:shortVersionString>1\.95<\/sparkle:shortVersionString>/);
  assert.match(appcast, /releases\/tag\/v1\.95/);
  assert.doesNotMatch(appcast, /<enclosure\b/);
});

test("serves the latest fork release with cache and mode headers", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({ ok: true, json: async () => release });

  try {
    const response = mockResponse();
    await appcastHandler({ method: "GET" }, response);

    assert.equal(response.statusCode, 200);
    assert.equal(response.headers.get("content-type"), "application/rss+xml; charset=utf-8");
    assert.equal(response.headers.get("x-appcast-mode"), "informational");
    assert.equal(response.headers.get("x-appcast-source"), "github");
    assert.match(response.body, /Roma Just Talk 1\.95/);
  } finally {
    global.fetch = originalFetch;
  }
});

test("falls back to the last known fork release when GitHub is unavailable", async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => {
    throw new Error("offline");
  };

  try {
    const response = mockResponse();
    await appcastHandler({ method: "GET" }, response);

    assert.equal(response.statusCode, 200);
    assert.equal(response.headers.get("x-appcast-source"), "fallback");
    assert.match(response.body, /Roma Just Talk 1\.95/);
  } finally {
    global.fetch = originalFetch;
  }
});
