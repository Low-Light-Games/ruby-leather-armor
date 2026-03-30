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

app.use((req, _res, next) => {
  const count = Array.isArray(req.body) ? ` (${req.body.length} items)` : "";
  console.log(`[evaluator] ${req.method} ${req.path}${count}`);
  next();
});

// 120s covers the worst case: 6 parallel 30s OpenAI calls with buffer.
// Rails HTTP client waits 150s — always above this so Rails gets a well-formed error.
const REQUEST_TIMEOUT_MS = 120_000;
app.use((req, res, next) => {
  const timer = setTimeout(() => {
    if (!res.headersSent) {
      res.status(503).json({ error: "Request timed out after 120s", partial_results: [] });
    }
  }, REQUEST_TIMEOUT_MS);
  res.on("finish", () => clearTimeout(timer));
  res.on("close", () => clearTimeout(timer));
  next();
});

const PORT = process.env.PORT || 3001;

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
// Runs N prompts in parallel (Promise.all). Returns results in input order.
// All-or-nothing: if any call fails, returns 500 with { error, partial_results }.
// ----------------------------------------------------------------
app.post("/fan_out", async (req, res) => {
  const prompts = req.body;

  if (!Array.isArray(prompts) || prompts.length === 0) {
    return res.status(400).json({ error: "Request body must be a non-empty array of prompt objects." });
  }

  const settled = await Promise.allSettled(
    prompts.map((p) =>
      chat({
        systemPrompt: p.system_prompt,
        userMessage:  p.user_message,
        model:        p.model,
        maxTokens:    p.max_tokens,
        meta:         p.meta ?? {},
      })
    )
  );

  const results = [];
  const failures = [];

  for (let i = 0; i < settled.length; i++) {
    const outcome = settled[i];
    if (outcome.status === "fulfilled") {
      results.push(outcome.value);
    } else {
      const domain = prompts[i]?.meta?.domain ?? `index ${i}`;
      failures.push({ index: i, domain, error: outcome.reason?.message ?? String(outcome.reason) });
    }
  }

  if (failures.length > 0) {
    const errorMsg = failures
      .map((f) => `OpenAI call failed for domain ${f.domain}: ${f.error}`)
      .join("; ");
    return res.status(500).json({
      error: errorMsg,
      partial_results: results,
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
        userMessage: p.user_message,
        model:       p.model,
        maxTokens:   p.max_tokens,
        meta:        p.meta ?? {},
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
