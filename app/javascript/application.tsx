// Stimulus setup
import { Application } from "@hotwired/stimulus";

// React setup
import React from "react";
import { createRoot } from "react-dom/client";

// Import React components
import App from "./components/App";
import AdventureCreation from "./components/AdventureCreation";
import AdventurePlay from "./components/AdventurePlay";
import AdminStoryEditor from "./components/AdminStoryEditor";
import { AuthProvider } from "./contexts/AuthContext";
import { GameDataProvider } from "./contexts/GameDataContext";

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
        <GameDataProvider>
          <App />
        </GameDataProvider>
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
        <GameDataProvider>
          <AuthProvider>
            <AdventurePlay adventureId={adventureId} />
          </AuthProvider>
        </GameDataProvider>
      </React.StrictMode>
    );
  }

  // SPA 4: Admin Story editor (new / edit)
  const storyEditorRoot = document.getElementById("admin-story-editor-root");
  if (storyEditorRoot) {
    const mode = (storyEditorRoot.dataset.mode || 'create') as 'create' | 'edit';
    const storyId = storyEditorRoot.dataset.storyId
      ? Number(storyEditorRoot.dataset.storyId)
      : undefined;
    const root = createRoot(storyEditorRoot);
    root.render(
      <React.StrictMode>
        <AuthProvider>
          <AdminStoryEditor mode={mode} storyId={storyId} />
        </AuthProvider>
      </React.StrictMode>
    );
  }
});
