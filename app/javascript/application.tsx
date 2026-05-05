// Stimulus setup
import { Application } from "@hotwired/stimulus";

// Stimulus-driven admin styles (no React component owns these pages)
import "./components/AdminFeatureFlags/FeatureFlagEdit.scss";

// React setup
import React from "react";
import { createRoot } from "react-dom/client";

// Import React components
import App from "./components/App";
import AdventureCreation from "./components/AdventureCreation";
import AdventurePlay from "./components/AdventurePlay";
import AdminStoryEditor from "./components/AdminStoryEditor";
import SubscriptionPlans from "./components/SubscriptionPlans";
import SubscriptionSuccess from "./components/SubscriptionSuccess";
import { AuthProvider } from "./contexts/AuthContext";
import { GameDataProvider } from "./contexts/GameDataContext";
import type { SubscriptionPlan } from "./types/subscriptions";

// Import Stimulus controllers
import FeatureFlagEditController from "./controllers/feature_flag_edit_controller";

// Initialize Stimulus
const Stimulus = Application.start();
Stimulus.register("feature-flag-edit", FeatureFlagEditController);

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

  // SPA 5: Subscription plans
  const subscriptionPlansRoot = document.getElementById("subscription-plans-root");
  if (subscriptionPlansRoot) {
    const plansJson = subscriptionPlansRoot.dataset.plans || "[]";
    const plans = JSON.parse(plansJson) as SubscriptionPlan[];
    const currentPlanKey = subscriptionPlansRoot.dataset.currentPlanKey || "free";
    const root = createRoot(subscriptionPlansRoot);
    root.render(
      <React.StrictMode>
        <AuthProvider>
          <SubscriptionPlans plans={plans} currentPlanKey={currentPlanKey} />
        </AuthProvider>
      </React.StrictMode>
    );
  }

  // SPA 6: Subscription success polling page
  const subscriptionSuccessRoot = document.getElementById("subscription-success-root");
  if (subscriptionSuccessRoot) {
    const root = createRoot(subscriptionSuccessRoot);
    root.render(
      <React.StrictMode>
        <AuthProvider>
          <SubscriptionSuccess />
        </AuthProvider>
      </React.StrictMode>
    );
  }
});
