/**
 * Starting points for the "add provider" form. Everything stays editable, and URLs should be
 * confirmed against each provider's current documentation.
 * AMD is hardware/software rather than one hosted API: use "Custom" with the URL of the
 * AMD-compatible endpoint you actually have (for example a vLLM server on ROCm that you run).
 */
export type Preset = { key: string; name: string; baseUrl: string; protocol: "openai" | "anthropic" | "gemini"; local?: boolean; note?: string };

export const PRESETS: Preset[] = [
  { key: "openai", name: "OpenAI", baseUrl: "https://api.openai.com/v1", protocol: "openai" },
  { key: "anthropic", name: "Anthropic Claude", baseUrl: "https://api.anthropic.com/v1", protocol: "anthropic", note: "Chat and vision only; no image generation." },
  { key: "gemini", name: "Google Gemini", baseUrl: "https://generativelanguage.googleapis.com/v1beta", protocol: "gemini" },
  { key: "openrouter", name: "OpenRouter", baseUrl: "https://openrouter.ai/api/v1", protocol: "openai" },
  { key: "groq", name: "Groq", baseUrl: "https://api.groq.com/openai/v1", protocol: "openai" },
  { key: "nvidia", name: "NVIDIA NIM (build.nvidia.com)", baseUrl: "https://integrate.api.nvidia.com/v1", protocol: "openai" },
  { key: "mistral", name: "Mistral AI", baseUrl: "https://api.mistral.ai/v1", protocol: "openai" },
  { key: "deepseek", name: "DeepSeek", baseUrl: "https://api.deepseek.com/v1", protocol: "openai" },
  { key: "together", name: "Together AI", baseUrl: "https://api.together.xyz/v1", protocol: "openai" },
  { key: "cohere", name: "Cohere (compatibility API)", baseUrl: "https://api.cohere.ai/compatibility/v1", protocol: "openai" },
  { key: "huggingface", name: "Hugging Face Inference Providers", baseUrl: "https://router.huggingface.co/v1", protocol: "openai" },
  { key: "ollama", name: "Ollama (local)", baseUrl: "http://localhost:11434/v1", protocol: "openai", local: true },
  { key: "lmstudio", name: "LM Studio (local)", baseUrl: "http://localhost:1234/v1", protocol: "openai", local: true },
  { key: "custom", name: "Custom / AMD-compatible / any OpenAI-style gateway", baseUrl: "", protocol: "openai" },
];
