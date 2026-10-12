"use client";

import { useState } from "react";
import Sidebar from "@/components/Sidebar";
import ChatArea from "@/components/ChatArea";
import { Conversation, Message } from "@/lib/types";
import { v4 as uuidv4 } from "uuid";

export default function Home() {
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [activeConversationId, setActiveConversationId] = useState<string | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [darkMode, setDarkMode] = useState(false);

  const activeConversation = conversations.find((c) => c.id === activeConversationId) || null;

  function createNewConversation() {
    const newConv: Conversation = {
      id: uuidv4(),
      title: "محادثة جديدة",
      messages: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    setConversations((prev) => [newConv, ...prev]);
    setActiveConversationId(newConv.id);
  }

  function deleteConversation(id: string) {
    setConversations((prev) => prev.filter((c) => c.id !== id));
    if (activeConversationId === id) {
      setActiveConversationId(null);
    }
  }

  function addMessage(conversationId: string, message: Message) {
    setConversations((prev) =>
      prev.map((c) => {
        if (c.id !== conversationId) return c;
        const updatedMessages = [...c.messages, message];
        const title =
          c.messages.length === 0 && message.role === "user"
            ? message.content.slice(0, 40) + (message.content.length > 40 ? "..." : "")
            : c.title;
        return { ...c, messages: updatedMessages, title, updatedAt: new Date().toISOString() };
      })
    );
  }

  function toggleDarkMode() {
    setDarkMode(!darkMode);
    document.documentElement.classList.toggle("dark");
  }

  return (
    <div className={`flex h-screen overflow-hidden ${darkMode ? "dark" : ""}`}>
      <Sidebar
        conversations={conversations}
        activeId={activeConversationId}
        isOpen={sidebarOpen}
        onToggle={() => setSidebarOpen(!sidebarOpen)}
        onNewChat={createNewConversation}
        onSelect={setActiveConversationId}
        onDelete={deleteConversation}
        darkMode={darkMode}
        onToggleDarkMode={toggleDarkMode}
      />
      <ChatArea
        conversation={activeConversation}
        onSendMessage={(msg) => {
          if (!activeConversationId) {
            const newConv: Conversation = {
              id: uuidv4(),
              title: msg.content.slice(0, 40) + (msg.content.length > 40 ? "..." : ""),
              messages: [msg],
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString(),
            };
            setConversations((prev) => [newConv, ...prev]);
            setActiveConversationId(newConv.id);
          } else {
            addMessage(activeConversationId, msg);
          }
        }}
        onToggleSidebar={() => setSidebarOpen(!sidebarOpen)}
        sidebarOpen={sidebarOpen}
      />
    </div>
  );
}
