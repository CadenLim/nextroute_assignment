# NextRoute

## Supabase setup

1. In the Supabase dashboard, open your project and select **Connect**.
2. Copy `config/supabase.example.json` to `config/supabase.json`.
3. Replace the placeholders with the project's **Project URL** and
   **Publishable Key**. Never put a `service_role` or secret key in this app.
4. Fetch dependencies and start Flutter with the local config:

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.json
```

For a release build, pass the same option:

```powershell
flutter build apk --dart-define-from-file=config/supabase.json
```

The initialized client is available through `Database.client` in
`lib/services/database.dart`. For example:

```dart
final rows = await Database.client.from('your_table').select();
```

`config/supabase.json` is ignored by Git. The publishable key is intended for
client applications. This coursework uses explicit SQL `GRANT`/`REVOKE`
permissions instead of row-level security. Never store real or sensitive user
data in this assignment project: its application tables intentionally do not
use Row Level Security. The private avatar bucket is the exception and keeps
its policies on `storage.objects` so uploads and signed reads continue to work.

## Module 5: route-focused analytics and notifications

Users choose **My Routes**, stored only in device preferences; no profile table
or Module 5 user role is required. Live Service, the seven-day trend, weekly
report and Notification Centre then use the same route scope, with an explicit
All network option. The route picker distinguishes live, stale, timetable-only
and unavailable realtime data rather than presenting missing data as zero.

The trend explores **published travel alerts** over the last seven Malaysia
calendar days and can switch between delay, possible slow movement, service and
all-alert metrics. Reports use fixed Monday–Sunday weeks (eight selectable
weeks), route-scoped KPIs, category counts, alert details, a copyable text report
and a downloadable CSV report. These counts are not unique incident counts,
passenger crowding or a guarantee of service reliability.
Collector-health notices are excluded from travel-alert counts.

### Deployment order

1. Review and run `supabase/migrations/202609050001_analytics_quality.sql` in
   the shared project's SQL Editor. It adds nullable quality columns and three
   narrowly scoped functions; it does not delete/backfill records, replace the
   existing daily view, change teammate-table access, or touch
   station/ridership/profile tables.
2. Run `202609050002_notification_bus_details.sql`,
   `202609060001_estimated_bus_delays.sql`,
   `202609060002_gps_service_estimates.sql`, then
   `202609060003_route_focused_alerts.sql`. These are additive Module 5
   migrations. The last migration adds sustained-slow-movement confidence and
   updates the public archive projection; none inserts demonstration data or
   changes grants on teammate tables.
3. Check the existing SELECT permissions on `notifications`: historical public,
   active alerts must remain readable after `expires_at`. Both reader functions
   use invoker security and preserve the table permissions. Do not grant client
   roles permission to insert, update or delete shared notifications.
4. Deploy the updated collector:

   ```powershell
   supabase functions deploy collect-analytics --project-ref ajxsdxqszentcxbaiunq
   ```

5. Change the existing collector Cron schedule to every five minutes. The
   collector still upserts one row per half-hour bucket, so analytics keeps at
   most 48 service snapshots per day while private per-vehicle observations are
   retained for eight days for delay and sustained-slow-movement estimates.
   Check its next invocation and confirm new snapshot columns are
   populated. Legacy NULL fields deliberately remain
   unknown. New congestion percentages use only fresh observations whose
   congestion status was explicitly reported, weighted by observation count.
6. Restart the app with the Supabase config and verify Trend, Reports, and the
   live inbox as guest and signed-in user. Use an approved published test alert
   to verify category/route/date filtering, then withdraw that test alert.
   No demonstration records are inserted by this migration.

Missing archive functions show a visible error, not a fabricated empty history.
Until the quality function is deployed, the old daily view remains readable,
but legacy congestion rates are treated as unavailable. Apply the migration
before deploying the new collector; otherwise its new writes will fail.

Live Service and the cloud collector combine the official `rapid-bus-kl` and
`rapid-bus-mrtfeeder` vehicle-position feeds. This keeps Kuala Lumpur bus
analytics useful when one valid feed temporarily contains no vehicles; the
response reports per-feed entity counts/errors so partial coverage is visible.
No Penang/Kuantan vehicles or ridership data are mixed into this scope.

The five-minute position-age threshold (60 seconds allowed for clock skew) is
an application quality rule, not an operator SLA. Stale/undated positions never
produce a new current congestion alert. A continuously observed route extends
one alert's expiry; after a two-hour gap a new observation can start a new alert.
Historical hourly alerts are not rewritten. Collector-health alerts retain
their existing hourly deduplication. HTTP success is labelled request success,
not service availability. Missing scheduled slots are shown separately.

The collector response includes delay rejection counts (`stale_or_undated`,
`missing_trip_or_route`, `missing_position`, `no_schedule_match`) plus the number
without official stop references, schedule matches and accepted estimates. It
also reports movement samples, possible-congestion alerts and non-fatal movement
errors. These distinguish missing input from calculation/deployment failures.

The collector's existing endpoint authentication configuration is unchanged.
Review endpoint access with the Cron owner before a public production release.
This change does not introduce an official Trip Updates feed or background remote
push delivery; those require separate integrations. It adds a deliberately
conservative NextRoute estimate described below.

### Module 5 bus notice details and export

Run `supabase/migrations/202609050002_notification_bus_details.sql` separately
to add optional details to Module 5's `notifications` table. This script inserts
no notices and does not change teammate tables, grants or the collector.
Existing notices work without these fields; missing values display as unknown.

For a genuine operator-published bus notice, use the existing `route_id` matching
`assets/gtfs/bus/routes.txt`, and fill only details actually supplied by the source:

- `delay_minutes`: integer minutes, 0–1440; leave NULL if unknown.
- `vehicle_label`: public operator bus identifier, if this identifies one bus.
- `from_stop` / `to_stop`: affected section, not guessed from a route's name.
- `direction`: supplied destination/headsign or direction; NULL if unspecified.

Publisher notices keep their supplied details and are labelled `Reported delay`.
A route-level notice cannot identify a specific bus without a public vehicle
identifier. Test data must be clearly labelled TEST/DEMO and must not be
presented as a real operator announcement.

The collector can also create a labelled `Estimated delay`. It downloads the
official Rapid KL and MRT feeder static timetables only when the realtime feed
contains a usable candidate. An estimate is accepted only when all of these are
true:

- the vehicle position is no more than five minutes old;
- the vehicle reports a route, trip ID and valid GPS position;
- the trip matches the appropriate weekday/weekend static GTFS trip;
- the feed supplies a stop reference, or GPS is within 75 metres of a scheduled
  stop;
- frequency-based service includes its realtime `start_time`;
- the stop is not the terminal and the computed difference is between -30 and
  +180 minutes (larger differences are treated as mismatches).

At the observed stop, actual timestamp minus scheduled stop time gives schedule
deviation. That difference is propagated to the downstream terminal to show
`Scheduled arrival`, `Estimated arrival`, and delay minutes. This is an academic
estimate, not an operator prediction: traffic after the observed stop can change
the result. Missing or stale information never becomes zero/on-time. A material
delay starts at five minutes. One record is updated per trip instance; when an
observed estimate falls below the threshold, the current notice expires into
History. The collector response exposes candidate/estimate/alert counts and a
non-fatal `delay_error` for deployment diagnosis.

Possible congestion is a separate, explicitly labelled NextRoute estimate. The
collector compares successive positions of the same vehicle and trip. A notice
is eligible only after at least three consecutive 2–10 minute movement intervals
covering at least six minutes and averaging 1–10 km/h. A reported `STOPPED_AT`
state is excluded, as is movement below 40 metres, which reduces normal bus-stop
dwell and GPS-jitter false positives. Confidence increases with a longer streak
or several slow vehicles on the same route in one collection run. The result is
always labelled **Possible slow movement**, never operator-confirmed congestion.
The observation table is private to `service_role`, automatically removes rows
older than eight days, and never changes an unknown publisher congestion field
into a confirmed congestion value.

Realtime collector failures appear under **Data status**, not Service. Service
is reserved for route suspensions, diversions, stop closures, schedule changes
and other publisher/operator notices. The current public Vehicle Position feeds
do not contain GTFS Service Alerts, so a genuine Service notice is published to
the shared `notifications` table by an authorised administrator until an
official feed exists. A zero-vehicle response never claims that service stopped.

Notification search matches route IDs/names, public bus labels, stops, direction,
titles and messages within the selected Current/History/category filter.
History keeps the latest 200 readable, active-but-expired public notices;
expiration is not proof of resolution and does not trigger another push.
Search covers loaded notices, not an unlimited full-database search.

**Download weekly CSV** exports the selected Monday–Sunday week, a meaningful
summary, all seven daily rows and available public travel-alert details. Unknown
values remain blank, future days say `Not elapsed`, and dates use Malaysia time.
The UTF-8 CSV quotes commas/newlines and neutralizes spreadsheet formula prefixes.
The export includes no credentials or user profiles. Browsers initiate a download;
Windows and Linux save directly to Downloads so a native dialog cannot hide the
app, while supported mobile/macOS platforms use Save As. Cancel and failure are
shown explicitly; **Copy weekly report** remains available.

Run `flutter pub get` and fully restart/rebuild after pulling these changes:
Module 5's `file_saver` dependency requires generated platform registration.
Do not manually remove that generated registration. No existing dependency
versions were upgraded by this change. Native Android/Windows save dialogs must
still be smoke-tested on the target devices before release.

Android device notifications currently use Supabase Realtime plus
`flutter_local_notifications` while NextRoute is running. This is not remote
background push. Do not add Firebase packages without the team's registered
Firebase Android app and `google-services.json`; true closed-app delivery needs
FCM token registration and a server-side sender.

### Validation

```powershell
flutter analyze --no-pub lib/models/analytics_notification_models.dart lib/services/analytics_service.dart lib/screens/service_analytics.dart test/modules/analytics_notification
flutter test --no-pub
deno test --no-lock supabase/functions/collect-analytics/index_test.ts
```

Before merging, complete the live deployment checks above. Passing local tests
alone does not verify live schema, access grants, Cron configuration or
data-source coverage.
