import {
  analyzeVehicles,
  buildTripSchedules,
  estimateDelay,
  estimateMovement,
  findDelayCandidates,
  parseCsvRow,
  parseGtfsTime,
  type TripSchedule,
} from "./index.ts";
import { strToU8 } from "npm:fflate@0.8.2";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      "Expected " + JSON.stringify(expected) + ", got " +
        JSON.stringify(actual),
    );
  }
}
const now = new Date("2026-09-05T10:45:00Z");
const seconds = now.getTime() / 1000;
const vehicle = (level?: number, timestamp?: number) => ({
  vehicle: { congestionLevel: level, timestamp, trip: { routeId: "U6000" } },
});

Deno.test("missing congestion is unknown even with fresh positions", () => {
  const result = analyzeVehicles([vehicle(undefined, seconds)], now);
  equal(result.reportedCount, 0);
  equal(result.freshReportedCount, 0);
  equal(result.congestedCount, 0);
  equal(result.freshCount, 1);
  equal(result.congestedByRoute.size, 0);
});

Deno.test("known congestion uses only fresh known observations", () => {
  const result = analyzeVehicles([
    vehicle(1, seconds),
    vehicle(3, seconds),
    vehicle(4, seconds),
    vehicle(0, seconds),
    vehicle(4, seconds - 301),
    vehicle(3),
  ], now);
  equal(result.reportedCount, 5);
  equal(result.freshReportedCount, 3);
  equal(result.freshCongestedCount, 2);
  equal(result.freshCount, 4);
  equal(result.staleCount, 1);
  equal(result.unknownTimestampCount, 1);
  equal(result.congestedByRoute.get("U6000"), { congested: 2, severe: 1 });
});

Deno.test("empty feed and future timestamps cannot generate congestion alerts", () => {
  const empty = analyzeVehicles([], now);
  equal(empty.freshCount, 0);
  equal(empty.reportedCount, 0);
  const invalid = analyzeVehicles(
    [vehicle(4, seconds + 61), vehicle(3, 0)],
    now,
  );
  equal(invalid.unknownTimestampCount, 2);
  equal(invalid.congestedByRoute.size, 0);
});

Deno.test("five-minute age boundary is explicit", () => {
  const result = analyzeVehicles([
    vehicle(3, seconds - 300),
    vehicle(3, seconds - 301),
  ], now);
  equal(result.freshCount, 1);
  equal(result.staleCount, 1);
  equal(result.freshCongestedCount, 1);
});

Deno.test("delay candidate diagnostics explain every rejected vehicle", () => {
  const candidate = delayVehicle({ timestamp: seconds });
  const result = findDelayCandidates([
    candidate,
    delayVehicle({ timestamp: seconds - 301 }),
    delayVehicle({
      timestamp: seconds,
      currentStatus: 2,
      currentStopSequence: 0,
      stopId: "",
    }),
    delayVehicle({ timestamp: seconds, trip: { routeId: "U6000" } }),
    delayVehicle({ timestamp: seconds, position: {} }),
  ], now);
  equal(result.vehicles.length, 2);
  equal(result.diagnostics, {
    totalVehicles: 5,
    freshVehicles: 4,
    stoppedVehicles: 3,
    candidates: 2,
    staleOrUndated: 1,
    missingTripOrRoute: 1,
    missingPosition: 1,
    withoutOfficialStopReference: 1,
  });
});

Deno.test("GTFS time and CSV parsing handle timetable formats", () => {
  equal(parseGtfsTime("25:01:02"), 90062);
  equal(parseGtfsTime("10:61:00"), null);
  equal(parseCsvRow('route,"Stop, Main","Say ""Hi"""'), [
    "route",
    "Stop, Main",
    'Say "Hi"',
  ]);
});

Deno.test("static GTFS matches realtime trip suffix and service day", () => {
  const archive = Object.fromEntries(
    Object.entries({
      "trips.txt":
        "route_id,service_id,trip_id,shape_id,trip_headsign,direction_id\nU6000,weekday,weekday_U6000_U600001_0,x,,0\nU6000,weekend,weekend_U6000_U600001_0,x,,0\n",
      "stop_times.txt":
        "trip_id,arrival_time,departure_time,stop_id,stop_sequence,stop_headsign\nweekday_U6000_U600001_0,06:00:00,06:00:00,A,1,\nweekday_U6000_U600001_0,06:10:00,06:10:00,B,5,\nweekday_U6000_U600001_0,06:30:00,06:30:00,C,10,\n",
      "stops.txt":
        'stop_id,stop_name,stop_desc,stop_lat,stop_lon\nA,Stop A,,3,101\nB,Stop B,,3,101\nC,"Terminal, C",,3,101\n',
      "frequencies.txt":
        "trip_id,start_time,end_time,headway_secs,exact_times\nweekday_U6000_U600001_0,06:00:00,22:00:00,600,0\n",
    }).map(([name, value]) => [name, strToU8(value)]),
  );
  const schedules = buildTripSchedules(archive, [
    delayVehicle({
      trip: {
        routeId: "U6000",
        tripId: "U6000_U600001_0",
        startDate: "20260904",
        startTime: "10:00:00",
      },
    }),
  ]);
  equal(schedules.size, 1);
  equal(schedules.get("U6000_U600001_0")?.serviceId, "weekday");
  equal(schedules.get("U6000_U600001_0")?.frequencyBased, true);
  equal(schedules.get("U6000_U600001_0")?.stops[2].stopName, "Terminal, C");
});

Deno.test("static timetable without frequencies remains usable", () => {
  const archive = Object.fromEntries(
    Object.entries({
      "trips.txt":
        "route_id,service_id,trip_id,trip_headsign\n30000172,weekend,weekend_T2500_1200,Setapak Sentral\n",
      "stop_times.txt":
        "trip_id,arrival_time,departure_time,stop_id,stop_sequence\nweekend_T2500_1200,12:00:00,12:00:00,A,1\nweekend_T2500_1200,12:30:00,12:30:00,B,2\n",
      "stops.txt":
        "stop_id,stop_name,stop_lat,stop_lon\nA,Wangsa Maju,3,101\nB,Setapak Sentral,3,101\n",
    }).map(([name, value]) => [name, strToU8(value)]),
  );
  const schedules = buildTripSchedules(archive, [
    delayVehicle({
      trip: {
        routeId: "T2500",
        tripId: "T2500_1200",
        startDate: "20260905",
      },
    }),
  ]);
  equal(schedules.get("T2500_1200")?.frequencyBased, false);
  equal(schedules.get("T2500_1200")?.stops.length, 2);
  equal(schedules.get("T2500_1200")?.routeId, "T2500");
});

const schedule: TripSchedule = {
  staticTripId: "weekday_U6000_U600001_0",
  routeId: "U6000",
  serviceId: "weekday",
  headsign: null,
  frequencyBased: true,
  stops: [
    {
      sequence: 1,
      arrivalSeconds: 21600,
      stopId: "A",
      stopName: "Stop A",
      latitude: 3,
      longitude: 101,
    },
    {
      sequence: 5,
      arrivalSeconds: 22200,
      stopId: "B",
      stopName: "Stop B",
      latitude: 3.001,
      longitude: 101.001,
    },
    {
      sequence: 10,
      arrivalSeconds: 23400,
      stopId: "C",
      stopName: "Terminal C",
      latitude: 3.002,
      longitude: 101.002,
    },
  ],
};

function delayVehicle(overrides: Record<string, unknown> = {}) {
  return {
    vehicle: {
      timestamp: Date.parse("2026-09-04T02:18:00Z") / 1000,
      currentStatus: 1,
      currentStopSequence: 5,
      stopId: "B",
      position: { latitude: 3.001, longitude: 101.001 },
      trip: {
        routeId: "U6000",
        tripId: "U6000_U600001_0",
        startDate: "20260904",
        startTime: "10:00:00",
      },
      vehicle: { id: "vehicle-123" },
      ...overrides,
    },
  };
}

Deno.test("stopped vehicle produces an auditable downstream delay estimate", () => {
  const result = estimateDelay(
    delayVehicle(),
    schedule,
    new Date("2026-09-04T02:19:00Z"),
  );
  equal(result, {
    routeId: "U6000",
    tripId: "U6000_U600001_0",
    serviceDate: "20260904",
    startTime: "10:00:00",
    delayMinutes: 8,
    vehicleLabel: "vehicle-123",
    fromStop: "Stop B",
    toStop: "Terminal C",
    direction: "Terminal C",
    observedStopId: "B",
    scheduledArrival: "2026-09-04T02:30:00.000Z",
    estimatedArrival: "2026-09-04T02:38:00.000Z",
    observedAt: "2026-09-04T02:18:00.000Z",
    estimateMethod: "schedule_stop_observation",
  });
});

Deno.test("near-stop GPS position estimates delay when stop fields are absent", () => {
  const result = estimateDelay(
    delayVehicle({ currentStatus: 2, currentStopSequence: 0, stopId: "" }),
    schedule,
    new Date("2026-09-04T02:19:00Z"),
  );
  equal(result?.delayMinutes, 8);
  equal(result?.observedStopId, "B");
  equal(result?.estimateMethod, "schedule_near_stop_position");
});

Deno.test("unsafe or insufficient observations never invent a delay", () => {
  equal(
    estimateDelay(
      delayVehicle({
        currentStatus: 2,
        currentStopSequence: 0,
        stopId: "",
        position: { latitude: 4, longitude: 102 },
      }),
      schedule,
      new Date("2026-09-04T02:19:00Z"),
    ),
    null,
  );
  equal(
    estimateDelay(
      delayVehicle({ timestamp: Date.parse("2026-09-04T02:00:00Z") / 1000 }),
      schedule,
      new Date("2026-09-04T02:19:00Z"),
    ),
    null,
  );
  equal(
    estimateDelay(
      delayVehicle({
        trip: {
          routeId: "U6000",
          tripId: "U6000_U600001_0",
          startDate: "20260904",
        },
      }),
      schedule,
      new Date("2026-09-04T02:19:00Z"),
    ),
    null,
  );
  equal(
    estimateDelay(
      delayVehicle({ timestamp: Date.parse("2026-09-04T05:20:00Z") / 1000 }),
      schedule,
      new Date("2026-09-04T05:21:00Z"),
    ),
    null,
  );
});

Deno.test("three fresh low-speed intervals flag possible slow movement", () => {
  const result = estimateMovement(
    delayVehicle({
      currentStatus: 2,
      currentStopSequence: 0,
      stopId: "",
    }),
    {
      vehicle_id: "vehicle-123",
      route_id: "U6000",
      trip_id: "U6000_U600001_0",
      latitude: 3.0004,
      longitude: 101.0004,
      vehicle_timestamp: "2026-09-04T02:13:00.000Z",
      speed_kmh: 4,
      movement_interval_seconds: 300,
      slow_interval_streak: 2,
      slow_duration_seconds: 600,
    },
  );
  equal(result?.sustainedSlow, true);
  equal(result?.observationDurationMinutes, 15);
  equal(result?.slowIntervalStreak, 3);
  equal(result?.confidence, "Low");
});

Deno.test("one slow interval never becomes a congestion alert", () => {
  const result = estimateMovement(
    delayVehicle(),
    {
      vehicle_id: "vehicle-123",
      route_id: "U6000",
      trip_id: "U6000_U600001_0",
      latitude: 3.0007,
      longitude: 101.0007,
      vehicle_timestamp: "2026-09-04T02:13:00.000Z",
      speed_kmh: null,
      movement_interval_seconds: null,
    },
  );
  equal(result?.sustainedSlow, false);
});

Deno.test("reported stop dwell is never classified as congestion", () => {
  const result = estimateMovement(
    delayVehicle({ currentStatus: 1 }),
    {
      vehicle_id: "vehicle-123",
      route_id: "U6000",
      trip_id: "U6000_U600001_0",
      latitude: 3.0007,
      longitude: 101.0007,
      vehicle_timestamp: "2026-09-04T02:13:00.000Z",
      speed_kmh: 4,
      movement_interval_seconds: 300,
      slow_interval_streak: 4,
      slow_duration_seconds: 1200,
    },
  );
  equal(result?.sustainedSlow, false);
  equal(result?.slowIntervalStreak, 0);
});
