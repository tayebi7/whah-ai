/** @type {import('next').NextConfig} */
const staticExport = process.env.WAHA_STATIC === "1"; // phone build: no server, the app answers its own /api calls

const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  ...(staticExport ? { output: "export", images: { unoptimized: true }, trailingSlash: false } : {}),
};

export default nextConfig;
