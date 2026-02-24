// Stimulus setup
import { Application } from "@hotwired/stimulus";

// React setup
import React from "react";
import { createRoot } from "react-dom/client";

// Import React components
import App from "./components/App";

// Import Stimulus controllers
import SheetsListController from "./controllers/sheets_list_controller";
import StimulusTestController from "./controllers/stimulus_test_controller";

// Initialize Stimulus
const Stimulus = Application.start();
Stimulus.register("sheets-list", SheetsListController);
Stimulus.register("stimuilus-test", StimulusTestController);

// Mount React app when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  const container = document.getElementById("react-root");
  if (container) {
    const root = createRoot(container);
    root.render(
      <React.StrictMode>
        <App />
      </React.StrictMode>
    );
  }
});
