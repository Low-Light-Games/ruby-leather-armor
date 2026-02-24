// Stimulus setup
import { Application } from "@hotwired/stimulus";

// React setup
import React from "react";
import { createRoot } from "react-dom/client";

// Import React components
import App from "./components/App";
import AdventureCreation from "./components/AdventureCreation";
import AdventurePlay from "./components/AdventurePlay";
import { AuthProvider } from "./contexts/AuthContext";

// Import Stimulus controllers
import SheetsListController from "./controllers/sheets_list_controller";
import StimulusTestController from "./controllers/stimulus_test_controller";

// Initialize Stimulus
const Stimulus = Application.start();
Stimulus.register("sheets-list", SheetsListController);
Stimulus.register("stimuilus-test", StimulusTestController);

// Mount React apps when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  // SPA 1: Character Sheet management (home page)
  const reactRoot = document.getElementById("react-root");
  if (reactRoot) {
    const root = createRoot(reactRoot);
    root.render(
      <React.StrictMode>
        <App />
      </React.StrictMode>
    );
  }

  // SPA 2: Adventure creation
  const adventureCreationRoot = document.getElementById("adventure-creation-root");
  if (adventureCreationRoot) {
    const root = createRoot(adventureCreationRoot);
    root.render(
      <React.StrictMode>
        <AuthProvider>
          <AdventureCreation />
        </AuthProvider>
      </React.StrictMode>
    );
  }

  // SPA 3: Adventure play
  const adventurePlayRoot = document.getElementById("adventure-play-root");
  if (adventurePlayRoot) {
    const adventureId = Number(adventurePlayRoot.dataset.adventureId);
    const root = createRoot(adventurePlayRoot);
    root.render(
      <React.StrictMode>
        <AuthProvider>
          <AdventurePlay adventureId={adventureId} />
        </AuthProvider>
      </React.StrictMode>
    );
  }
});
