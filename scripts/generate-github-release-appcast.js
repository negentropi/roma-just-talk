#!/usr/bin/env node

const fs = require("node:fs");

const repository = "negentropi/roma-just-talk";
const releasesPage = `https://github.com/${repository}/releases`;
const releaseURLPrefix = `${releasesPage}/tag/`;
const archiveName = "roma.just.talk.app.zip";
const minimumSystemVersion = "14.4";

function escapeXML(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&apos;",
  })[character]);
}

function releaseVersion(tagName) {
  const match = /^v?(\d+)\.(\d+)(?:\.(\d+))?$/.exec(tagName || "");
  if (!match) return null;

  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = match[3] === undefined ? null : Number(match[3]);
  if (!Number.isSafeInteger(major) || !Number.isSafeInteger(minor) || minor > 99) return null;
  if (patch !== null && (!Number.isSafeInteger(patch) || patch > 99)) return null;

  return {
    // Preserve historical builds: 195 < 195.1 < 196 in Sparkle's numeric comparison.
    build: `${major * 100 + minor}${patch === null ? "" : `.${patch}`}`,
    short: `${major}.${minor}${patch === null ? "" : `.${patch}`}`,
  };
}

function normalizedRelease(release) {
  if (!release || release.draft || release.prerelease) {
    throw new Error("Release must be a published stable release");
  }

  const version = releaseVersion(release.tag_name);
  if (!version) throw new Error(`Unsupported release tag: ${release.tag_name || "(missing)"}`);

  const releaseURL = typeof release.html_url === "string" ? release.html_url : "";
  if (!releaseURL.startsWith(releaseURLPrefix)) {
    throw new Error(`Release URL must belong to ${repository}`);
  }

  const publishedAt = new Date(release.published_at);
  if (Number.isNaN(publishedAt.getTime())) throw new Error("Release published_at is invalid");

  const hasArchive = release.assets?.some((asset) => {
    return asset.name === archiveName && (!asset.state || asset.state === "uploaded");
  });
  if (!hasArchive) throw new Error(`Release is missing ${archiveName}`);

  return {
    ...version,
    releaseURL,
    publishedAt: publishedAt.toUTCString(),
    notes: release.body?.trim() || "See the GitHub release page for details.",
  };
}

function buildAppcast(release) {
  return renderAppcast(normalizedRelease(release), minimumSystemVersion);
}

function buildDraftAppcast(release, intent) {
  if (!release || release.draft !== true || release.prerelease !== false || release.published_at != null) {
    throw new Error("Release must be an unpublished stable draft");
  }
  const version = releaseVersion(release.tag_name);
  if (!version || intent.appVersion !== version.short || intent.appBuild !== version.build) {
    throw new Error("Draft tag and verified app versions differ");
  }
  if (!/^\d+\.\d+(?:\.\d+)?$/.test(intent.minimumSystemVersion || "")) {
    throw new Error("Verified minimum system version is invalid");
  }
  if (typeof intent.publicationTime !== "string" || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/.test(intent.publicationTime)) {
    throw new Error("Draft publication time is invalid");
  }
  const publicationTime = new Date(intent.publicationTime);
  if (Number.isNaN(publicationTime.getTime()) || publicationTime.toISOString() !== intent.publicationTime.replace("Z", ".000Z")) {
    throw new Error("Draft publication time is invalid");
  }
  const archives = release.assets?.filter(asset => asset.name === archiveName && asset.state === "uploaded") || [];
  if (archives.length !== 1) throw new Error(`Draft must contain one uploaded ${archiveName}`);
  return renderAppcast({
    ...version,
    releaseURL: `${releaseURLPrefix}${release.tag_name}`,
    publishedAt: publicationTime.toUTCString(),
    notes: release.body?.trim() || "See the GitHub release page for details.",
  }, intent.minimumSystemVersion);
}

function renderAppcast(item, minimum) {

  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>roma just talk updates</title>
    <link>${releasesPage}</link>
    <description>Updates published from the Roma Just Talk GitHub repository.</description>
    <language>en</language>
    <item>
      <title>roma just talk ${escapeXML(item.short)}</title>
      <link>${escapeXML(item.releaseURL)}</link>
      <pubDate>${escapeXML(item.publishedAt)}</pubDate>
      <sparkle:version>${escapeXML(item.build)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXML(item.short)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escapeXML(minimum)}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown">${escapeXML(item.notes)}</description>
    </item>
  </channel>
</rss>
`;
}

function releaseFromEventFile(eventPath) {
  const payload = JSON.parse(fs.readFileSync(eventPath, "utf8"));
  return payload.release || payload;
}

if (require.main === module) {
  try {
    const eventPath = process.argv[2] || process.env.GITHUB_EVENT_PATH;
    if (!eventPath) throw new Error("Pass a GitHub release event JSON file");
    const release = releaseFromEventFile(eventPath);
    if (process.argv[3] === "--draft-intent" && process.argv.length === 5) {
      process.stdout.write(buildDraftAppcast(release, JSON.parse(fs.readFileSync(process.argv[4], "utf8"))));
    } else {
      if (process.argv.length > 3) throw new Error("Unsupported appcast arguments");
      process.stdout.write(buildAppcast(release));
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  buildAppcast,
  buildDraftAppcast,
  normalizedRelease,
  releaseFromEventFile,
  releaseVersion,
};
