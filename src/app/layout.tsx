import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Waha AI",
  description: "منصة ذكاء اصطناعي متكاملة - Unified AI Workspace",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ar" dir="rtl" suppressHydrationWarning>
      <body className="bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100 antialiased">
        {children}
      </body>
    </html>
  );
}
