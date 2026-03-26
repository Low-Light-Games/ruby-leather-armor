"use strict";

const OpenAI = require("openai");

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
  timeout: 30_000,
  maxRetries: 0,
});

/**
 * Makes a single chat completion call and returns structured result data.
 *
 * @param {Object} opts
 * @param {string} opts.systemPrompt
 * @param {string} opts.userMessage
 * @param {string} opts.model
 * @param {number} opts.maxTokens
 * @param {Object} opts.meta  - passthrough metadata (step, domain, etc.)
 * @returns {Promise<Object>}
 */
async function chat({ systemPrompt, userMessage, model, maxTokens, meta = {} }) {
  const t0 = Date.now();

  const requestBody = {
    model,
    max_tokens: maxTokens,
    messages: [
      { role: "system", content: systemPrompt },
      { role: "user", content: userMessage },
    ],
  };

  const response = await client.chat.completions.create(requestBody);

  const durationMs = Date.now() - t0;
  const rawContent = response.choices[0]?.message?.content ?? "";
  const usage = response.usage ?? {};

  let parsedResponse = null;
  let parseStatus = "success";

  try {
    // Try the full content first (handles well-formed responses).
    parsedResponse = JSON.parse(rawContent);
  } catch {
    try {
      // Fall back to extracting the first complete JSON object — handles responses
      // where the model prefixes or suffixes the JSON with prose.
      const jsonMatch = rawContent.match(/\{[\s\S]*\}/);
      if (jsonMatch) parsedResponse = JSON.parse(jsonMatch[0]);
      else parseStatus = "parse_error";
    } catch {
      parseStatus = "parse_error";
    }
  }

  return {
    raw_response: rawContent,
    parsed_response: parsedResponse,
    parse_status: parseStatus,
    model_used: response.model ?? model,
    duration_ms: durationMs,
    usage: {
      input_tokens: usage.prompt_tokens ?? 0,
      output_tokens: usage.completion_tokens ?? 0,
      reasoning_tokens: usage.completion_tokens_details?.reasoning_tokens ?? 0,
      total_tokens: usage.total_tokens ?? 0,
    },
    request_body: { system_prompt: systemPrompt, user_message: userMessage },
    meta,
  };
}

module.exports = { chat };
