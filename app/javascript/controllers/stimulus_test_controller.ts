import { Controller } from "@hotwired/stimulus";

export default class StimulusTestController extends Controller {
    static values = { id: Number };
    declare idValue: number;
  
    add(event: Event) {

    }

    detract(event: Event) {

    }

    delete(event: Event) {
        const button = event.currentTarget as HTMLElement;
        const id = button.dataset.deleteId; // "123"
    }

    destroy() {
        console.log(this.idValue); // 123
        // Use this.idValue to delete the item
    }
}