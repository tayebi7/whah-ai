/** Sorts a provider's model ids into chat / image / video / other, and suggests sensible defaults. Pure, used by the settings form. */
export type ModelGroups = { chat: string[]; image: string[]; video: string[]; other: string[] };

const OTHER = /(embed|rerank|moderation|whisper|tts|transcribe|speech|audio|asr|guard|aqa|bge-|e5-|clip|ocr|safety|realtime)/i;
const VIDEO = /(^|[-_/.])(sora|veo|kling|runway|gen-?[34]|wan|hunyuan-?video|ltx|cogvideo|mochi|pika|luma|hailuo|seedance|video)/i;
const IMAGE = /(dall-?e|gpt-image|imagen|flux|stable-?diffusion|sdxl|sd3|midjourney|ideogram|recraft|playground|kolors|seedream|nano-?banana|(^|[-_/.])image($|[-_/.]))/i;

export function classifyModels(ids: string[]): ModelGroups {
  const g: ModelGroups = { chat: [], image: [], video: [], other: [] };
  for (const id of ids) {
    if (VIDEO.test(id)) g.video.push(id);
    else if (IMAGE.test(id)) g.image.push(id);
    else if (OTHER.test(id)) g.other.push(id);
    else g.chat.push(id);
  }
  return g;
}

const RANK = [/gpt-4o-mini/i, /flash(?!-(image|lite))/i, /haiku/i, /mini/i, /chat/i, /instruct/i, /sonnet/i, /llama-?3\.[13]/i, /deepseek/i, /gpt-/i, /gemini/i, /claude/i];
const UNSTABLE = /(preview|exp|experimental|beta|-\d{2}-\d{2}|-\d{4}-\d{2}-\d{2}|\d{8})/i;

const score = (id: string) => {
  const i = RANK.findIndex((r) => r.test(id));
  return (i < 0 ? 99 : i) + (UNSTABLE.test(id) ? 0.5 : 0);
};
/** Prefers fast, current, stable names: lowest rank, then the shortest (the alias rather than a dated copy). */
const version = (id: string) => {
  const m = /(\d+(?:\.\d+)?)/.exec(id.replace(/^models\//, ""));
  return m ? Number(m[1]) : 0;
};
/** Within the same family it takes the NEWEST version (old ones are retired for new accounts), then the shortest alias. */
export const bestOf = (ids: string[]): string => [...ids].sort((a, b) => Math.floor(score(a)) - Math.floor(score(b)) || version(b) - version(a) || score(a) - score(b) || a.length - b.length || a.localeCompare(b))[0] ?? "";

const VISION = /(gpt-4o|gpt-4\.1|gpt-5|gemini|claude|vision|(^|[-_/])vl([-_/]|$)|llava|pixtral|minicpm-v|gemma-?3)/i;
export const looksVision = (id: string) => VISION.test(id);

export type Suggestion = { model: string; imageModel: string; videoModel: string; vision: boolean };
export function suggest(g: ModelGroups): Suggestion {
  const model = bestOf(g.chat);
  return { model, imageModel: bestOf(g.image), videoModel: bestOf(g.video), vision: !!model && looksVision(model) };
}
