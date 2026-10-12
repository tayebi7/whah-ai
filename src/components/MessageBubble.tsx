"use client";

import { Message } from "@/lib/types";
import { useState } from "react";

interface MessageBubbleProps {
  message: Message;
}

export default function MessageBubble({ message }: MessageBubbleProps) {
  const [copied, setCopied] = useState(false);
  const isUser = message.role === "user";

  async function handleCopy() {
    await navigator.clipboard.writeText(message.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className={`flex animate-fade-in ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[85%] rounded-2xl px-4 py-3 ${
          isUser
            ? "bg-primary-600 text-white rounded-bl-sm"
            : "bg-gray-100 dark:bg-gray-800 text-gray-900 dark:text-gray-100 rounded-br-sm"
        }`}
      >
        {/* Message content */}
        <div className="whitespace-pre-wrap text-sm leading-relaxed">
          {message.content}
        </div>

        {/* Footer */}
        <div className={`flex items-center gap-2 mt-2 text-xs ${
          isUser ? "text-blue-200" : "text-gray-400"
        }`}>
          <span>
            {new Date(message.createdAt).toLocaleTimeString("ar-SA", {
              hour: "2-digit",
              minute: "2-digit",
            })}
          </span>
          {message.provider && (
            <span className="opacity-70">• {message.provider}/{message.model}</span>
          )}
          {!isUser && (
            <button
              onClick={handleCopy}
              className="mr-auto hover:opacity-100 opacity-60 transition-opacity"
              title="نسخ"
            >
              {copied ? "✅" : "📋"}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
