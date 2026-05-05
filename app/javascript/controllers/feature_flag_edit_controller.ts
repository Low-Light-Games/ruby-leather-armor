import { Controller } from "@hotwired/stimulus"

export default class FeatureFlagEditController extends Controller<HTMLFormElement> {
  static targets = ["bucketingSection", "granularSection", "moduloSection"]

  declare readonly bucketingSectionTarget: HTMLElement
  declare readonly granularSectionTarget: HTMLElement
  declare readonly moduloSectionTarget: HTMLElement

  connect() {
    this.refresh()
  }

  refresh() {
    const bucketed = this.modeValue() === "bucketed"
    this.bucketingSectionTarget.hidden = !bucketed

    const strategy = bucketed ? this.strategyValue() : null
    this.granularSectionTarget.hidden = strategy !== "granular"
    this.moduloSectionTarget.hidden = strategy !== "modulo"
  }

  private modeValue(): string {
    const checked = this.element.querySelector<HTMLInputElement>(
      'input[name="feature_flag[mode]"]:checked',
    )
    return checked ? checked.value : "off"
  }

  private strategyValue(): string | null {
    const checked = this.element.querySelector<HTMLInputElement>(
      'input[name="feature_flag[bucketing_strategy]"]:checked',
    )
    return checked ? checked.value : null
  }
}
