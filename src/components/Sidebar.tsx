"use client";

import { Conversation } from "@/lib/types";

interface SidebarProps {
  conversations: Conversation[];
  activeId: string | null;
  isOpen: boolean;
  onToggle: () => void;
  onNewChat: () => void;
  onSelect: (id: string) => void;
  onDelete: (id: string) => void;
  darkMode: boolean;
  onToggleDarkMode: () => void;
}

export default function Sidebar({
  conversations,
  activeId,
  isOpen,
  onToggle,
  onNewChat,
  onSelect,
  onDelete,
  darkMode,
  onToggleDarkMode,
}: SidebarProps) {
  if (!isOpen) return null;

  return (
    <aside className="w-72 h-screen flex flex-col bg-gray-50 dark:bg-gray-800 border-l dark:border-gray-700 transition-all">
      {/* Header */}
      <div className="p-4 border-b dark:border-gray-700">
        <div className="flex items-center justify-between mb-3">
          <h1 className="text-xl font-bold text-primary-600 dark:text-primary-400">
            🤖 Waha AI
          </h1>
          <button
            onClick={onToggle}
            className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 text-gray-500"
            title="إغلاق القائمة"
          >
            ✕
          </button>
        </div>
        <button
          onClick={onNewChat}
          className="w-full py-2.5 px-4 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium transition-colors flex items-center justify-center gap-2"
        >
          <span>＋</span>
          <span>محادثة جديدة</span>
        </button>
      </div>

      {/* Conversations list */}
      <div className="flex-1 overflow-y-auto p-2">
        {conversations.length === 0 ? (
          <div className="text-center text-gray-400 dark:text-gray-500 mt-8 px-4">
            <p className="text-3xl mb-2">💬</p>
            <p className="text-sm">لا توجد محادثات بعد</p>
            <p className="text-xs mt-1">اضغط "محادثة جديدة" للبدء</p>
          </div>
        ) : (
          conversations.map((conv) => (
            <div
              key={conv.id}
              className={`group flex items-center gap-2 p-3 rounded-lg cursor-pointer mb-1 transition-colors ${
                activeId === conv.id
                  ? "bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300"
                  : "hover:bg-gray-100 dark:hover:bg-gray-700"
              }`}
              onClick={() => onSelect(conv.id)}
            >
              <span className="text-sm flex-1 truncate">{conv.title}</span>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDelete(conv.id);
                }}
                className="opacity-0 group-hover:opacity-100 text-red-400 hover:text-red-600 text-xs transition-opacity"
                title="حذف"
              >
                🗑
              </button>
            </div>
          ))
        )}
      </div>

      {/* Footer */}
      <div className="p-3 border-t dark:border-gray-700">
        <button
          onClick={onToggleDarkMode}
          className="w-full py-2 px-3 rounded-lg text-sm hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors flex items-center justify-center gap-2"
        >
          <span>{darkMode ? "☀️" : "🌙"}</span>
          <span>{darkMode ? "الوضع الفاتح" : "الوضع الداكن"}</span>
        </button>
      </div>
    </aside>
  );
}
