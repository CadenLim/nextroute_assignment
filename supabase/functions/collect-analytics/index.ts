import GtfsRealtimeBindings from "npm:gtfs-realtime-bindings@1.1.1";
import { createClient } from "npm:@supabase/supabase-js@2";

const feedUrl =
  "https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl";
const source = "rapidkl_gtfs_realtime";

type VehicleEntity = {
  vehicle?: {
    congestionLevel?: number;
    position?: { latitude?: number; longitude?: number };
    trip?: { routeId?: string };
  };
};

function bucketStart(now: Date): string {
  const bucket = new Date(now);
  bucket.setUTCMinutes(now.getUTCMinutes() < 30 ? 0 : 30, 0, 0);
  return bucket.toISOString();
}

function hourKey(now: Date): string {
  return now.toISOString().slice(0, 13).replaceAll("-", "").replace("T", "");
}

function validPosition(entity: VehicleEntity): boolean {
  const latitude = entity.vehicle?.position?.latitude;
  const longitude = entity.vehicle?.position?.longitude;
  return typeof latitude === "number" &&
    Number.isFinite(latitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    typeof longitude === "number" &&
    Number.isFinite(longitude) &&
    longitude >= -180 &&
    longitude <= 180;
}

async function saveFailure(
  supabase: ReturnType<typeof createClient>,
  now: Date,
  reason: string,
) {
  await supabase.from("analytics_snapshots").upsert(
    {
      bucket_start: bucketStart(now),
      captured_at: now.toISOString(),
      vehicle_count: 0,
      route_count: 0,
      congested_vehicle_count: 0,
      severe_congestion_count: 0,
      fetch_succeeded: false,
      source,
    },
    { onConflict: "bucket_start,source", ignoreDuplicates: true },
  );

  await supabase.from("notifications").upsert(
    {
      notification_type: "service",
      title: "Realtime data unavailable",
      message:
        `NextRoute could not collect Rapid Bus KL realtime data: ${reason}`,
      severity: "high",
      origin: "appGenerated",
      dedupe_key: `data-health:${hourKey(now)}`,
      expires_at: new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString(),
    },
    { onConflict: "dedupe_key", ignoreDuplicates: true },
  );
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json(
      { error: "Method not allowed." },
      { status: 405, headers: { Allow: "POST" } },
    );
  }

  const now = new Date();
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return Response.json(
      { error: "Supabase server environment is incomplete." },
      { status: 500 },
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  try {
    const response = await fetch(feedUrl, {
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      throw new Error(`feed returned HTTP ${response.status}`);
    }

    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0) {
      throw new Error("feed returned an empty response");
    }

    const feed = GtfsRealtimeBindings.transit_realtime.FeedMessage.decode(
      bytes,
    );
    const entities = (feed.entity ?? []) as VehicleEntity[];
    const vehicles = entities.filter(
      (entity) => entity.vehicle && validPosition(entity),
    );
    const routes = new Set<string>();
    const congestedByRoute = new Map<
      string,
      { congested: number; severe: number }
    >();
    let congestedCount = 0;
    let severeCount = 0;

    for (const entity of vehicles) {
      const routeId = entity.vehicle?.trip?.routeId?.trim() || "Unknown route";
      if (routeId !== "Unknown route") routes.add(routeId);
      const level = entity.vehicle?.congestionLevel ?? 0;
      if (level !== 3 && level !== 4) continue;

      congestedCount += 1;
      if (level === 4) severeCount += 1;
      const current = congestedByRoute.get(routeId) ?? {
        congested: 0,
        severe: 0,
      };
      current.congested += 1;
      if (level === 4) current.severe += 1;
      congestedByRoute.set(routeId, current);
    }

    const { error: snapshotError } = await supabase
      .from("analytics_snapshots")
      .upsert(
        {
          bucket_start: bucketStart(now),
          captured_at: now.toISOString(),
          vehicle_count: vehicles.length,
          route_count: routes.size,
          congested_vehicle_count: congestedCount,
          severe_congestion_count: severeCount,
          fetch_succeeded: true,
          source,
        },
        { onConflict: "bucket_start,source" },
      );
    if (snapshotError) throw snapshotError;

    if (congestedByRoute.size > 0) {
      const expiresAt = new Date(now.getTime() + 2 * 60 * 60 * 1000);
      const notifications = [...congestedByRoute.entries()].map(
        ([routeId, counts]) => ({
          notification_type: "crowd",
          title: counts.severe > 0
            ? "Severe congestion reported"
            : "Congestion reported",
          message:
            `The Rapid Bus KL feed reported ${counts.congested} congested ` +
            `vehicle(s)${routeId === "Unknown route" ? "." : ` on route ${routeId}.`}`,
          route_id: routeId === "Unknown route" ? null : routeId,
          severity: counts.severe > 0 ? "critical" : "high",
          origin: "appGenerated",
          dedupe_key: `congestion:${routeId}:${hourKey(now)}`,
          expires_at: expiresAt.toISOString(),
        }),
      );
      const { error: notificationError } = await supabase
        .from("notifications")
        .upsert(notifications, {
          onConflict: "dedupe_key",
          ignoreDuplicates: true,
        });
      if (notificationError) throw notificationError;
    }

    return Response.json({
      captured_at: now.toISOString(),
      vehicles: vehicles.length,
      routes: routes.size,
      congested: congestedCount,
      severe: severeCount,
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unknown error";
    await saveFailure(supabase, now, reason);
    return Response.json({ error: reason }, { status: 502 });
  }
});
