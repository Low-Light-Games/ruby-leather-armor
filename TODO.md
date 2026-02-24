# Token Optimization — AI Dungeon Master

## Current State

- Model: `gpt-4o-mini` (128k context, 16k max output)
- Each player action = **2 API calls** (sanitization + DM response)
- Roll requests trigger an additional 2-call round
- Conversation history capped at **20 messages** (`last(20)`)
- DM response `max_tokens`: **1000**
- At plateau (~20 messages), each DM call sends ~5,000–6,000 input tokens

## Optimization Strategies

### 1. Conversation Summarization
After N messages, summarize older messages into a single "story so far" paragraph and replace the full history with that compact recap. Keep only the last ~6 messages verbatim for immediate context. This is the **highest-impact** optimization — it keeps token usage nearly flat regardless of session length.

### 2. Token Counting Before Sending
Use a tokenizer (e.g. `tiktoken` via the `tiktoken_ruby` gem) to count tokens before sending the request. Dynamically trim history to stay within a target budget (e.g. 4,000 input tokens). This prevents surprise truncations from `finish_reason: length`.

### 3. Compress the System Prompt
The DM system prompt (~550–1,150 tokens) is sent on every call. It includes story stages, character stats, and verbose JSON format instructions. Compressing it (shorter instructions, abbreviations, removing examples) could save 200–400 tokens per call.

### 4. Separate Narrative from Metadata
Instead of asking the model for a single JSON object with narrative + reasoning + advance_stage + roll_request, split into two calls:
- Call A: Generate narrative text only (no JSON overhead)
- Call B: A tiny call with just the narrative as context, asking for structured metadata (advance_stage, roll_request)

This makes each call simpler and reduces the chance of JSON truncation. Trade-off: doubles the DM calls (cost increase), but each call is cheaper and more reliable.

### 5. Streaming Responses
Stream the DM response to the frontend so the user sees text appearing in real-time. This doesn't save tokens but improves perceived performance, especially for longer responses.

### 6. Caching the System Prompt
OpenAI supports prompt caching for repeated prefixes. If the system prompt is identical across calls (same adventure state), the cached prefix reduces input token costs. This happens automatically with OpenAI's API for prompts > 1,024 tokens that share a prefix.

### 7. Model Selection Per Call Type
Use cheaper/faster models for simpler tasks:
- Sanitization: could use `gpt-4o-mini` or even a smaller model — it's a simple classification task
- DM response: keep `gpt-4o-mini` or upgrade to `gpt-4o` only for complex scenes
