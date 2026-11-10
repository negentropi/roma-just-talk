# Cut, caption, and slow-mo the CI screen recording into a short demo (mp4 + gif).
import subprocess, sys
from PIL import Image, ImageDraw, ImageFont
src, out = sys.argv[1], sys.argv[2]
font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 22)
small = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15)
W = 1024
def caption(path, text, step):
    img = Image.new("RGBA", (W, 64), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rounded_rectangle((120, 4, W - 120, 60), 14, fill=(20, 20, 24, 225))
    d.text((140, 10), step, font=small, fill=(255, 200, 60))
    d.text((140, 28), text, font=font, fill="white")
    img.save(path)
# (src start, src end, speed, caption, step label)
segs = [
    (14.0, 21.3, 1.0, "Mic set to BlackHole 2ch: a virtual input that records silence", "1/5 · setup"),
    (21.3, 22.7, 0.25, "Notice names the mic → Change Mic → System Default (¼ speed)", "2/5 · empty dictation after a ~7 s hold"),
    (22.7, 24.5, 1.0, "Switched instantly, no Settings window", "3/5 · picked System Default"),
    (130.0, 137.5, 1.0, "Next hold uses the new mic (runner default = Apple Virtual Sound Device)", "4/5 · toast confirms the switch"),
    (137.5, 149.0, 1.0, "Still silent → notice names the NEW mic, closes itself after 10 s", "5/5 · second empty dictation"),
]
parts = []
for i, (a, b, speed, text, step) in enumerate(segs):
    cap, part = f"{out}/cap{i}.png", f"{out}/part{i}.mp4"
    caption(cap, text, step)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(a), "-t", str(b - a), "-i", src, "-i", cap,
        "-filter_complex", f"[0:v]fps=30,setpts=PTS/{speed}[v];[v][1:v]overlay=0:96,format=yuv420p",
        "-r", "30", "-an", "-c:v", "libx264", "-crf", "20", part], check=True)
    parts.append(part)
open(f"{out}/list.txt", "w").write("".join(f"file '{p}'\n" for p in parts))
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", f"{out}/list.txt",
    "-c", "copy", "-movflags", "+faststart", f"{out}/pr37-mic-notice.mp4"], check=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f"{out}/pr37-mic-notice.mp4", "-vf",
    "fps=12,scale=768:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer",
    f"{out}/pr37-mic-notice.gif"], check=True)
