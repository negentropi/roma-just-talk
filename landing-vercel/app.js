const repoUrl = "https://github.com/happyf-weallareeuropean/roma-just-talk";
const repoBranch = "without/no-adhoc-macos-tcc";
const latestReleaseUrl = `${repoUrl}/releases/latest`;
const releasesApi = "https://api.github.com/repos/happyf-weallareeuropean/roma-just-talk/releases";
const latestReleaseApi = `${releasesApi}/latest`;
const releasesPageUrl = `${repoUrl}/releases`;
const rawBase = `https://raw.githubusercontent.com/happyf-weallareeuropean/roma-just-talk/${repoBranch}/`;
const readmeMarkdownUrl = `${rawBase}README.md`;
const discordId = "freedom_uuuuuuuuuuuuuuunion.p.f";
const waitlistEmail = "happyfumd@icloud.com";
const fetchTimeoutMs = 8000;

function detectOs() {
  const ua = navigator.userAgent.toLowerCase();
  const platform = (navigator.platform || "").toLowerCase();
  if (ua.includes("windows") || platform.includes("win")) return "windows";
  if (ua.includes("mac os") || platform.includes("mac")) return "mac";
  return "other";
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function repoContentUrl(url, mode) {
  if (/^(https?:|mailto:|#)/.test(url)) return url;
  const cleanUrl = url.replace(/^.\//, "");
  return mode === "raw" ? `${rawBase}${cleanUrl}` : `${repoUrl}/blob/${repoBranch}/${cleanUrl}`;
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), fetchTimeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    window.clearTimeout(timeout);
  }
}

async function resolveMacDownloadUrl() {
  try {
    const response = await fetchWithTimeout(latestReleaseApi, {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(`release fetch failed: ${response.status}`);
    const release = await response.json();
    const appAsset = release.assets?.find((asset) => {
      return asset.name?.endsWith(".app.zip") && asset.browser_download_url;
    });
    return appAsset?.browser_download_url || latestReleaseUrl;
  } catch (_error) {
    return latestReleaseUrl;
  }
}

async function downloadMac(event) {
  event?.preventDefault();
  window.location.href = await resolveMacDownloadUrl();
}

function inlineMarkdown(value) {
  return escapeHtml(value)
    .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_match, alt, url) => {
      return `<img src="${repoContentUrl(url, "raw")}" alt="${alt}" loading="lazy" />`;
    })
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_match, label, url) => {
      return `<a href="${repoContentUrl(url, "blob")}" target="_blank" rel="noreferrer">${label}</a>`;
    })
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>");
}

function markdownToHtml(markdown) {
  const lines = markdown.split("\n");
  const html = [];
  let listOpen = false;
  let orderedListOpen = false;
  let codeOpen = false;
  let skipHtmlBlock = false;

  const closeLists = () => {
    if (listOpen) {
      html.push("</ul>");
      listOpen = false;
    }
    if (orderedListOpen) {
      html.push("</ol>");
      orderedListOpen = false;
    }
  };

  lines.forEach((line) => {
    const trimmed = line.trim();
    if (trimmed.startsWith("<div")) {
      skipHtmlBlock = true;
      return;
    }
    if (skipHtmlBlock) {
      if (trimmed.startsWith("</div>")) skipHtmlBlock = false;
      return;
    }
    if (trimmed.startsWith("<") && trimmed.endsWith(">")) return;
    if (line.startsWith("```")) {
      closeLists();
      html.push(codeOpen ? "</code></pre>" : "<pre><code>");
      codeOpen = !codeOpen;
      return;
    }
    if (codeOpen) {
      html.push(`${escapeHtml(line)}\n`);
      return;
    }
    if (!trimmed) {
      closeLists();
      return;
    }
    if (line === "---") {
      closeLists();
      html.push("<hr />");
      return;
    }
    const heading = /^(#{1,4})\s+(.+)$/.exec(line);
    if (heading) {
      closeLists();
      const level = heading[1].length + 1;
      html.push(`<h${level}>${inlineMarkdown(heading[2])}</h${level}>`);
      return;
    }
    const bullet = /^[-*]\s+(.+)$/.exec(line);
    if (bullet) {
      if (!listOpen) {
        if (orderedListOpen) {
          html.push("</ol>");
          orderedListOpen = false;
        }
        html.push("<ul>");
        listOpen = true;
      }
      html.push(`<li>${inlineMarkdown(bullet[1])}</li>`);
      return;
    }
    const ordered = /^\d+\.\s+(.+)$/.exec(line);
    if (ordered) {
      if (!orderedListOpen) {
        if (listOpen) {
          html.push("</ul>");
          listOpen = false;
        }
        html.push("<ol>");
        orderedListOpen = true;
      }
      html.push(`<li>${inlineMarkdown(ordered[1])}</li>`);
      return;
    }
    closeLists();
    html.push(`<p>${inlineMarkdown(line)}</p>`);
  });

  closeLists();
  if (codeOpen) html.push("</code></pre>");
  return html.join("");
}

function setWindowsMode() {
  document.getElementById("mac-actions")?.classList.add("hidden");
  document.getElementById("waitlist-form")?.classList.remove("hidden");
  requestAnimationFrame(() => document.getElementById("waitlist-email")?.focus());
}

async function submitWaitlist(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const state = document.getElementById("waitlist-state");
  const email = document.getElementById("waitlist-email");
  if (!email.value.trim()) {
    state.textContent = "type an email first";
    email.focus();
    return;
  }

  const subject = encodeURIComponent("Roma Just Talk Windows waitlist");
  const body = encodeURIComponent(`Add me to the Windows waitlist: ${email.value.trim()}`);
  state.textContent = "opening email draft. send it to join.";
  window.location.href = `mailto:${waitlistEmail}?subject=${subject}&body=${body}`;
  form.reset();
}

function toggleContact() {
  document.getElementById("contact-panel")?.classList.toggle("hidden");
}

async function copyDiscord() {
  const state = document.getElementById("contact-state");
  if (!state) return;
  try {
    await navigator.clipboard.writeText(discordId);
    state.textContent = "saved my discord id in clipboard. ⌘V to paste.";
  } catch (_error) {
    state.textContent = `copy this discord id: ${discordId}`;
  }
  window.open("https://discord.com/channels/@me/", "_blank", "noopener,noreferrer");
}

function formatReleaseDate(value) {
  if (!value) return "release date pending";
  return new Intl.DateTimeFormat("en", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(value));
}

function releaseNotesToHtml(release) {
  const body = release.body?.trim();
  if (!body) return "<p>No release notes yet.</p>";
  const lines = body.split("\n");
  const firstLine = lines[0]?.trim() || "";
  const startsWithReleaseTitle = /^#{1,4}\s+/.test(firstLine) && firstLine.includes(release.tag_name);
  const notes = startsWithReleaseTitle ? lines.slice(1).join("\n").trim() : body;
  return markdownToHtml(notes || body);
}

function releaseAssetLinks(release) {
  const links = (release.assets || [])
    .filter((asset) => asset.browser_download_url)
    .slice(0, 3)
    .map((asset) => {
      const isAppZip = asset.name?.endsWith(".app.zip");
      const label = isAppZip ? "download app" : `download ${asset.name || "asset"}`;
      return `<a class="release-link release-download" href="${escapeHtml(asset.browser_download_url)}">${escapeHtml(label)}</a>`;
    });

  links.unshift(`<a class="release-link" href="${escapeHtml(release.html_url || releasesPageUrl)}">view release</a>`);
  return `<div class="release-actions">${links.join("")}</div>`;
}

function releaseAnchorId(release, index) {
  const label = release.tag_name || release.name || `release-${index + 1}`;
  const slug = label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `release-${slug || index + 1}`;
}

function releaseJumpToHtml(releases) {
  const links = releases
    .map((release, index) => {
      const label = release.tag_name || release.name || `release ${index + 1}`;
      return `<a href="#${releaseAnchorId(release, index)}">${escapeHtml(label)}</a>`;
    })
    .join("");
  return `<nav class="release-jump" aria-label="Jump to release">${links}</nav>`;
}

function releaseToHtml(release, index) {
  const title = release.name || release.tag_name || `release ${index + 1}`;
  const badge = release.prerelease ? "pre-release" : "release";
  return `
    <section class="release-entry" id="${releaseAnchorId(release, index)}">
      <div class="release-heading">
        <h3>${escapeHtml(title)}</h3>
        <div class="release-meta">
          <span>${escapeHtml(formatReleaseDate(release.published_at || release.created_at))}</span>
          <span>${escapeHtml(release.tag_name || badge)}</span>
          <span>${badge}</span>
        </div>
      </div>
      <div class="release-notes">
        ${releaseNotesToHtml(release)}
      </div>
      ${releaseAssetLinks(release)}
    </section>
  `;
}

async function loadReadme() {
  const target = document.getElementById("readme-content");
  if (!target) return;

  try {
    const response = await fetchWithTimeout(readmeMarkdownUrl);
    if (!response.ok) throw new Error(`README fetch failed: ${response.status}`);
    target.innerHTML = markdownToHtml(await response.text());
  } catch (_error) {
    target.innerHTML = `<p>readme failed to load. open the <a href="${repoUrl}#readme" target="_blank" rel="noreferrer">github readme</a>.</p>`;
  }
}

async function loadChangelog() {
  const target = document.getElementById("changelog-content");
  if (!target) return;

  try {
    const response = await fetchWithTimeout(releasesApi, {
      headers: { Accept: "application/vnd.github+json" },
      cache: "no-store",
    });
    if (!response.ok) throw new Error(`releases fetch failed: ${response.status}`);
    const releases = await response.json();
    if (!Array.isArray(releases)) throw new Error("releases response was not a list");
    const visibleReleases = releases.filter((release) => !release.draft).slice(0, 8);
    if (!visibleReleases.length) throw new Error("no published releases");
    target.innerHTML = `${releaseJumpToHtml(visibleReleases)}<div class="release-list">${visibleReleases.map(releaseToHtml).join("")}</div>`;
  } catch (_error) {
    target.innerHTML = `<p>changelog could not reach github releases right now. open <a href="${releasesPageUrl}" target="_blank" rel="noreferrer">github releases</a>.</p>`;
  }
}

document.addEventListener("DOMContentLoaded", () => {
  if (detectOs() === "windows") setWindowsMode();
  document.getElementById("waitlist-form")?.addEventListener("submit", submitWaitlist);
  document.getElementById("talk-button")?.addEventListener("click", toggleContact);
  document.getElementById("discord-button")?.addEventListener("click", copyDiscord);
  document.getElementById("download-button")?.addEventListener("click", downloadMac);
  loadReadme();
  loadChangelog();
});

document.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  const hasHeroShortcuts = document.getElementById("download-button") || document.getElementById("talk-button");
  if (!hasHeroShortcuts) return;

  if (event.key === "Enter" && event.shiftKey) {
    event.preventDefault();
    window.open(repoUrl, "_blank", "noopener,noreferrer");
    return;
  }
  if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    toggleContact();
    return;
  }
  if (event.key === "Enter") {
    const waitlist = document.getElementById("waitlist-form");
    if (waitlist && !waitlist.classList.contains("hidden")) return;
    event.preventDefault();
    void downloadMac();
    return;
  }
  if (key === "a") window.open("https://x.com/Hft_freedom", "_blank", "noopener,noreferrer");
  if (key === "s") copyDiscord();
  if (key === "d") window.open("https://t.me/felixorder", "_blank", "noopener,noreferrer");
});
