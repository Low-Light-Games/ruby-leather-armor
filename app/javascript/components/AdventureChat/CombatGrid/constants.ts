// Pixel size of one square at full zoom; the grid auto-scales down to
// fit MAX_GRID_PX so wide battlefields don't blow out the layout.
export const COMBAT_GRID_DEFAULT_CELL_PX = 24
export const COMBAT_GRID_MIN_CELL_PX = 18
export const COMBAT_GRID_MAX_TOTAL_PX = 360

// How many extra squares of empty grid to render around the outermost
// token so the player can always see one move-action's worth of space
// in any direction.
export const COMBAT_GRID_VIEWPORT_PADDING_FLOOR = 3

// Default viewport bounds when the battlefield doesn't ship explicit ones.
export const COMBAT_GRID_DEFAULT_VIEWPORT_WIDTH = 20
export const COMBAT_GRID_DEFAULT_VIEWPORT_HEIGHT = 20

// On mobile, show this many squares across each axis (centred on the player).
// At ~319px column width this gives ≈46px tiles — within Apple's 44px touch guideline.
export const COMBAT_GRID_MOBILE_VIEW_SQUARES = 7
