import { Capacitor, registerPlugin } from "@capacitor/core";

type FsPlugin = { writeFile(o: { path: string; data: string; directory: string; recursive?: boolean }): Promise<{ uri: string }> };
type SharePlugin = { share(o: { title?: string; url?: string; dialogTitle?: string }): Promise<unknown> };

function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

/**
 * Gives the user a file. In a browser this is a normal download. In the Android app a WebView cannot download
 * blobs, so the file is written to the app's cache and handed to the Android share sheet ("Save to Files",
 * Drive, WhatsApp, ...).
 */
export async function saveBlobAs(blob: Blob, name: string): Promise<void> {
  if (Capacitor.isNativePlatform()) {
    const Filesystem = registerPlugin<FsPlugin>("Filesystem");
    const Share = registerPlugin<SharePlugin>("Share");
    const safe = name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_").slice(0, 100) || "file";
    const { uri } = await Filesystem.writeFile({ path: `waha/${Date.now().toString(36)}-${safe}`, data: toBase64(new Uint8Array(await blob.arrayBuffer())), directory: "CACHE", recursive: true });
    await Share.share({ title: name, url: uri, dialogTitle: name });
    return;
  }
  const url = URL.createObjectURL(blob);
  const el = document.createElement("a");
  el.href = url;
  el.download = name;
  document.body.appendChild(el);
  el.click();
  el.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
