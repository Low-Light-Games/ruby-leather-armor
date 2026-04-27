"use strict";

const OpenAI = require("openai");

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
  timeout: 30_000,
  maxRetries: 0,
});

const OPENAI_MAX_RETRIES = Math.max(0, parseInt(process.env.DM_OPENAI_MAX_RETRIES || "2", 10));
const OPENAI_RETRY_BASE_DELAY_SECONDS = Math.max(
  0,
  parseFloat(process.env.DM_OPENAI_RETRY_BASE_DELAY_SECONDS || "0.5")
);
const OPENAI_RETRY_MAX_DELAY_SECONDS = Math.max(
  OPENAI_RETRY_BASE_DELAY_SECONDS,
  parseFloat(process.env.DM_OPENAI_RETRY_MAX_DELAY_SECONDS || "8")
);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function extractRetryAfterSeconds(error) {
  const raw =
    error?.headers?.["retry-after"] ??
    error?.headers?.["Retry-After"] ??
    error?.response?.headers?.["retry-after"] ??
    error?.response?.headers?.["Retry-After"];

  if (raw == null) return null;

  const value = Number.parseFloat(raw);
  return Number.isFinite(value) ? value : null;
}

function isRetryableOpenAIError(error) {
  const status = error?.status ?? error?.response?.status;

  if (status === 408 || status === 429) return true;
  if (typeof status === "number" && status >= 500) return true;

  return [
    "APIConnectionError",
    "APIConnectionTimeoutError",
    "InternalServerError",
  ].includes(error?.name);
}

function jitteredBackoffDelaySeconds(attempt) {
  const ceiling = Math.min(
    OPENAI_RETRY_BASE_DELAY_SECONDS * (2 ** (attempt - 1)),
    OPENAI_RETRY_MAX_DELAY_SECONDS
  );

  return Math.random() * ceiling;
}

function retryDelaySeconds(attempt, error) {
  const retryAfterSeconds = extractRetryAfterSeconds(error);
  if (retryAfterSeconds != null) {
    return {
      delaySeconds: Math.max(0, Math.min(retryAfterSeconds, OPENAI_RETRY_MAX_DELAY_SECONDS)),
      usedRetryAfter: true,
    };
  }

  return {
    delaySeconds: jitteredBackoffDelaySeconds(attempt),
    usedRetryAfter: false,
  };
}

async function withOpenAIRetries(callType, model, fn) {
  let attempt = 0;

  while (true) {
    attempt += 1;

    try {
      return await fn();
    } catch (error) {
      if (!isRetryableOpenAIError(error) || attempt > OPENAI_MAX_RETRIES) {
        throw error;
      }

      const { delaySeconds, usedRetryAfter } = retryDelaySeconds(attempt, error);
      console.warn(
        `[evaluator] ${callType} ${error?.name || error?.constructor?.name || "Error"} ` +
        `(attempt ${attempt}/${OPENAI_MAX_RETRIES + 1}, model=${model}, ` +
        `delay=${delaySeconds.toFixed(3)}s, retry_after=${usedRetryAfter})`
      );
      await sleep(delaySeconds * 1000);
    }
  }
}

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

  const response = await withOpenAIRetries("chat", model, () =>
    client.chat.completions.create(requestBody)
  );

  const durationMs = Date.now() - t0;
  const rawContent = response.choices[0]?.message?.content ?? "";
  const usage = response.usage ?? {};

  let parsedResponse = null;
  let parseStatus = "success";

  const stripFences = (s) =>
    s
      .trim()
      .replace(/^\s*```(?:json)?\s*/i, "")
      .replace(/\s*```\s*$/, "")
      .trim();

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

  // Mirrors Rails AiClient#parse_json(fallback_as: :dm_response) for narrate.
  if (parseStatus === "parse_error" && meta.parse_fallback === "dm_response") {
    const cleaned = stripFences(rawContent);
    if (cleaned) {
      parsedResponse = { narrative: cleaned };
      parseStatus = "parse_fallback";
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

/**
 * Calls the OpenAI Moderation API on a text input.
 *
 * @param {string} input - The player text to classify.
 * @returns {Promise<Object>} { flagged, categories, category_scores }
 */
async function moderate(input) {
  const response = await withOpenAIRetries("moderate", "omni-moderation-latest", () =>
    client.moderations.create({
      model: "omni-moderation-latest",
      input,
    })
  );
  const result = response.results[0];
  return {
    flagged: result.flagged,
    categories: result.categories,
    category_scores: result.category_scores,
  };
}

module.exports = { chat, moderate };
