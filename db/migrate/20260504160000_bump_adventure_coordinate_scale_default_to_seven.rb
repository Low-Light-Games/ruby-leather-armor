# frozen_string_literal: true

# Bumps the default `Adventure.coordinate_scale` from 1.0 to 7.0 so each
# grid unit translates into a more substantial travel distance. With the
# previous default a 5×5 displacement (≈7.07 grid units) resolved to ~0.7
# hours of plains walking — too brisk for "I walk to the keep" to register
# as an in-fiction day's journey. At 7.0, the same displacement becomes
# ~49.5 miles / ~5h, which both TimeKeeper and the SceneRetrieval prompt
# see consistently.
class BumpAdventureCoordinateScaleDefaultToSeven < ActiveRecord::Migration[7.1]
  def up
    change_column_default :adventures, :coordinate_scale, from: 1.0, to: 7.0
    Adventure.where(coordinate_scale: 1.0).update_all(coordinate_scale: 7.0)
  end

  def down
    change_column_default :adventures, :coordinate_scale, from: 7.0, to: 1.0
    Adventure.where(coordinate_scale: 7.0).update_all(coordinate_scale: 1.0)
  end
end
