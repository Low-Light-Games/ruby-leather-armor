# Step: Classify (Removed)

The Classify step was removed. Its functionality has been absorbed:

- **dm_query detection** → now handled by the Intake step (`is_dm_query` field)
- **Domain classification** → no longer needed; all beacons run in parallel regardless, and `primary_context` is derived from beacon results using a domain priority heuristic

See [Intake](../steps/intake.md) for the replacement.
