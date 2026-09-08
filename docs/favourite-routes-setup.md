# Favourite routes

Apply `supabase/migrations/202609040001_saved_routes.sql` once in the Supabase
SQL Editor for the project used by the app, or apply it through your team's
normal migration process. This adds only `public.saved_routes`, its indexes,
and permissions. No existing application tables are changed.

The table stores the owner's user ID, a custom title, the two GTFS station
snapshots, and a stable route signature. The stable signature contains the
ordered transit service/line sequence and transport modes. Departure time,
arrival time, waiting time, duration, trip ID, and search-result rank are not
part of the favourite identity. The assignment app filters records
by the signed-in user's ID, but the database does not enforce row isolation.
A unique constraint on `user_id, route_key` prevents repeated saves from
creating duplicates. Re-saving an existing favourite leaves its custom title
intact; rename it in Profile.

The app does not store old departure times or fares as current information.
View live route resolves the saved station IDs against the current station dataset,
recalculates routes using the current timetable, and selects the candidate with
the same ordered service sequence and transport modes. The planner searches its
complete candidate set, even when the favourite is outside the four routes
normally displayed. Only when that service sequence is absent from the complete
set does the app explain that alternatives are being shown. Missing stations
require the user to choose new locations. Existing favourites with legacy
signatures remain readable and are matched using their saved line name.

## Verify in the app

1. Sign in, choose two different stations in Journey, and select Find Routes.
2. Select a route, tap Save route, enter a name, and save.
3. Open Profile > Favourite Routes. Check the saved title and endpoints.
4. Rename it, close and reopen the page, and verify the title persists.
5. Tap View live route. Check the endpoints, current departures, waiting times,
   and live vehicles.
6. Save the same route again and check it still appears only once.
7. Remove the favourite and check the Profile Saved Routes count updates.
8. Sign in with another account and verify the app's user-ID filter does not
   display the first account's records.
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

Live database persistence requires the migration and signed-in accounts and is
not covered by the in-memory widget tests.

## Multiple Smart Reminders

Apply `supabase/migrations/202609050002_daily_commutes.sql` for a new database.
For a database that already has the original one-reminder table, also apply
`supabase/migrations/202609060002_multiple_daily_commutes.sql`. The compatibility
migration gives every existing reminder an ID and changes the primary key from
`user_id` to `id`, allowing each user to keep multiple reminders. It explicitly
keeps row-level security disabled and does not change Avatar Storage policies.

Apply `supabase/migrations/202609060003_saved_places.sql` to add the separate
Saved Places table for Home, University, and Work. Saved Places keep individual
station details for Journey Planning and do not replace Favourite Routes. This
table also keeps row-level security disabled for the assignment.
