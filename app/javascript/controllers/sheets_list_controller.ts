import { Controller } from "@hotwired/stimulus";

// Stimulus controller for expand/collapse functionality
// This demonstrates Stimulus's strength: simple, focused interactions
export default class SheetsListController extends Controller {
  static targets = ["item", "details", "icon"];

  declare itemTargets: HTMLElement[];
  declare detailsTargets: HTMLElement[];
  declare iconTargets: HTMLElement[];

  connect() {
    // All items start collapsed
    this.itemTargets.forEach((item) => {
      item.classList.remove("expanded");
    });
  }

  toggle(event: Event) {
    const clickedItem = event.currentTarget as HTMLElement;
    if (!clickedItem) return;

    const isExpanded = clickedItem.classList.contains("expanded");
    
    // Toggle the expanded class on the item
    clickedItem.classList.toggle("expanded");
    
    // Find the details and icon within this specific item
    const details = clickedItem.querySelector("[data-sheets-list-target='details']") as HTMLElement;
    
    if (details) {
      // Toggle the expanded/collapsed classes for smooth animation
      if (isExpanded) {
        details.classList.remove("expanded");
        details.classList.add("collapsed");
      } else {
        details.classList.remove("collapsed");
        details.classList.add("expanded");
      }
    }
  }
}

