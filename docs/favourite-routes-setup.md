# Favourite routes

Apply `supabase/migrations/202609040001_saved_routes.sql` once in the Supabase
SQL Editor for the project used by the app, or apply it through your team's
normal migration process. This adds only `public.saved_routes`, its indexes,
and policies. No existing application tables are changed.

The table stores the owner's user ID, a custom title, the two GTFS station
snapshots, and the chosen route signature. Each user can only read and change
their own records through authenticated RLS policies. A unique constraint on
`user_id, route_key` prevents repeated saves from creating duplicates. Re-saving
an existing favourite leaves its custom title intact; rename it in Profile.

The app does not store old departure times or fares as current information.
Plan again resolves the saved station IDs against the current station dataset,
calls the existing route planner, and selects the matching route signature if
available. Otherwise it explains that alternatives are being shown. Missing
stations require the user to choose new locations.

## Verify in the app

1. Sign in, choose two different stations in Journey, and select Find Routes.
2. Select a route, tap Save route, enter a name, and save.
3. Open Profile > Favourite Routes. Check the saved title and endpoints.
4. Rename it, close and reopen the page, and verify the title persists.
5. Tap Plan again. Check the endpoints and refreshed route results.
6. Save the same route again and check it still appears only once.
7. Remove the favourite and check the Profile Saved Routes count updates.
8. Sign in with another account and verify the first account's records do not
   appear. Also verify with a second account's authenticated API request that
   selecting, updating, or deleting a known first-account row returns no rows.
9. Test without a network connection: failed saves must not show Saved; failed
   renames/deletions must leave the existing item visible and allow retry.

Before applying the migration, favourite requests will fail and display retry
messages; the Profile count displays a dash rather than an invented number.
The Trips Taken and Active Alerts statistics are still existing placeholders
and are outside this change.

Automated checks:

```powershell
flutter test --no-pub test/personal_travel/saved_routes_test.dart
```

Live database persistence and RLS require the migration and signed-in accounts
and are not covered by the in-memory widget tests.
