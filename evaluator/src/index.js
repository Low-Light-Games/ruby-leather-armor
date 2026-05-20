"use strict";

// ----------------------------------------------------------------
// Sentry — must be initialized before any other requires.
// Only reports what cannot be returned to Rails (process-level crashes).
// Route-level errors are returned in the response body and reported by Rails.
// ----------------------------------------------------------------
const Sentry = require("@sentry/node");

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    serverName: "evaluator",
    tracesSampleRate: 0,
  });
}

process.on("uncaughtException", (err) => {
  console.error("[evaluator] uncaughtException:", err);
  Sentry.captureException(err);
  // Flush buffered Sentry events before exiting — captureException is async.
  Sentry.flush(2000).finally(() => process.exit(1));
});

process.on("unhandledRejection", (reason) => {
  console.error("[evaluator] unhandledRejection:", reason);
  Sentry.captureException(reason instanceof Error ? reason : new Error(String(reason)));
  // unhandledRejection is non-fatal by default; flush but do not exit.
  Sentry.flush(2000);
});

// ----------------------------------------------------------------
// App
// ----------------------------------------------------------------
const express = require("express");
const { chat, moderate } = require("./ai_client");

const app = express();
app.use(express.json({ limit: "4mb" }));

const MAX_PARALLEL_FAN_OUT = Math.max(1, parseInt(process.env.EVALUATOR_MAX_PARALLEL || "7", 10));

app.use((req, _res, next) => {
  const count = Array.isArray(req.body) ? ` (${req.body.length} items)` : "";
  console.log(`[evaluator] ${req.method} ${req.path}${count}`);
  next();
});

// Worst case: 3 sequential retries × OPENAI_TIMEOUT_MS per call (all in
// one parallel slot) + backoff. Must stay below the Rails HTTP read_timeout
// so Rails always gets a well-formed error body instead of a socket hang-up.
const REQUEST_TIMEOUT_MS = Math.max(
  60_000,
  parseInt(process.env.EVALUATOR_REQUEST_TIMEOUT_MS || "210000", 10)
);
app.use((req, res, next) => {
  const timer = setTimeout(() => {
    if (!res.headersSent) {
      res.status(503).json({ error: `Request timed out after ${REQUEST_TIMEOUT_MS / 1000}s`, partial_results: [] });
    }
  }, REQUEST_TIMEOUT_MS);
  res.on("finish", () => clearTimeout(timer));
  res.on("close", () => clearTimeout(timer));
  next();
});

const PORT = process.env.PORT || 3001;

async function mapWithConcurrency(items, limit, iteratee) {
  const results = new Array(items.length);
  let nextIndex = 0;

  async function worker() {
    while (true) {
      const currentIndex = nextIndex;
      nextIndex += 1;

      if (currentIndex >= items.length) return;

      try {
        results[currentIndex] = {
          status: "fulfilled",
          value: await iteratee(items[currentIndex], currentIndex),
        };
      } catch (error) {
        results[currentIndex] = {
          status: "rejected",
          reason: error,
        };
      }
    }
  }

  const workers = Array.from({ length: Math.min(limit, items.length) }, () => worker());
  await Promise.all(workers);
  return results;
}

// ----------------------------------------------------------------
// Health check
// ----------------------------------------------------------------
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

// ----------------------------------------------------------------
// POST /moderate
//
// Classifies a single text input using the OpenAI Moderation API.
// Body:    { "input": "text to classify" }
// Returns: { flagged, categories, category_scores }
// ----------------------------------------------------------------
app.post("/moderate", async (req, res) => {
  const { input } = req.body;

  if (!input || typeof input !== "string") {
    return res.status(400).json({ error: "Request body must include a non-empty string 'input'." });
  }

  const result = await moderate(input);
  return res.json(result);
});

// ----------------------------------------------------------------
// POST /fan_out
//
// Runs N prompts with bounded concurrency. Returns results in input order.
// All-or-nothing: if any call fails, returns 500 with { error, partial_results }.
// ----------------------------------------------------------------
app.post("/fan_out", async (req, res) => {
  const prompts = req.body;

  if (!Array.isArray(prompts) || prompts.length === 0) {
    return res.status(400).json({ error: "Request body must be a non-empty array of prompt objects." });
  }

  if (prompts.length > MAX_PARALLEL_FAN_OUT) {
    console.log(
      `[evaluator] fan_out saturated: ${prompts.length} prompts limited to ${MAX_PARALLEL_FAN_OUT} concurrent calls`
    );
  }

  const settled = await mapWithConcurrency(prompts, MAX_PARALLEL_FAN_OUT, (p) =>
    chat({
      systemPrompt:    p.system_prompt,
      userMessage:     p.user_message,
      model:           p.model,
      maxTokens:       p.max_tokens,
      reasoningEffort: p.reasoning_effort,
      meta:            p.meta ?? {},
    })
  );

  const results = [];
  const failures = [];

  for (let i = 0; i < settled.length; i++) {
    const outcome = settled[i];
    if (outcome.status === "fulfilled") {
      results.push(outcome.value);
    } else {
      const step = prompts[i]?.meta?.step ?? null;
      const domain = prompts[i]?.meta?.domain ?? `index ${i}`;
      const reason = outcome.reason ?? {};
      const retryInfo = reason.evaluatorRetry ?? {};
      failures.push({
        index: i,
        step,
        domain,
        error: reason.message ?? String(reason),
        error_name: retryInfo.errorName ?? reason.name ?? null,
        error_status: retryInfo.errorStatus ?? null,
        attempts: retryInfo.attempts ?? null,
        max_attempts: retryInfo.maxAttempts ?? null,
        retryable: retryInfo.retryable ?? null,
      });
    }
  }

  if (failures.length > 0) {
    const errorMsg = failures
      .map((f) => {
        const tag =
          f.attempts != null
            ? ` (${f.error_name ?? "Error"} after ${f.attempts}/${f.max_attempts} attempts, retryable=${f.retryable})`
            : "";
        return `OpenAI call failed for domain ${f.domain}: ${f.error}${tag}`;
      })
      .join("; ");
    return res.status(500).json({
      error: errorMsg,
      partial_results: results,
      failed_steps: failures.map((f) => f.step).filter((s) => s != null),
      failures,
    });
  }

  return res.json(results);
});

// ----------------------------------------------------------------
// POST /sequential
//
// Runs N prompts sequentially. After each call, extracts a summary
// string using the caller-supplied `summary_extraction_key` and
// prepends all accumulated summaries to the next system_prompt_base.
// Node never hardcodes a key name — Rails passes it per item.
//
// Stops at first failure and returns 500 with { error, partial_results }.
// ----------------------------------------------------------------
app.post("/sequential", async (req, res) => {
  const prompts = req.body;

  if (!Array.isArray(prompts) || prompts.length === 0) {
    return res.status(400).json({ error: "Request body must be a non-empty array of prompt objects." });
  }

  const results = [];
  const summaries = [];

  for (let i = 0; i < prompts.length; i++) {
    const p = prompts[i];
    const extractionKey = p.summary_extraction_key;

    // Prepend accumulated summaries from prior iterations
    const systemPrompt =
      summaries.length > 0
        ? `[PREVIOUS EVALUATIONS]\n${summaries.join("\n\n")}\n\n${p.system_prompt_base}`
        : p.system_prompt_base;

    let result;
    try {
      result = await chat({
        systemPrompt,
        userMessage:     p.user_message,
        model:           p.model,
        maxTokens:       p.max_tokens,
        reasoningEffort: p.reasoning_effort,
        meta:            p.meta ?? {},
      });
    } catch (err) {
      const domain = p.meta?.domain ?? `index ${i}`;
      return res.status(500).json({
        error: `Sequential call failed at index ${i} (${domain}): ${err.message}`,
        partial_results: results,
      });
    }

    results.push(result);

    // Accumulate summary for the next iteration
    if (extractionKey && result.parsed_response?.[extractionKey]) {
      const domainLabel = p.meta?.domain ? `[${p.meta.domain.toUpperCase()}]` : `[DOMAIN ${i + 1}]`;
      summaries.push(`${domainLabel} ${result.parsed_response[extractionKey]}`);
    }
  }

  return res.json(results);
});

// ----------------------------------------------------------------
// Express error middleware — catches synchronous route errors and
// returns a well-formed JSON 500 rather than dropping the connection.
// Does NOT report to Sentry — Rails reports route-level errors.
// ----------------------------------------------------------------
app.use((err, _req, res, _next) => {
  console.error("[evaluator] Unhandled route error:", err);
  res.status(500).json({ error: err.message ?? "Internal server error" });
});

// ----------------------------------------------------------------
// Start
// ----------------------------------------------------------------
app.listen(PORT, () => {
  console.log(`[evaluator] Listening on port ${PORT}`);
});
