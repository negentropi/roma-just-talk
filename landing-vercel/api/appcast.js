const releasesApi = "https://api.github.com/repos/happyf-weallareeuropean/roma-just-talk/releases/latest";
const releasesPage = "https://github.com/happyf-weallareeuropean/roma-just-talk/releases";
const releaseUrlPrefix = `${releasesPage}/tag/`;
const appArchiveName = "roma.just.talk.app.zip";
const minimumSystemVersion = "14.4";

const fallbackRelease = {
  tag_name: "v1.95",
  html_url: `${releaseUrlPrefix}v1.95`,
  published_at: "2026-06-17T05:54:21Z",
  draft: false,
  prerelease: false,
  assets: [{ name: appArchiveName, state: "uploaded" }],
};

function escapeXml(value) {
  return String(value).replace(/[&<>"']/g, (character) => {
    return {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&apos;",
    }[character];
  });
}

function releaseVersion(tagName) {
  const match = /^v?(\d+)\.(\d+)$/.exec(tagName || "");
  if (!match) return null;

  const major = Number(match[1]);
  const minor = Number(match[2]);
  if (!Number.isSafeInteger(major) || !Number.isSafeInteger(minor) || minor > 99) return null;

  return {
    build: String(major * 100 + minor),
    short: `${major}.${minor}`,
  };
}

function normalizeRelease(release) {
  if (!release || release.draft || release.prerelease) return null;

  const version = releaseVersion(release.tag_name);
  const publishedAt = new Date(release.published_at);
  const hasArchive = release.assets?.some((asset) => {
    return asset.name === appArchiveName && (!asset.state || asset.state === "uploaded");
  });
  const releaseUrl = typeof release.html_url === "string" ? release.html_url : "";

  if (!version || Number.isNaN(publishedAt.getTime()) || !hasArchive || !releaseUrl.startsWith(releaseUrlPrefix)) {
    return null;
  }

  return {
    ...version,
    publishedAt: publishedAt.toUTCString(),
    releaseUrl,
  };
}

function buildAppcast(release) {
  const item = normalizeRelease(release);
  if (!item) throw new Error("No eligible Roma Just Talk release found");

  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Roma Just Talk updates</title>
    <link>${releasesPage}</link>
    <description>Fork release notifications for Roma Just Talk.</description>
    <language>en</language>
    <item>
      <title>Roma Just Talk ${escapeXml(item.short)}</title>
      <link>${escapeXml(item.releaseUrl)}</link>
      <pubDate>${escapeXml(item.publishedAt)}</pubDate>
      <sparkle:version>${escapeXml(item.build)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXml(item.short)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimumSystemVersion}</sparkle:minimumSystemVersion>
      <description sparkle:format="plain-text">Download this update manually from the fork's GitHub release page.</description>
    </item>
  </channel>
</rss>
`;
}

async function fetchLatestRelease() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5_000);
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "roma-just-talk-appcast",
    "X-GitHub-Api-Version": "2022-11-28",
  };

  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;

  try {
    const response = await fetch(releasesApi, { headers, signal: controller.signal });
    if (!response.ok) throw new Error(`GitHub releases request failed: ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function handler(request, response) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.setHeader("Allow", "GET, HEAD");
    response.statusCode = 405;
    response.end("Method Not Allowed");
    return;
  }

  let release;
  let source = "github";

  try {
    const candidate = await fetchLatestRelease();
    release = normalizeRelease(candidate) ? candidate : fallbackRelease;
    if (release === fallbackRelease) source = "fallback";
  } catch (_error) {
    release = fallbackRelease;
    source = "fallback";
  }

  response.setHeader("Content-Type", "application/rss+xml; charset=utf-8");
  response.setHeader("Cache-Control", "public, s-maxage=900, stale-while-revalidate=86400");
  response.setHeader("X-Appcast-Mode", "informational");
  response.setHeader("X-Appcast-Source", source);
  response.statusCode = 200;
  response.end(request.method === "HEAD" ? undefined : buildAppcast(release));
}

module.exports = handler;
module.exports.buildAppcast = buildAppcast;
module.exports.normalizeRelease = normalizeRelease;
module.exports.releaseVersion = releaseVersion;
