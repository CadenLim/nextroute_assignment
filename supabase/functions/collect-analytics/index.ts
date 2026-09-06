import GtfsRealtimeBindings from "npm:gtfs-realtime-bindings@1.1.1";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { strFromU8, unzipSync } from "npm:fflate@0.8.2";

const realtimeFeeds = [
  {
    category: "rapid-bus-kl",
    url:
      "https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl",
  },
  {
    category: "rapid-bus-mrtfeeder",
    url:
      "https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-mrtfeeder",
  },
] as const;
const staticFeeds = [
  {
    category: "rapid-bus-kl",
    url: "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-kl",
  },
  {
    category: "rapid-bus-mrtfeeder",
    url:
      "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-bus-mrtfeeder",
  },
] as const;
const source = "rapidkl_gtfs_realtime";
const malaysiaOffsetMs = 8 * 60 * 60 * 1000;
const delayThresholdMinutes = 5;

type VehicleEntity = {
  sourceCategory?: string;
  vehicle?: {
    congestionLevel?: number;
    timestamp?: number | { toString(): string };
    position?: { latitude?: number; longitude?: number };
    trip?: {
      routeId?: string;
      tripId?: string;
      startTime?: string;
      startDate?: string;
    };
    currentStopSequence?: number;
    currentStatus?: number;
    stopId?: string;
    vehicle?: { id?: string; label?: string; licensePlate?: string };
  };
};

export type DelayCandidateDiagnostics = {
  totalVehicles: number;
  freshVehicles: number;
  stoppedVehicles: number;
  candidates: number;
  staleOrUndated: number;
  missingTripOrRoute: number;
  missingPosition: number;
  withoutOfficialStopReference: number;
};

type ScheduledStop = {
  sequence: number;
  arrivalSeconds: number;
  stopId: string;
  stopName: string;
  latitude: number;
  longitude: number;
};

export type TripSchedule = {
  staticTripId: string;
  routeId: string;
  serviceId: string;
  headsign: string | null;
  frequencyBased: boolean;
  stops: ScheduledStop[];
};

export type DelayEstimate = {
  routeId: string;
  tripId: string;
  serviceDate: string;
  startTime: string | null;
  delayMinutes: number;
  vehicleLabel: string | null;
  fromStop: string;
  toStop: string;
  direction: string;
  observedStopId: string;
  scheduledArrival: string;
  estimatedArrival: string;
  observedAt: string;
  estimateMethod: "schedule_stop_observation" | "schedule_near_stop_position";
};

export type PreviousVehicleObservation = {
  vehicle_id: string;
  route_id: string;
  trip_id: string;
  latitude: number;
  longitude: number;
  vehicle_timestamp: string;
  speed_kmh: number | null;
  movement_interval_seconds: number | null;
  slow_interval_streak?: number;
  slow_duration_seconds?: number;
};

export type MovementEstimate = {
  vehicleId: string;
  routeId: string;
  tripId: string;
  vehicleTimestamp: string;
  latitude: number;
  longitude: number;
  speedKmh: number | null;
  intervalSeconds: number | null;
  sustainedSlow: boolean;
  observationDurationMinutes: number | null;
  slowIntervalStreak: number;
  slowDurationSeconds: number;
  confidence: "Low" | "Medium" | "High" | null;
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

function distanceMetres(
  firstLatitude: number,
  firstLongitude: number,
  secondLatitude: number,
  secondLongitude: number,
): number {
  const radians = (degrees: number) => degrees * Math.PI / 180;
  const latitudeDelta = radians(secondLatitude - firstLatitude);
  const longitudeDelta = radians(secondLongitude - firstLongitude);
  const first = radians(firstLatitude);
  const second = radians(secondLatitude);
  const haversine = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(first) * Math.cos(second) *
      Math.sin(longitudeDelta / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.sqrt(haversine));
}

function vehicleIdentifier(entity: VehicleEntity): string | null {
  const descriptor = entity.vehicle?.vehicle;
  return text(descriptor?.id) ?? text(descriptor?.label) ??
    text(descriptor?.licensePlate);
}

function text(value: unknown): string | null {
  const result = typeof value === "string" ? value.trim() : "";
  return result.length > 0 ? result : null;
}

export function parseGtfsTime(value: string | null | undefined): number | null {
  const match = /^(\d{1,2}):(\d{2}):(\d{2})$/.exec(value?.trim() ?? "");
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  const seconds = Number(match[3]);
  if (hours > 47 || minutes > 59 || seconds > 59) return null;
  return hours * 3600 + minutes * 60 + seconds;
}

// GTFS text files may quote commas and escaped quotes. Embedded newlines are
// not used by the official Rapid KL files, so parsing stays line-oriented.
export function parseCsvRow(line: string): string[] {
  const values: string[] = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < line.length; index++) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        value += '"';
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      values.push(value.trim());
      value = "";
    } else {
      value += character;
    }
  }
  values.push(value.trim());
  return values;
}

function rows(bytes: Uint8Array | undefined): string[][] {
  if (bytes == null) return [];
  const lines = strFromU8(bytes).replace(/^\uFEFF/, "").split(/\r?\n/);
  return lines.filter((line) => line.length > 0).map(parseCsvRow);
}

function rowObjects(bytes: Uint8Array | undefined): Record<string, string>[] {
  const parsed = rows(bytes);
  if (parsed.length === 0) return [];
  const header = parsed[0];
  return parsed.slice(1).map((values) =>
    Object.fromEntries(
      header.map((name, index) => [name, values[index] ?? ""]),
    )
  );
}

function malaysiaDateKey(instant: Date): string {
  return new Date(instant.getTime() + malaysiaOffsetMs)
    .toISOString().slice(0, 10).replaceAll("-", "");
}

function serviceDateStart(dateKey: string): number | null {
  if (!/^\d{8}$/.test(dateKey)) return null;
  const year = Number(dateKey.slice(0, 4));
  const month = Number(dateKey.slice(4, 6));
  const day = Number(dateKey.slice(6, 8));
  const utc = Date.UTC(year, month - 1, day) - malaysiaOffsetMs;
  const local = new Date(utc + malaysiaOffsetMs);
  return local.getUTCFullYear() === year && local.getUTCMonth() === month - 1 &&
      local.getUTCDate() === day
    ? utc
    : null;
}

function expectedService(serviceId: string, dateKey: string): boolean {
  if (serviceId !== "weekday" && serviceId !== "weekend") return true;
  const start = serviceDateStart(dateKey);
  if (start == null) return false;
  const day = new Date(start + malaysiaOffsetMs).getUTCDay();
  return serviceId === (day === 0 || day === 6 ? "weekend" : "weekday");
}

function tripMatches(staticTripId: string, realtimeTripId: string): boolean {
  return staticTripId === realtimeTripId ||
    staticTripId.replace(/^(weekday|weekend)_/, "") === realtimeTripId ||
    realtimeTripId.replace(/^(weekday|weekend)_/, "") === staticTripId;
}

async function loadTripSchedules(
  vehicles: VehicleEntity[],
): Promise<Map<string, TripSchedule>> {
  const schedules = new Map<string, TripSchedule>();
  const errors: string[] = [];
  let attempted = 0;
  for (const { category, url } of staticFeeds) {
    const relevant = vehicles.filter((vehicle) =>
      vehicle.sourceCategory == null || vehicle.sourceCategory === category
    );
    if (relevant.length === 0) continue;
    attempted++;
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(20_000),
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const archive = unzipSync(new Uint8Array(await response.arrayBuffer()));
      for (const [tripId, schedule] of buildTripSchedules(archive, relevant)) {
        schedules.set(tripId, schedule);
      }
    } catch (error) {
      errors.push(`${url}: ${error instanceof Error ? error.message : error}`);
    }
  }
  if (attempted > 0 && errors.length === attempted) {
    throw new Error(`static feeds unavailable: ${errors.join("; ")}`);
  }
  return schedules;
}

export function buildTripSchedules(
  archive: Record<string, Uint8Array>,
  vehicles: VehicleEntity[],
): Map<string, TripSchedule> {
  const required = [
    "trips.txt",
    "stop_times.txt",
    "stops.txt",
  ];
  if (required.some((name) => archive[name] == null)) {
    throw new Error("static feed is missing timetable files");
  }

  const candidates = vehicles.map((entity) => ({
    tripId: text(entity.vehicle?.trip?.tripId),
    routeId: text(entity.vehicle?.trip?.routeId),
    date: text(entity.vehicle?.trip?.startDate) ??
      malaysiaDateKey(
        new Date(Number(entity.vehicle?.timestamp?.toString()) * 1000),
      ),
  })).filter((item) => item.tripId != null && item.routeId != null);

  const matched = new Map<string, TripSchedule>();
  for (const trip of rowObjects(archive["trips.txt"])) {
    for (const candidate of candidates) {
      if (
        !tripMatches(trip.trip_id, candidate.tripId!) ||
        !expectedService(trip.service_id, candidate.date)
      ) continue;
      matched.set(candidate.tripId!, {
        staticTripId: trip.trip_id,
        // Prasarana's MRT feeder realtime feed uses public route codes such as
        // T559 while its static feed uses internal IDs such as 30000172. The
        // trip ID is the stable cross-feed key, so keep the realtime route ID
        // for user-facing notifications after matching the trip.
        routeId: candidate.routeId!,
        serviceId: trip.service_id,
        headsign: text(trip.trip_headsign),
        frequencyBased: false,
        stops: [],
      });
    }
  }
  if (matched.size === 0) return matched;

  const byStaticId = new Map(
    [...matched.entries()].map(([realtimeId, schedule]) =>
      [schedule.staticTripId, { realtimeId, schedule }] as const
    ),
  );
  const rawStops: {
    sequence: number;
    arrivalSeconds: number;
    stopId: string;
  }[] = [];
  const stopsByTrip = new Map<string, typeof rawStops>();
  const neededStopIds = new Set<string>();
  for (const stop of rowObjects(archive["stop_times.txt"])) {
    const target = byStaticId.get(stop.trip_id);
    if (!target) continue;
    const sequence = Number(stop.stop_sequence);
    const arrivalSeconds = parseGtfsTime(stop.arrival_time);
    if (
      !Number.isInteger(sequence) || sequence <= 0 || arrivalSeconds == null ||
      !stop.stop_id
    ) continue;
    const list = stopsByTrip.get(target.realtimeId) ?? [];
    list.push({ sequence, arrivalSeconds, stopId: stop.stop_id });
    stopsByTrip.set(target.realtimeId, list);
    neededStopIds.add(stop.stop_id);
  }
  const stopDetails = new Map<
    string,
    { name: string; latitude: number; longitude: number }
  >();
  for (const stop of rowObjects(archive["stops.txt"])) {
    if (neededStopIds.has(stop.stop_id)) {
      const latitude = Number(stop.stop_lat);
      const longitude = Number(stop.stop_lon);
      if (
        Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 &&
        Number.isFinite(longitude) && longitude >= -180 && longitude <= 180
      ) {
        stopDetails.set(stop.stop_id, {
          name: text(stop.stop_name) ?? stop.stop_id,
          latitude,
          longitude,
        });
      }
    }
  }
  const frequencyIds = new Set(
    rowObjects(archive["frequencies.txt"]).map((row) => row.trip_id),
  );
  for (const [realtimeId, schedule] of matched) {
    const stopList = stopsByTrip.get(realtimeId) ?? [];
    stopList.sort((first, second) => first.sequence - second.sequence);
    schedule.frequencyBased = frequencyIds.has(schedule.staticTripId);
    schedule.stops = stopList.flatMap((stop) => {
      const details = stopDetails.get(stop.stopId);
      return details == null ? [] : [{
        ...stop,
        stopName: details.name,
        latitude: details.latitude,
        longitude: details.longitude,
      }];
    });
  }
  return matched;
}

export function estimateDelay(
  entity: VehicleEntity,
  schedule: TripSchedule,
  collectorNow: Date,
): DelayEstimate | null {
  const vehicle = entity.vehicle;
  if (vehicle == null) return null;
  const trip = vehicle?.trip;
  const tripId = text(trip?.tripId);
  const routeId = text(trip?.routeId);
  const timestamp = Number(vehicle?.timestamp?.toString());
  if (
    !tripId || !routeId || !Number.isFinite(timestamp) || timestamp <= 0 ||
    positionAge(entity, collectorNow) == null ||
    positionAge(entity, collectorNow)! > 300_000 ||
    schedule.stops.length < 2
  ) return null;

  const sequence = Number(vehicle.currentStopSequence);
  const stopId = text(vehicle.stopId);
  let currentIndex = schedule.stops.findIndex((stop) =>
    Number.isInteger(sequence) && sequence > 0
      ? stop.sequence === sequence
      : stopId != null && stop.stopId === stopId
  );
  let estimateMethod: DelayEstimate["estimateMethod"] =
    "schedule_stop_observation";
  if (currentIndex < 0 && validPosition(entity)) {
    const latitude = vehicle!.position!.latitude!;
    const longitude = vehicle!.position!.longitude!;
    let nearestDistance = Number.POSITIVE_INFINITY;
    for (let index = 0; index < schedule.stops.length; index++) {
      const stop = schedule.stops[index];
      const distance = distanceMetres(
        latitude,
        longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        currentIndex = index;
      }
    }
    // A bus between stops cannot safely be assigned to an arbitrary timetable
    // point. 75 m retains genuine near-stop observations in the production
    // feeder feed while rejecting most in-transit positions.
    if (nearestDistance > 75) return null;
    estimateMethod = "schedule_near_stop_position";
  }
  if (currentIndex < 0 || currentIndex >= schedule.stops.length - 1) {
    return null;
  }

  const current = schedule.stops[currentIndex];
  const terminal = schedule.stops[schedule.stops.length - 1];
  const startTime = text(trip!.startTime);
  const startSeconds = parseGtfsTime(startTime);
  if (schedule.frequencyBased && startSeconds == null) return null;
  const serviceDate = text(trip!.startDate) ??
    malaysiaDateKey(new Date(timestamp * 1000));
  const serviceStart = serviceDateStart(serviceDate);
  if (serviceStart == null) return null;

  const firstSeconds = schedule.stops[0].arrivalSeconds;
  const scheduledCurrentSeconds = startSeconds == null
    ? current.arrivalSeconds
    : startSeconds + current.arrivalSeconds - firstSeconds;
  const scheduledTerminalSeconds = startSeconds == null
    ? terminal.arrivalSeconds
    : startSeconds + terminal.arrivalSeconds - firstSeconds;
  const scheduledCurrent = serviceStart + scheduledCurrentSeconds * 1000;
  const rawDelayMinutes = Math.round(
    (timestamp * 1000 - scheduledCurrent) / 60_000,
  );
  // Larger differences normally mean the realtime and static trip instances did
  // not match. Reject them instead of presenting a confident but false delay.
  if (rawDelayMinutes < -30 || rawDelayMinutes > 180) return null;
  const delayMinutes = Math.max(0, rawDelayMinutes);
  const scheduledTerminal = serviceStart + scheduledTerminalSeconds * 1000;
  const vehicleLabel = text(vehicle.vehicle?.label) ??
    text(vehicle.vehicle?.licensePlate) ?? text(vehicle.vehicle?.id);
  return {
    routeId,
    tripId,
    serviceDate,
    startTime,
    delayMinutes,
    vehicleLabel,
    fromStop: current.stopName,
    toStop: terminal.stopName,
    direction: schedule.headsign ?? terminal.stopName,
    observedStopId: current.stopId,
    scheduledArrival: new Date(scheduledTerminal).toISOString(),
    estimatedArrival: new Date(scheduledTerminal + delayMinutes * 60_000)
      .toISOString(),
    observedAt: new Date(timestamp * 1000).toISOString(),
    estimateMethod,
  };
}

// Explicit quality threshold: five minutes, with 60s allowed for clock skew.
function positionAge(entity: VehicleEntity, now: Date): number | null {
  const raw = entity.vehicle?.timestamp;
  if (raw == null) return null;
  const seconds = Number(raw.toString());
  if (!Number.isFinite(seconds) || seconds <= 0) return null;
  const age = now.getTime() - seconds * 1000;
  return age < -60_000 ? null : age;
}

// The national feed often omits current_stop_sequence and stop_id. A fresh GPS
// position can still become a candidate; estimateDelay later requires it to be
// within 75 m of a stop in the matching published timetable.
export function findDelayCandidates(
  vehicles: VehicleEntity[],
  now: Date,
): { vehicles: VehicleEntity[]; diagnostics: DelayCandidateDiagnostics } {
  const candidates: VehicleEntity[] = [];
  const diagnostics: DelayCandidateDiagnostics = {
    totalVehicles: vehicles.length,
    freshVehicles: 0,
    stoppedVehicles: 0,
    candidates: 0,
    staleOrUndated: 0,
    missingTripOrRoute: 0,
    missingPosition: 0,
    withoutOfficialStopReference: 0,
  };

  for (const entity of vehicles) {
    const age = positionAge(entity, now);
    if (age == null || age > 300_000) {
      diagnostics.staleOrUndated++;
      continue;
    }
    diagnostics.freshVehicles++;
    if (entity.vehicle?.currentStatus === 1) diagnostics.stoppedVehicles++;
    if (
      text(entity.vehicle?.trip?.tripId) == null ||
      text(entity.vehicle?.trip?.routeId) == null
    ) {
      diagnostics.missingTripOrRoute++;
      continue;
    }
    if (!validPosition(entity)) {
      diagnostics.missingPosition++;
      continue;
    }
    if (
      !(Number(entity.vehicle?.currentStopSequence) > 0) &&
      text(entity.vehicle?.stopId) == null
    ) diagnostics.withoutOfficialStopReference++;
    candidates.push(entity);
  }
  diagnostics.candidates = candidates.length;
  return { vehicles: candidates, diagnostics };
}

export function estimateMovement(
  entity: VehicleEntity,
  previous: PreviousVehicleObservation | null,
): MovementEstimate | null {
  const vehicleId = vehicleIdentifier(entity);
  const routeId = text(entity.vehicle?.trip?.routeId);
  const tripId = text(entity.vehicle?.trip?.tripId);
  const timestamp = Number(entity.vehicle?.timestamp?.toString());
  if (
    !vehicleId || !routeId || !tripId || !Number.isFinite(timestamp) ||
    timestamp <= 0 || !validPosition(entity)
  ) return null;

  const latitude = entity.vehicle!.position!.latitude!;
  const longitude = entity.vehicle!.position!.longitude!;
  let speedKmh: number | null = null;
  let intervalSeconds: number | null = null;
  let sustainedSlow = false;
  let observationDurationMinutes: number | null = null;
  let slowIntervalStreak = 0;
  let slowDurationSeconds = 0;
  let confidence: "Low" | "Medium" | "High" | null = null;
  if (
    previous != null && previous.route_id === routeId &&
    previous.trip_id === tripId
  ) {
    const previousTimestamp = Date.parse(previous.vehicle_timestamp);
    intervalSeconds = Math.round((timestamp * 1000 - previousTimestamp) / 1000);
    if (intervalSeconds >= 120 && intervalSeconds <= 600) {
      const travelled = distanceMetres(
        previous.latitude,
        previous.longitude,
        latitude,
        longitude,
      );
      speedKmh = travelled / intervalSeconds * 3.6;
      // STOPPED_AT is normal dwell, not evidence of road congestion. A
      // minimum movement speed also prevents GPS jitter from looking like a
      // traffic crawl. Three qualifying intervals (at least six minutes) are
      // required before a user-facing estimate is published.
      const movingSlow = entity.vehicle?.currentStatus !== 1 &&
        travelled >= 40 && speedKmh >= 1 && speedKmh <= 10;
      const previousSlow = previous.slow_interval_streak ??
        (previous.speed_kmh != null && previous.speed_kmh >= 1 &&
            previous.speed_kmh <= 10
          ? 1
          : 0);
      const previousDuration = previous.slow_duration_seconds ??
        (previousSlow > 0 ? previous.movement_interval_seconds ?? 0 : 0);
      slowIntervalStreak = movingSlow ? Math.min(20, previousSlow + 1) : 0;
      slowDurationSeconds = movingSlow
        ? Math.min(7200, previousDuration + intervalSeconds)
        : 0;
      sustainedSlow = slowIntervalStreak >= 3 && slowDurationSeconds >= 360;
      if (sustainedSlow) {
        observationDurationMinutes = Math.min(
          30,
          Math.round(slowDurationSeconds / 60),
        );
        confidence = slowIntervalStreak >= 5
          ? "High"
          : slowIntervalStreak >= 4
          ? "Medium"
          : "Low";
      }
    } else {
      intervalSeconds = null;
    }
  }

  return {
    vehicleId,
    routeId,
    tripId,
    vehicleTimestamp: new Date(timestamp * 1000).toISOString(),
    latitude,
    longitude,
    speedKmh,
    intervalSeconds,
    sustainedSlow,
    observationDurationMinutes,
    slowIntervalStreak,
    slowDurationSeconds,
    confidence,
  };
}

type RealtimeFeedResult = {
  category: string;
  entities: VehicleEntity[] | null;
  error: string | null;
};

async function loadRealtimeEntities(): Promise<{
  entities: VehicleEntity[];
  feeds: RealtimeFeedResult[];
}> {
  const feeds: RealtimeFeedResult[] = await Promise.all(
    realtimeFeeds.map(async ({ category, url }) => {
      try {
        const response = await fetch(url, {
          signal: AbortSignal.timeout(15_000),
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (bytes.length === 0) throw new Error("empty response");
        const feed = GtfsRealtimeBindings.transit_realtime.FeedMessage.decode(
          bytes,
        );
        return {
          category,
          entities: ((feed.entity ?? []) as VehicleEntity[]).map((entity) => ({
            ...entity,
            sourceCategory: category,
          })),
          error: null,
        };
      } catch (error) {
        return {
          category,
          entities: null,
          error: error instanceof Error ? error.message : "unknown error",
        };
      }
    }),
  );
  const successful = feeds.filter((feed) => feed.entities != null);
  if (successful.length === 0) {
    throw new Error(
      `all realtime feeds failed: ${
        feeds.map((feed) => `${feed.category}: ${feed.error}`).join("; ")
      }`,
    );
  }
  return {
    entities: successful.flatMap((feed) => feed.entities ?? []),
    feeds,
  };
}

async function saveFailure(
  supabase: SupabaseClient,
  now: Date,
  reason: string,
) {
  const { error: snapshotError } = await supabase.from("analytics_snapshots")
    .upsert(
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
  if (snapshotError) throw snapshotError;

  const { error: notificationError } = await supabase.from("notifications")
    .upsert(
      {
        notification_type: "service",
        title: "Realtime data unavailable",
        message:
          `NextRoute could not collect Kuala Lumpur bus realtime data: ${reason}`,
        severity: "high",
        origin: "appGenerated",
        dedupe_key: `data-health:${hourKey(now)}`,
        expires_at: new Date(now.getTime() + 2 * 60 * 60 * 1000).toISOString(),
      },
      { onConflict: "dedupe_key", ignoreDuplicates: true },
    );
  if (notificationError) throw notificationError;
}

export function analyzeVehicles(vehicles: VehicleEntity[], now: Date) {
  const routes = new Set<string>();
  const congestedByRoute = new Map<
    string,
    { congested: number; severe: number }
  >();
  let congestedCount = 0;
  let severeCount = 0;
  let reportedCount = 0;
  let freshCount = 0;
  let staleCount = 0;
  let unknownTimestampCount = 0;
  let freshReportedCount = 0;
  let freshCongestedCount = 0;
  let latestVehicleAt: number | null = null;

  for (const entity of vehicles) {
    const routeId = entity.vehicle?.trip?.routeId?.trim() || "Unknown route";
    if (routeId !== "Unknown route") routes.add(routeId);
    const level = entity.vehicle?.congestionLevel ?? 0;
    const reported = level >= 1 && level <= 4;
    if (reported) reportedCount++;
    const age = positionAge(entity, now);
    const fresh = age != null && age <= 300_000;
    if (age == null) unknownTimestampCount++;
    else {
      const timestamp = now.getTime() - age;
      latestVehicleAt = Math.max(latestVehicleAt ?? timestamp, timestamp);
      if (fresh) freshCount++;
      else staleCount++;
    }
    if (fresh && reported) freshReportedCount++;
    if (level !== 3 && level !== 4) continue;

    congestedCount += 1;
    if (level === 4) severeCount += 1;
    // Never publish a current congestion alert from stale/undated positions.
    if (!fresh) continue;
    freshCongestedCount++;
    const current = congestedByRoute.get(routeId) ?? {
      congested: 0,
      severe: 0,
    };
    current.congested += 1;
    if (level === 4) current.severe += 1;
    congestedByRoute.set(routeId, current);
  }

  return {
    routes,
    congestedByRoute,
    congestedCount,
    severeCount,
    reportedCount,
    freshCount,
    staleCount,
    unknownTimestampCount,
    freshReportedCount,
    freshCongestedCount,
    latestVehicleAt,
  };
}

export async function collectAnalytics(request: Request) {
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
    const realtime = await loadRealtimeEntities();
    const entities = realtime.entities;
    const vehicles = entities.filter(
      (entity) => entity.vehicle && validPosition(entity),
    );
    const {
      routes,
      congestedByRoute,
      congestedCount,
      severeCount,
      reportedCount,
      freshCount,
      staleCount,
      unknownTimestampCount,
      freshReportedCount,
      freshCongestedCount,
      latestVehicleAt,
    } = analyzeVehicles(vehicles, now);

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
          congestion_reported_vehicle_count: reportedCount,
          fresh_vehicle_count: freshCount,
          stale_vehicle_count: staleCount,
          unknown_timestamp_vehicle_count: unknownTimestampCount,
          fresh_congestion_reported_vehicle_count: freshReportedCount,
          fresh_congested_vehicle_count: freshCongestedCount,
          latest_vehicle_at: latestVehicleAt == null
            ? null
            : new Date(latestVehicleAt).toISOString(),
          fetch_succeeded: true,
          source,
        },
        { onConflict: "bucket_start,source" },
      );
    if (snapshotError) throw snapshotError;

    let movementSamples = 0;
    let possibleCongestionAlerts = 0;
    let movementError: string | null = null;
    try {
      const trackable = vehicles.filter((entity) =>
        vehicleIdentifier(entity) != null &&
        text(entity.vehicle?.trip?.routeId) != null &&
        text(entity.vehicle?.trip?.tripId) != null &&
        positionAge(entity, now) != null && positionAge(entity, now)! <= 300_000
      );
      const vehicleIds = [
        ...new Set(
          trackable.map(vehicleIdentifier).filter((id): id is string =>
            id != null
          ),
        ),
      ];
      const previousByVehicle = new Map<string, PreviousVehicleObservation[]>();
      if (vehicleIds.length > 0) {
        const { data, error } = await supabase
          .from("module5_vehicle_observations")
          .select(
            "vehicle_id,route_id,trip_id,latitude,longitude,vehicle_timestamp,speed_kmh,movement_interval_seconds,slow_interval_streak,slow_duration_seconds",
          )
          .in("vehicle_id", vehicleIds)
          .gte(
            "vehicle_timestamp",
            new Date(now.getTime() - 20 * 60_000).toISOString(),
          )
          .order("vehicle_timestamp", { ascending: false });
        if (error) throw error;
        for (const row of (data ?? []) as PreviousVehicleObservation[]) {
          const list = previousByVehicle.get(row.vehicle_id) ?? [];
          list.push(row);
          previousByVehicle.set(row.vehicle_id, list);
        }
      }

      const movements: MovementEstimate[] = [];
      for (const entity of trackable) {
        const vehicleId = vehicleIdentifier(entity)!;
        const currentTimestamp = Number(entity.vehicle?.timestamp?.toString()) *
          1000;
        const previous = (previousByVehicle.get(vehicleId) ?? []).find((row) =>
          Date.parse(row.vehicle_timestamp) < currentTimestamp
        ) ?? null;
        const movement = estimateMovement(entity, previous);
        if (movement != null) {
          movements.push(movement);
        }
      }
      movementSamples = movements.filter((item) =>
        item.speedKmh != null
      ).length;
      if (movements.length > 0) {
        const { error } = await supabase.from("module5_vehicle_observations")
          .upsert(
            movements.map((item) => ({
              vehicle_id: item.vehicleId,
              route_id: item.routeId,
              trip_id: item.tripId,
              latitude: item.latitude,
              longitude: item.longitude,
              vehicle_timestamp: item.vehicleTimestamp,
              observed_at: now.toISOString(),
              speed_kmh: item.speedKmh,
              movement_interval_seconds: item.intervalSeconds,
              slow_interval_streak: item.slowIntervalStreak,
              slow_duration_seconds: item.slowDurationSeconds,
              source,
            })),
            { onConflict: "vehicle_id,vehicle_timestamp" },
          );
        if (error) throw error;
      }
      const slowVehiclesByRoute = new Map<string, number>();
      for (const movement of movements.filter((item) => item.sustainedSlow)) {
        slowVehiclesByRoute.set(
          movement.routeId,
          (slowVehiclesByRoute.get(movement.routeId) ?? 0) + 1,
        );
      }
      for (const movement of movements.filter((item) => item.sustainedSlow)) {
        const routeCount = slowVehiclesByRoute.get(movement.routeId) ?? 1;
        const confidence = routeCount >= 3
          ? "High"
          : routeCount >= 2 && movement.confidence === "Low"
          ? "Medium"
          : movement.confidence ?? "Low";
        const { error } = await supabase.rpc(
          "module5_record_estimated_congestion",
          {
            route: movement.routeId,
            trip: movement.tripId,
            vehicle_label: movement.vehicleId,
            speed_kmh: movement.speedKmh,
            duration_minutes: movement.observationDurationMinutes,
            observed_at: movement.vehicleTimestamp,
            confidence,
          },
        );
        if (error) throw error;
        possibleCongestionAlerts++;
      }
      const { error: cleanupError } = await supabase
        .from("module5_vehicle_observations")
        .delete()
        .lt(
          "vehicle_timestamp",
          new Date(now.getTime() - 8 * 86_400_000).toISOString(),
        );
      if (cleanupError) throw cleanupError;
    } catch (error) {
      // Movement estimates are supplementary and must not discard a valid
      // service snapshot if observation storage is temporarily unavailable.
      movementError = error instanceof Error ? error.message : "unknown error";
      console.error("Movement estimation unavailable", error);
    }

    for (const [routeId, counts] of congestedByRoute) {
      const { error } = await supabase.rpc("module5_record_congestion", {
        route: routeId === "Unknown route" ? null : routeId,
        congested: counts.congested,
        severe: counts.severe,
        observed_at: now.toISOString(),
      });
      if (error) throw error;
    }

    const delayCandidateResult = findDelayCandidates(vehicles, now);
    const delayCandidates = delayCandidateResult.vehicles;
    const delayDiagnostics = delayCandidateResult.diagnostics;
    let delayEstimates = 0;
    let delayAlerts = 0;
    let delayScheduleMatches = 0;
    let delayEstimateRejections = 0;
    let delayError: string | null = null;
    if (delayCandidates.length > 0) {
      try {
        const schedules = await loadTripSchedules(delayCandidates);
        for (const entity of delayCandidates) {
          const tripId = text(entity.vehicle?.trip?.tripId);
          const schedule = tripId == null ? null : schedules.get(tripId);
          if (!schedule) continue;
          delayScheduleMatches++;
          const estimate = estimateDelay(entity, schedule, now);
          if (!estimate) {
            delayEstimateRejections++;
            continue;
          }
          delayEstimates++;
          const { error } = await supabase.rpc(
            "module5_record_estimated_delay",
            {
              route: estimate.routeId,
              trip: estimate.tripId,
              service_date: estimate.serviceDate,
              start_time: estimate.startTime,
              delay_minutes: estimate.delayMinutes,
              vehicle_label: estimate.vehicleLabel,
              from_stop: estimate.fromStop,
              to_stop: estimate.toStop,
              direction: estimate.direction,
              observed_stop_id: estimate.observedStopId,
              scheduled_arrival: estimate.scheduledArrival,
              estimated_arrival: estimate.estimatedArrival,
              observed_at: estimate.observedAt,
            },
          );
          if (error) throw error;
          if (estimate.delayMinutes >= delayThresholdMinutes) delayAlerts++;
        }
      } catch (error) {
        // Delay estimation is supplementary. A static timetable or RPC problem
        // must be visible to monitoring without discarding a valid live snapshot.
        delayError = error instanceof Error
          ? error.message
          : "unknown delay error";
        console.error("Delay estimation unavailable", error);
      }
    }

    return Response.json({
      captured_at: now.toISOString(),
      vehicles: vehicles.length,
      routes: routes.size,
      congested: congestedCount,
      severe: severeCount,
      delay_candidates: delayCandidates.length,
      delay_estimates: delayEstimates,
      delay_alerts: delayAlerts,
      delay_error: delayError,
      movement_samples: movementSamples,
      possible_congestion_alerts: possibleCongestionAlerts,
      movement_error: movementError,
      feed_sources: Object.fromEntries(
        realtime.feeds.map((feed) => [
          feed.category,
          {
            entities: feed.entities?.length ?? null,
            error: feed.error,
          },
        ]),
      ),
      delay_diagnostics: {
        total_vehicles: delayDiagnostics.totalVehicles,
        fresh_vehicles: delayDiagnostics.freshVehicles,
        stopped_vehicles: delayDiagnostics.stoppedVehicles,
        without_official_stop_reference:
          delayDiagnostics.withoutOfficialStopReference,
        schedule_matches: delayScheduleMatches,
        estimate_rejections: delayEstimateRejections,
        rejected: {
          stale_or_undated: delayDiagnostics.staleOrUndated,
          missing_trip_or_route: delayDiagnostics.missingTripOrRoute,
          missing_position: delayDiagnostics.missingPosition,
          no_schedule_match: delayCandidates.length - delayScheduleMatches,
        },
      },
    });
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unknown error";
    try {
      await saveFailure(supabase, now, reason);
    } catch (saveError) {
      console.error("Collector could not persist failure status", saveError);
      return Response.json({ error: "Collector storage failed." }, {
        status: 500,
      });
    }
    return Response.json({ error: reason }, { status: 502 });
  }
}

if (import.meta.main) Deno.serve(collectAnalytics);
