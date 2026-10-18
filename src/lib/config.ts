import path from "node:path";

const MB = 1024 * 1024;
const num = (v: string | undefined, fallback: number) => (v !== undefined && v !== "" && Number.isFinite(Number(v)) ? Number(v) : fallback);

/** Where uploads, jobs and the encrypted provider store live. */
export const dataDir = () => path.resolve(process.env.WAHA_DATA_DIR || path.join(process.cwd(), "data"));
export const allowLocal = () => process.env.WAHA_ALLOW_LOCAL === "true";
export const maxUploadBytes = () => Math.max(1, num(process.env.WAHA_MAX_UPLOAD_MB, 25)) * MB;
/** Cap for files WE create or download on the user's behalf (images, videos, converted documents). */
export const maxGeneratedBytes = () => Math.max(1, num(process.env.WAHA_MAX_GENERATED_MB, 200)) * MB;
/** Stored files older than this are deleted automatically. 0 keeps everything until deleted by hand. */
export const retentionDays = () => Math.max(0, num(process.env.WAHA_RETENTION_DAYS, 0));
