import { promises as fs } from "node:fs";
import path from "node:path";
import { type Asset, readAssetData, saveAsset } from "./assets";
import { run, semaphore, withTempDir } from "./exec";
import type { JobContext } from "./jobs";
import { ASPECTS, wrapCaption, type SlideshowInput } from "./video-core";

export * from "./video-core";

const FPS = 25;
const heavy = semaphore(1);

/** A font that has Arabic and Latin glyphs. Override with WAHA_FONT_FILE. */
const FONT_CANDIDATES = [
  "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  "/usr/share/fonts/dejavu/DejaVuSans.ttf",
  "/Library/Fonts/Arial Unicode.ttf",
  "C:/Windows/Fonts/arial.ttf",
];
export async function findFont(): Promise<string | undefined> {
  const env = process.env.WAHA_FONT_FILE;
  for (const f of env ? [env, ...FONT_CANDIDATES] : FONT_CANDIDATES) {
    try {
      await fs.access(f);
      return f;
    } catch {
      /* next */
    }
  }
  return undefined;
}

const esc = (p: string) => p.replace(/\\/g, "/").replace(/:/g, "\\:").replace(/'/g, "\\'");

/** Renders a captioned slideshow as an H.264 MP4 (ffmpeg). Captions use the font from findFont(). */
export async function renderSlideshow(input: SlideshowInput, ctx: JobContext, o: { warn?: (m: string) => void } = {}): Promise<Asset> {
  const [W, H] = ASPECTS[input.aspect];
  const font = await findFont();
  if (!font && input.slides.some((s) => s.caption)) (o.warn ?? ctx.warn)("No font with Arabic/Latin glyphs was found, so captions were skipped. Set WAHA_FONT_FILE to a .ttf file.");

  return heavy(() =>
    withTempDir(async (dir) => {
      const segs: string[] = [];
      const n = input.slides.length;
      for (let i = 0; i < n; i++) {
        if (ctx.signal.aborted) throw new Error("cancelled");
        const s = input.slides[i];
        let loaded;
        try {
          loaded = await readAssetData(s.assetId);
        } catch {
          throw new Error(`Slide ${i + 1}: the image was not found`);
        }
        if (loaded.asset.kind !== "image") throw new Error(`Slide ${i + 1}: the file is not an image`);
        const img = path.join(dir, `img${i}.${loaded.asset.ext === "jpeg" ? "jpg" : loaded.asset.ext}`);
        await fs.writeFile(img, loaded.data);
        ctx.setProgress(5 + (85 * i) / n, `Rendering slide ${i + 1} of ${n}`);

        const frames = Math.round(input.secondsPerSlide * FPS);
        const filters: string[] = [];
        if (input.kenBurns) {
          filters.push(`scale=${W * 2}:${H * 2}:force_original_aspect_ratio=increase`, `crop=${W * 2}:${H * 2}`, `zoompan=z='min(zoom+0.0012,1.2)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=${frames}:s=${W}x${H}:fps=${FPS}`);
        } else {
          filters.push(`scale=${W}:${H}:force_original_aspect_ratio=increase`, `crop=${W}:${H}`);
        }
        if (s.caption && font) {
          const size = Math.round(H / (input.aspect === "9:16" ? 26 : 20));
          const txt = path.join(dir, `cap${i}.txt`);
          await fs.writeFile(txt, wrapCaption(s.caption, Math.floor(W / (size * 0.62))), "utf8");
          filters.push(`drawtext=fontfile='${esc(font)}':textfile='${esc(txt)}':fontsize=${size}:fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=${Math.round(size / 2)}:line_spacing=8:x=(w-text_w)/2:y=h-text_h-${Math.round(H * 0.08)}`);
        }
        filters.push("format=yuv420p");
        const seg = path.join(dir, `seg${i}.mp4`);
        await run(
          "ffmpeg",
          ["-v", "error", "-y", ...(input.kenBurns ? [] : ["-loop", "1"]), "-i", img, "-vf", filters.join(","), "-r", String(FPS), "-frames:v", String(frames), "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", "-an", seg],
          { timeoutMs: 180_000, home: dir, signal: ctx.signal },
        );
        segs.push(seg);
      }
      ctx.setProgress(92, "Joining slides");
      await fs.writeFile(path.join(dir, "list.txt"), segs.map((s) => `file '${path.basename(s)}'`).join("\n"));
      const out = path.join(dir, "out.mp4");
      await run("ffmpeg", ["-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", path.join(dir, "list.txt"), "-c", "copy", "-movflags", "+faststart", out], { timeoutMs: 120_000, home: dir, cwd: dir, signal: ctx.signal });
      return saveAsset({ name: `slideshow-${Date.now().toString(36)}.mp4`, data: await fs.readFile(out), origin: "generated" });
    }),
  );
}
