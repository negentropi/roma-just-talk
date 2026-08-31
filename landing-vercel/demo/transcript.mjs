export function cleanTranscriptText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

export function joinTranscriptParts(parts) {
  const joined = [];
  for (const value of parts) {
    const part = cleanTranscriptText(value);
    if (!part) continue;
    const folded = (text) => text.toLocaleLowerCase().replace(/[^\p{L}\p{N}']/gu, "");
    const currentText = joined.join(" ");
    const currentFolded = folded(currentText);
    const partFolded = folded(part);
    const currentLower = currentText.toLocaleLowerCase();
    const partLower = part.toLocaleLowerCase();
    const isCjkPrefix = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(currentText)
      && partFolded.startsWith(currentFolded);
    if (currentFolded && (partLower.startsWith(`${currentLower} `) || isCjkPrefix)) {
      joined.splice(0, joined.length, ...part.split(" "));
      continue;
    }
    if (partFolded && currentFolded.endsWith(partFolded)) continue;
    const words = part.split(" ");
    const comparable = (word) => folded(word);
    const normalizedJoined = joined.map(comparable);
    const normalizedWords = words.map(comparable);
    let overlap = Math.min(joined.length, words.length);
    while (overlap > 0) {
      const previousTail = normalizedJoined.slice(-overlap);
      const nextHead = normalizedWords.slice(0, overlap);
      if (previousTail.every((word, index) => word === nextHead[index])) break;
      overlap -= 1;
    }
    joined.push(...words.slice(overlap));
  }
  return joined.join(" ").trim();
}
