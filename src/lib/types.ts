export interface Message {
  id: string;
  role: "user" | "assistant" | "system";
  content: string;
  createdAt: string;
  attachments?: Attachment[];
  model?: string;
  provider?: string;
  isStreaming?: boolean;
  error?: string;
}

export interface Attachment {
  id: string;
  name: string;
  type: string;
  size: number;
  url?: string;
}

export interface Conversation {
  id: string;
  title: string;
  messages: Message[];
  createdAt: string;
  updatedAt: string;
  folderId?: string;
}

export interface Provider {
  id: string;
  name: string;
  type: ProviderType;
  baseUrl: string;
  apiKey: string;
  modelId: string;
  enabled: boolean;
  priority: number;
  streaming: boolean;
  capabilities: string[];
  customHeaders?: Record<string, string>;
  timeout?: number;
  maxRetries?: number;
}

export type ProviderType =
  | "openai"
  | "anthropic"
  | "google"
  | "groq"
  | "mistral"
  | "deepseek"
  | "cohere"
  | "openrouter"
  | "huggingface"
  | "ollama"
  | "lmstudio"
  | "nvidia"
  | "custom";
