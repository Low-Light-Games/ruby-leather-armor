import React from "react";
import { createRoot } from "react-dom/client";
import FrontPage from "./frontpage/FrontPage";

document.addEventListener("DOMContentLoaded", () => {
  const el = document.getElementById("frontpage-root");
  if (el) {
    createRoot(el).render(
      <React.StrictMode>
        <FrontPage />
      </React.StrictMode>
    );
  }
});
