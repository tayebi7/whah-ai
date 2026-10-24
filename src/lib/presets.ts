/**
 * Starting points for the "add provider" form. Everything stays editable, and URLs should be
 * confirmed against each provider's current documentation.
 * AMD is hardware/software rather than one hosted API: use "Custom" with the URL of the
 * AMD-compatible endpoint you actually have (for example a vLLM server on ROCm that you run).
 */
export type Preset = { key: string; name: string; baseUrl: string; protocol: "openai" | "anthropic" | "gemini" | "azure" | "ollama" | "cohere"; local?: boolean; note?: string };

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
  { key: "cohere", name: "Cohere (native API)", baseUrl: "https://api.cohere.com", protocol: "cohere" },
  { key: "azure", name: "Azure OpenAI", baseUrl: "https://YOUR-RESOURCE.openai.azure.com/openai/deployments/YOUR-DEPLOYMENT", protocol: "azure", note: "Model field = your deployment name. Add ?api-version=... to the URL to change the version." },
  { key: "xai", name: "xAI Grok", baseUrl: "https://api.x.ai/v1", protocol: "openai" },
  { key: "perplexity", name: "Perplexity", baseUrl: "https://api.perplexity.ai", protocol: "openai" },
  { key: "fireworks", name: "Fireworks AI", baseUrl: "https://api.fireworks.ai/inference/v1", protocol: "openai" },
  { key: "cerebras", name: "Cerebras", baseUrl: "https://api.cerebras.ai/v1", protocol: "openai" },
  { key: "sambanova", name: "SambaNova", baseUrl: "https://api.sambanova.ai/v1", protocol: "openai" },
  { key: "deepinfra", name: "DeepInfra", baseUrl: "https://api.deepinfra.com/v1/openai", protocol: "openai" },
  { key: "siliconflow", name: "SiliconFlow", baseUrl: "https://api.siliconflow.com/v1", protocol: "openai" },
  { key: "moonshot", name: "Moonshot (Kimi)", baseUrl: "https://api.moonshot.ai/v1", protocol: "openai" },
  { key: "qwen", name: "Alibaba Qwen (DashScope)", baseUrl: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", protocol: "openai" },
  { key: "zhipu", name: "Zhipu GLM (Z.ai)", baseUrl: "https://api.z.ai/api/paas/v4", protocol: "openai" },
  { key: "github", name: "GitHub Models", baseUrl: "https://models.github.ai/inference", protocol: "openai" },
  { key: "huggingface", name: "Hugging Face Inference Providers", baseUrl: "https://router.huggingface.co/v1", protocol: "openai" },
  { key: "ollama", name: "Ollama (native API, local or remote)", baseUrl: "http://localhost:11434", protocol: "ollama", local: true, note: "Use your computer's address (for example http://192.168.1.20:11434) when running on a phone." },
  { key: "ollama-openai", name: "Ollama (OpenAI-compatible)", baseUrl: "http://localhost:11434/v1", protocol: "openai", local: true },
  { key: "lmstudio", name: "LM Studio (local)", baseUrl: "http://localhost:1234/v1", protocol: "openai", local: true },
  { key: "custom", name: "Custom / AMD-compatible / any OpenAI-style gateway", baseUrl: "", protocol: "openai" },
];
