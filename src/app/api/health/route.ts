import { encryptSecret } from "../../../lib/crypto";
import { hasTool } from "../../../lib/exec";
import { guard, json } from "../../../lib/http";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Which optional server features are usable right now. */
export async function GET(req: Request) {
  const g = guard(req, { bucket: "health", limit: 120 });
  if (g) return g;
  let encryption = true;
  try {
    encryptSecret("probe");
  } catch {
    encryption = false;
  }
  const tools = Object.fromEntries(["ffmpeg", "ffprobe", "pandoc", "soffice", "pdftotext", "pdftoppm", "tesseract", "zip", "unzip"].map((t) => [t, hasTool(t)]));
  return json(200, {
    tools,
    features: {
      providerStorage: encryption,
      slideshowVideo: tools.ffmpeg && tools.ffprobe,
      documentConversion: tools.soffice && tools.pandoc,
      bookExport: tools.pandoc,
      bookPdf: tools.pandoc && tools.soffice,
      ocr: tools.tesseract,
    },
    tokenConfigured: !!process.env.WAHA_ACCESS_TOKEN,
  });
}
