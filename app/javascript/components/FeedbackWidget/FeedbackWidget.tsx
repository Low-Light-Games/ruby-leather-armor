import { useState, useRef, useEffect, useCallback } from "react";
import { apiFetch } from "../../utils/api";
import "./FeedbackWidget.scss";

type WidgetState = "collapsed" | "open" | "sending" | "thanks" | "cooldown";

const MAX_BODY = 2000;
const COOLDOWN_MS = 60_000;
const STORAGE_KEY = "feedback_last_sent";

function remainingCooldown(): number {
  const last = Number(sessionStorage.getItem(STORAGE_KEY) || 0);
  if (!last) return 0;
  return Math.max(0, COOLDOWN_MS - (Date.now() - last));
}

const FeedbackWidget = () => {
  const [state, setState] = useState<WidgetState>(() =>
    remainingCooldown() > 0 ? "cooldown" : "collapsed"
  );
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [cooldownSec, setCooldownSec] = useState(() =>
    Math.ceil(remainingCooldown() / 1000)
  );
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const startCooldown = useCallback(() => {
    sessionStorage.setItem(STORAGE_KEY, String(Date.now()));
    setState("cooldown");

    const tick = () => {
      const left = Math.ceil(remainingCooldown() / 1000);
      setCooldownSec(left);
      if (left <= 0) {
        clearTimer();
        setState("collapsed");
      }
    };
    tick();
    timerRef.current = setInterval(tick, 1000);
  }, [clearTimer]);

  useEffect(() => {
    if (state === "cooldown" && !timerRef.current) {
      const tick = () => {
        const left = Math.ceil(remainingCooldown() / 1000);
        setCooldownSec(left);
        if (left <= 0) {
          clearTimer();
          setState("collapsed");
        }
      };
      tick();
      timerRef.current = setInterval(tick, 1000);
    }
    return clearTimer;
  }, [state, clearTimer]);

  const handleOpen = () => {
    setState("open");
    setError(null);
    setTimeout(() => textareaRef.current?.focus(), 0);
  };

  const handleClose = () => {
    setState("collapsed");
    setBody("");
    setError(null);
  };

  const handleSubmit = async () => {
    const trimmed = body.trim();
    if (!trimmed) return;

    setState("sending");
    setError(null);

    try {
      await apiFetch("/feedbacks", {
        method: "POST",
        body: JSON.stringify({
          body: trimmed,
          page_url: window.location.href,
        }),
      });
      setBody("");
      setState("thanks");
      setTimeout(() => startCooldown(), 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
      setState("open");
    }
  };

  if (state === "cooldown") {
    return (
      <button
        type="button"
        className="feedback-widget__trigger feedback-widget__trigger--cooldown"
        disabled
        aria-label="Feedback cooldown"
      >
        {cooldownSec}s
      </button>
    );
  }

  if (state === "collapsed") {
    return (
      <button
        type="button"
        className="feedback-widget__trigger"
        onClick={handleOpen}
        aria-label="Send feedback"
      >
        Feedback
      </button>
    );
  }

  if (state === "thanks") {
    return (
      <div className="feedback-widget__card">
        <p className="feedback-widget__thanks">Thank you for your feedback.</p>
      </div>
    );
  }

  const remaining = MAX_BODY - body.length;

  return (
    <div className="feedback-widget__card">
      <div className="feedback-widget__header">
        <span className="feedback-widget__title">Send Feedback</span>
        <button
          type="button"
          className="feedback-widget__close"
          onClick={handleClose}
          aria-label="Close"
        >
          &times;
        </button>
      </div>

      <textarea
        ref={textareaRef}
        className="feedback-widget__textarea"
        value={body}
        onChange={(e) => setBody(e.target.value.slice(0, MAX_BODY))}
        placeholder="What worked, what didn't, what was meh?"
        rows={5}
        disabled={state === "sending"}
      />

      <div className="feedback-widget__footer">
        <span className={`feedback-widget__counter${remaining < 100 ? " feedback-widget__counter--warn" : ""}`}>
          {remaining}
        </span>
        {error && <span className="feedback-widget__error">{error}</span>}
        <button
          type="button"
          className="feedback-widget__submit"
          onClick={handleSubmit}
          disabled={state === "sending" || !body.trim()}
        >
          {state === "sending" ? "Sending\u2026" : "Send"}
        </button>
      </div>
    </div>
  );
};

export default FeedbackWidget;
