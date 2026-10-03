const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildAppcast,
  buildDraftAppcast,
  normalizedRelease,
  releaseVersion,
} = require("../generate-github-release-appcast");

function release(overrides = {}) {
  return {
    tag_name: "v1.96",
    html_url: "https://github.com/negentropi/roma-just-talk/releases/tag/v1.96",
    published_at: "2026-07-31T12:34:56Z",
    body: "Fixes <upstream> routing & keeps notes.",
    draft: false,
    prerelease: false,
    assets: [{ name: "roma.just.talk.app.zip", state: "uploaded" }],
    ...overrides,
  };
}

test("maps release tags to the app build-number scheme", () => {
  assert.deepEqual(releaseVersion("v1.96"), { build: "196", short: "1.96" });
  assert.deepEqual(releaseVersion("v2.1"), { build: "201", short: "2.1" });
  assert.deepEqual(releaseVersion("v1.95.1"), { build: "195.1", short: "1.95.1" });
  assert.equal(releaseVersion("v1.95.1.2"), null);
});

test("publishes a patch release with the packaged app version", () => {
  const appcast = buildAppcast(release({
    tag_name: "v1.95.1",
    html_url: "https://github.com/negentropi/roma-just-talk/releases/tag/v1.95.1",
  }));
  assert.match(appcast, /<sparkle:version>195\.1<\/sparkle:version>/);
  assert.match(appcast, /<sparkle:shortVersionString>1\.95\.1<\/sparkle:shortVersionString>/);
});

test("builds a GitHub-backed informational Sparkle appcast", () => {
  const appcast = buildAppcast(release());

  assert.match(appcast, /<sparkle:version>196<\/sparkle:version>/);
  assert.match(appcast, /<sparkle:shortVersionString>1\.96<\/sparkle:shortVersionString>/);
  assert.match(appcast, /negentropi\/roma-just-talk\/releases\/tag\/v1\.96/);
  assert.match(appcast, /<description sparkle:format="markdown">/);
  assert.match(appcast, /Fixes &lt;upstream&gt; routing &amp; keeps notes\./);
  assert.doesNotMatch(appcast, /<enclosure\b/);
});

test("rejects releases that cannot safely become the stable feed", () => {
  assert.throws(
    () => normalizedRelease(release({ prerelease: true })),
    /published stable release/
  );
  assert.throws(
    () => normalizedRelease(release({ assets: [] })),
    /missing roma\.just\.talk\.app\.zip/
  );
  assert.throws(
    () => normalizedRelease(release({
      html_url: "https://github.com/Beingpax/VoiceInk/releases/tag/v2.1",
    })),
    /must belong to negentropi\/roma-just-talk/
  );
});

test("creates the same informational feed from an explicit draft intent", () => {
  const intent = { publicationTime: "2026-07-31T12:34:56Z", minimumSystemVersion: "14.4", appVersion: "1.96", appBuild: "196" };
  assert.equal(buildDraftAppcast(release({ draft: true, published_at: null }), intent), buildAppcast(release()));
  const appcast = buildDraftAppcast(release({ draft: true, published_at: null }), { ...intent, minimumSystemVersion: "14.2.1" });
  assert.match(appcast, /<sparkle:minimumSystemVersion>14\.2\.1<\/sparkle:minimumSystemVersion>/);
  assert.doesNotMatch(appcast, /<enclosure\b/);
  assert.match(appcast, /Fixes &lt;upstream&gt; routing &amp; keeps notes\./);
});

test("rejects invalid or mismatched draft intent without changing published metadata", () => {
  const draft = release({ draft: true, published_at: null });
  const intent = { publicationTime: "2026-07-31T12:34:56Z", minimumSystemVersion: "14.2.1", appVersion: "1.96", appBuild: "196" };
  for (const changes of [{ appBuild: "195" }, { appVersion: "1.95" }, { minimumSystemVersion: "14.2.1<bad>" }, { publicationTime: "2026-02-30T00:00:00Z" }]) {
    assert.throws(() => buildDraftAppcast(draft, { ...intent, ...changes }));
  }
  assert.throws(() => buildDraftAppcast(release(), intent), /unpublished stable draft/);
  assert.throws(() => buildDraftAppcast({ ...draft, assets: [...draft.assets, ...draft.assets] }, intent), /one uploaded/);
  assert.equal(draft.draft, true);
  assert.equal(draft.published_at, null);
});
