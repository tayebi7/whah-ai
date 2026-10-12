"use client";

import { useState, useRef, useEffect } from "react";
import { Conversation, Message } from "@/lib/types";
import { v4 as uuidv4 } from "uuid";
import MessageBubble from "@/components/MessageBubble";
import ChatInput from "@/components/ChatInput";

interface ChatAreaProps {
  conversation: Conversation | null;
  onSendMessage: (message: Message) => void;
  onToggleSidebar: () => void;
  sidebarOpen: boolean;
}

export default function ChatArea({
  conversation,
  onSendMessage,
  onToggleSidebar,
  sidebarOpen,
}: ChatAreaProps) {
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [conversation?.messages]);

  function handleSend(content: string) {
    if (!content.trim()) return;

    const userMsg: Message = {
      id: uuidv4(),
      role: "user",
      content: content.trim(),
      createdAt: new Date().toISOString(),
    };

    onSendMessage(userMsg);

    // Simulate AI response (placeholder - will be replaced with real API calls)
    setTimeout(() => {
      const aiMsg: Message = {
        id: uuidv4(),
        role: "assistant",
        content: generatePlaceholderResponse(content),
        createdAt: new Date().toISOString(),
        provider: "demo",
        model: "waha-demo",
      };
      onSendMessage(aiMsg);
    }, 800);
  }

  return (
    <main className="flex-1 flex flex-col h-screen bg-white dark:bg-gray-900">
      {/* Top bar */}
      <header className="flex items-center gap-3 px-4 py-3 border-b dark:border-gray-700 bg-white/80 dark:bg-gray-900/80 backdrop-blur-sm">
        {!sidebarOpen && (
          <button
            onClick={onToggleSidebar}
            className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
            title="فتح القائمة"
          >
            ☰
          </button>
        )}
        <h2 className="font-medium text-gray-700 dark:text-gray-300 truncate">
          {conversation?.title || "Waha AI"}
        </h2>
      </header>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-6">
        {!conversation || conversation.messages.length === 0 ? (
          <WelcomeScreen />
        ) : (
          <div className="max-w-3xl mx-auto space-y-4">
            {conversation.messages.map((msg) => (
              <MessageBubble key={msg.id} message={msg} />
            ))}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input */}
      <div className="border-t dark:border-gray-700 bg-white dark:bg-gray-900 px-4 py-3">
        <div className="max-w-3xl mx-auto">
          <ChatInput onSend={handleSend} />
        </div>
      </div>
    </main>
  );
}

function WelcomeScreen() {
  return (
    <div className="flex flex-col items-center justify-center h-full text-center px-4">
      <div className="text-6xl mb-4">🤖</div>
      <h2 className="text-2xl font-bold text-gray-800 dark:text-gray-200 mb-2">
        مرحبًا بك في Waha AI
      </h2>
      <p className="text-gray-500 dark:text-gray-400 mb-6 max-w-md">
        منصة ذكاء اصطناعي متكاملة تدعم المحادثة، توليد الصور، تحليل المستندات، وبرمجة التطبيقات.
      </p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 max-w-lg w-full">
        {[
          { icon: "💬", text: "اسألني أي سؤال" },
          { icon: "📄", text: "حلّل مستندًا" },
          { icon: "💻", text: "اكتب كودًا برمجيًا" },
          { icon: "🎨", text: "أنشئ صورة" },
        ].map((item) => (
          <div
            key={item.text}
            className="p-3 rounded-xl border dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 cursor-pointer transition-colors text-sm"
          >
            <span className="text-lg ml-2">{item.icon}</span>
            {item.text}
          </div>
        ))}
      </div>
    </div>
  );
}

function generatePlaceholderResponse(input: string): string {
  const responses = [
    `شكرًا على سؤالك! هذه نسخة تجريبية من Waha AI.\n\nلتفعيل الردود الذكية الحقيقية، يرجى:\n1. إضافة مفتاح API لأحد المزودين (OpenAI, Anthropic, Google, …)\n2. تكوين المزود في صفحة الإعدادات\n\nرسالتك كانت:\n> ${input}`,
    `مرحبًا! أنا Waha AI في الوضع التجريبي 🧪\n\nلم يتم تكوين أي مزود AI بعد. أضف مفتاح API في الإعدادات للحصول على ردود ذكية.\n\nما كتبته:\n> ${input}`,
  ];
  return responses[Math.floor(Math.random() * responses.length)];
}
