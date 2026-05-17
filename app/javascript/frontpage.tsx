import React from "react";
import { createRoot } from "react-dom/client";
import FrontPage from "./frontpage/FrontPage";
import RedditLanding from "./frontpage/RedditLanding";

document.addEventListener("DOMContentLoaded", () => {
  const el = document.getElementById("frontpage-root");
  if (el) {
    createRoot(el).render(
      <React.StrictMode>
        <FrontPage />
      </React.StrictMode>
    );
  }

  const redditEl = document.getElementById("reddit-landing-root");
  if (redditEl) {
    createRoot(redditEl).render(
      <React.StrictMode>
        <RedditLanding />
      </React.StrictMode>
    );
  }
});
