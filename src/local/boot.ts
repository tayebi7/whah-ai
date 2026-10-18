import { installLocalApi } from "./api";

/** Imported once by the page: in the phone build (NEXT_PUBLIC_WAHA_LOCAL=1) the app answers its own /api calls. */
if (typeof window !== "undefined" && process.env.NEXT_PUBLIC_WAHA_LOCAL === "1") installLocalApi();
