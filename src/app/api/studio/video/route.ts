import { fail } from "../../../../lib/api-errors";
import { hasTool } from "../../../../lib/exec";
import { guard, isRecord, json, readJson } from "../../../../lib/http";
import { startJob } from "../../../../lib/jobs";
import { runProductVideo, validateProductVideo } from "../../../../lib/product-video";
import { capabilitiesOf, loadAllProviders } from "../../../../lib/providers";
import { generateProviderVideo } from "../../../../lib/video-provider";
import { renderSlideshow, validateSlideshow } from "../../../../lib/video-slideshow";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Starts a background video job and returns it immediately (poll /api/jobs/:id).
 *  mode "slideshow": captioned slideshow from stored images (needs ffmpeg)
 *  mode "product":   product photos (+AI images, AI captions) -> video (needs ffmpeg)
 *  mode "provider":  text/image -> video through a configured video provider
 */
export async function POST(req: Request) {
  const g = guard(req, { bucket: "video", limit: 12 });
  if (g) return g;
  const body = await readJson(req);
  if (!body.ok) return body.res;
  const b = body.value;
  if (!isRecord(b)) return json(400, { error: "Invalid request body" });
  const mode = b.mode;

  try {
    if (mode === "slideshow" || mode === "product") {
      if (!hasTool("ffmpeg") || !hasTool("ffprobe")) return json(501, { error: '"ffmpeg" is not installed on the server, so this video mode is unavailable' });
    }
    if (mode === "slideshow") {
      const v = validateSlideshow(b);
      if (!v.value) return json(400, { error: "Invalid request", details: v.errors });
      const input = v.value;
      return json(202, { job: await startJob("video", "Slideshow video", async (ctx) => [(await renderSlideshow(input, ctx)).id]) });
    }
    if (mode === "product") {
      const v = validateProductVideo(b);
      if (!v.value) return json(400, { error: "Invalid request", details: v.errors });
      const input = v.value;
      const { providers } = await loadAllProviders();
      return json(202, { job: await startJob("product-video", input.productName, (ctx) => runProductVideo(input, providers, ctx)) });
    }
    if (mode === "provider") {
      if (typeof b.prompt !== "string" || !b.prompt.trim() || b.prompt.length > 4000) return json(400, { error: "prompt is required (max 4000 characters)" });
      const { providers } = await loadAllProviders();
      const p = providers.find((x) => x.enabled && capabilitiesOf(x).video && (!b.providerId || x.id === b.providerId));
      if (!p) return json(400, { error: "No video provider is configured. Add a provider with a video model and video API settings." });
      const seconds = b.seconds === undefined ? undefined : Number(b.seconds);
      if (seconds !== undefined && !(seconds >= 1 && seconds <= 60)) return json(400, { error: "seconds must be between 1 and 60" });
      const input = { prompt: b.prompt.trim(), imageAssetId: typeof b.imageAssetId === "string" ? b.imageAssetId : undefined, seconds, aspect: typeof b.aspect === "string" && ["16:9", "9:16", "1:1"].includes(b.aspect) ? b.aspect : undefined };
      return json(202, { job: await startJob("video", `${p.name}: ${input.prompt.slice(0, 60)}`, async (ctx) => [(await generateProviderVideo(p, input, ctx)).id]) });
    }
    if (mode === "auto") {
      if (typeof b.prompt !== "string" || !b.prompt.trim() || b.prompt.length > 4000) return json(400, { error: "prompt is required (max 4000 characters)" });
      const prompt = b.prompt.trim();
      const aspect = typeof b.aspect === "string" && ["16:9", "9:16", "1:1"].includes(b.aspect) ? (b.aspect as "16:9" | "9:16" | "1:1") : "16:9";
      const language = b.language === "en" || b.language === "fr" ? b.language : "ar";
      const { providers } = await loadAllProviders();
      const videoPs = providers.filter((x) => x.enabled && capabilitiesOf(x).video);
      const canStoryboard = hasTool("ffmpeg") && hasTool("ffprobe") && providers.some((x) => x.enabled && capabilitiesOf(x).image);
      if (videoPs.length === 0 && !canStoryboard) return json(400, { error: "No video model is configured and no image model is available for a storyboard video. Add one in Settings." });
      return json(202, {
        job: await startJob("video", prompt.slice(0, 60), async (ctx) => {
          const problems: string[] = [];
          for (const p of videoPs) {
            try {
              return [(await generateProviderVideo(p, { prompt, aspect }, ctx)).id];
            } catch (e) {
              if (ctx.signal.aborted) throw e;
              problems.push(`${p.name}: ${(e as Error).message}`);
              ctx.warn(`${p.name}: ${(e as Error).message}`);
            }
          }
          if (!canStoryboard) throw new Error(problems.join(" | ") || "Video generation failed");
          if (problems.length) ctx.warn("Falling back to an AI storyboard video");
          return runProductVideo({ productName: prompt.slice(0, 120), description: prompt.slice(0, 2000), language, photoAssetIds: [], generateImages: 4, aspect, secondsPerSlide: 3, scene: true }, providers, ctx);
        }),
      });
    }
    return json(400, { error: 'mode must be "slideshow", "product", "provider" or "auto"' });
  } catch (e) {
    return fail(e);
  }
}
