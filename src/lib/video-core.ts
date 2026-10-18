const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

export const ASPECTS = { "16:9": [1280, 720], "9:16": [720, 1280], "1:1": [1024, 1024] } as const;
export type Aspect = keyof typeof ASPECTS;
export type Slide = { assetId: string; caption?: string };
export type SlideshowInput = { slides: Slide[]; aspect: Aspect; secondsPerSlide: number; kenBurns: boolean };

export function validateSlideshow(b: unknown): { value?: SlideshowInput; errors: string[] } {
  const errors: string[] = [];
  if (!isRecord(b)) return { errors: ["body must be an object"] };
  const slides = b.slides;
  if (!Array.isArray(slides) || slides.length < 1 || slides.length > 12) errors.push("slides: provide 1 to 12 slides");
  const out: Slide[] = [];
  if (Array.isArray(slides)) {
    slides.forEach((s, i) => {
      if (!isRecord(s) || typeof s.assetId !== "string") return void errors.push(`slides[${i}]: assetId is required`);
      if (s.caption !== undefined && (typeof s.caption !== "string" || s.caption.length > 200)) return void errors.push(`slides[${i}]: caption must be text up to 200 characters`);
      out.push({ assetId: s.assetId, caption: typeof s.caption === "string" && s.caption.trim() ? s.caption.trim() : undefined });
    });
  }
  const aspect = (b.aspect ?? "16:9") as string;
  if (!(aspect in ASPECTS)) errors.push('aspect: must be "16:9", "9:16" or "1:1"');
  const sec = b.secondsPerSlide === undefined ? 3 : Number(b.secondsPerSlide);
  if (!(sec >= 1 && sec <= 10)) errors.push("secondsPerSlide: must be between 1 and 10");
  if (b.kenBurns !== undefined && typeof b.kenBurns !== "boolean") errors.push("kenBurns: must be true or false");
  if (errors.length) return { errors };
  return { value: { slides: out, aspect: aspect as Aspect, secondsPerSlide: sec, kenBurns: b.kenBurns !== false }, errors };
}

/** Wraps text to roughly `max` characters per line, breaking at spaces. */
export function wrapCaption(text: string, max: number): string {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let cur = "";
  for (const w of words) {
    if (cur && (cur + " " + w).length > max) {
      lines.push(cur);
      cur = w;
    } else cur = cur ? `${cur} ${w}` : w;
  }
  if (cur) lines.push(cur);
  return lines.slice(0, 4).join("\n");
}


export const LANGS = { ar: "Arabic", en: "English", fr: "French" } as const;
export type Lang = keyof typeof LANGS;

export type ProductVideoInput = {
  productName: string;
  description: string;
  language: Lang;
  photoAssetIds: string[];
  generateImages: number;
  aspect: Aspect;
  secondsPerSlide: number;
};

export function validateProductVideo(b: unknown): { value?: ProductVideoInput; errors: string[] } {
  const errors: string[] = [];
  if (!isRecord(b)) return { errors: ["body must be an object"] };
  const name = typeof b.productName === "string" ? b.productName.trim() : "";
  if (!name || name.length > 120) errors.push("productName: required, up to 120 characters");
  const description = typeof b.description === "string" ? b.description.trim() : "";
  if (description.length > 2000) errors.push("description: up to 2000 characters");
  const language = (b.language ?? "en") as string;
  if (!(language in LANGS)) errors.push('language: must be "ar", "en" or "fr"');
  const photos = b.photoAssetIds ?? [];
  if (!Array.isArray(photos) || photos.length > 10 || photos.some((p) => typeof p !== "string")) errors.push("photoAssetIds: up to 10 file ids");
  const gen = b.generateImages === undefined ? 0 : Number(b.generateImages);
  if (!Number.isInteger(gen) || gen < 0 || gen > 4) errors.push("generateImages: whole number from 0 to 4");
  const aspect = (b.aspect ?? "16:9") as string;
  if (!(aspect in ASPECTS)) errors.push('aspect: must be "16:9", "9:16" or "1:1"');
  const sec = b.secondsPerSlide === undefined ? 3 : Number(b.secondsPerSlide);
  if (!(sec >= 1 && sec <= 10)) errors.push("secondsPerSlide: between 1 and 10");
  if (!errors.length && (photos as string[]).length + gen < 1) errors.push("Add at least one product photo or ask for generated images");
  if (errors.length) return { errors };
  return { value: { productName: name, description, language: language as Lang, photoAssetIds: photos as string[], generateImages: gen, aspect: aspect as Aspect, secondsPerSlide: sec }, errors };
}

