class GtfsTimetableCall {
  const GtfsTimetableCall({
    required this.stopId,
    required this.arrivalSeconds,
    required this.departureSeconds,
  });

  final String stopId;
  final int arrivalSeconds;
  final int departureSeconds;
}

class GtfsFrequencyWindow {
  const GtfsFrequencyWindow({
    required this.startSeconds,
    required this.endSeconds,
    required this.headwaySeconds,
  });

  final int startSeconds;
  final int endSeconds;
  final int headwaySeconds;
}

class GtfsTimetableTrip {
  const GtfsTimetableTrip({
    required this.id,
    required this.folder,
    required this.routeName,
    required this.serviceId,
    required this.calls,
    this.frequencies = const [],
  });

  final String id;
  final String folder;
  final String routeName;
  final String serviceId;
  final List<GtfsTimetableCall> calls;
  final List<GtfsFrequencyWindow> frequencies;
}

class GtfsServiceCalendar {
  const GtfsServiceCalendar({
    required this.weekdays,
    required this.startDate,
    required this.endDate,
    this.exceptions = const {},
  });

  final Set<int> weekdays;
  final DateTime startDate;
  final DateTime endDate;
  final Map<int, bool> exceptions;

  bool isActive(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final exception = exceptions[_dateKey(day)];
    if (exception != null) return exception;
    return !day.isBefore(startDate) &&
        !day.isAfter(endDate) &&
        weekdays.contains(day.weekday);
  }

  static int _dateKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;
}

class RouteServiceDayAvailability {
  const RouteServiceDayAvailability({
    required this.weekday,
    required this.date,
    required this.isAvailable,
    this.requestedDeparture,
    this.departure,
    this.arrival,
    this.nextDeparture,
    this.nextArrival,
  });

  final int weekday;
  final DateTime date;
  final bool isAvailable;
  final DateTime? requestedDeparture;
  final DateTime? departure;
  final DateTime? arrival;
  final DateTime? nextDeparture;
  final DateTime? nextArrival;

  int? get journeyDurationMinutes {
    final start = requestedDeparture ?? departure;
    final end = arrival;
    if (start == null || end == null) return null;
    return end.difference(start).inMinutes;
  }

  int? get nextJourneyDurationMinutes {
    final start = nextDeparture;
    final end = nextArrival;
    return start == null || end == null
        ? null
        : end.difference(start).inMinutes;
  }
}

class RouteServiceAvailability {
  const RouteServiceAvailability({required this.days});

  final List<RouteServiceDayAvailability> days;

  bool get isAvailable =>
      days.isNotEmpty && days.every((day) => day.isAvailable);

  Set<int> get unavailableWeekdays => {
    for (final day in days)
      if (!day.isAvailable) day.weekday,
  };

  int? get estimatedDurationMinutes {
    final values = days
        .where((day) => day.isAvailable)
        .map((day) => day.journeyDurationMinutes)
        .whereType<int>()
        .where((minutes) => minutes > 0)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((first, second) => first > second ? first : second);
  }

  DateTime? get nextDeparture {
    final values = days
        .where((day) => !day.isAvailable)
        .map((day) => day.nextDeparture)
        .whereType<DateTime>()
        .toList();
    if (values.isEmpty) return null;
    values.sort();
    return values.first;
  }

  int? get fallbackDurationMinutes {
    final values = days
        .map(
          (day) => day.journeyDurationMinutes ?? day.nextJourneyDurationMinutes,
        )
        .whereType<int>()
        .where((minutes) => minutes > 0)
        .toList();
    if (values.isEmpty) return null;
    return values.first;
  }
}

class GtfsRouteTimetableValidator {
  const GtfsRouteTimetableValidator({
    this.availabilityWindowMinutes = 60,
    this.maximumTransferWaitMinutes = 120,
  });

  final int availabilityWindowMinutes;
  final int maximumTransferWaitMinutes;

  RouteServiceAvailability validate({
    required List<GtfsTimetableTrip> trips,
    required Map<String, GtfsServiceCalendar> calendars,
    required Map<String, String> stopGroups,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
    required List<String> serviceSequence,
    required Set<int> weekdays,
    required int departureTimeMinutes,
    required DateTime referenceDate,
  }) {
    final sequence = serviceSequence
        .map(_normaliseService)
        .where((service) => service.isNotEmpty)
        .toList(growable: false);
    final selectedDays = weekdays.toList()..sort();
    final results = <RouteServiceDayAvailability>[];

    for (final weekday in selectedDays) {
      final date = _nextWeekday(referenceDate, weekday);
      final requested = DateTime(
        date.year,
        date.month,
        date.day,
      ).add(Duration(minutes: departureTimeMinutes));
      final journey = sequence.isEmpty
          ? null
          : _findJourney(
              trips: trips,
              calendars: calendars,
              stopGroups: stopGroups,
              originStopIds: originStopIds,
              destinationStopIds: destinationStopIds,
              serviceSequence: sequence,
              requested: requested,
            );
      final available =
          journey != null &&
          !journey.departure.isAfter(
            requested.add(Duration(minutes: availabilityWindowMinutes)),
          );
      results.add(
        RouteServiceDayAvailability(
          weekday: weekday,
          date: date,
          isAvailable: available,
          requestedDeparture: requested,
          departure: available ? journey.departure : null,
          arrival: available ? journey.arrival : null,
          nextDeparture: available ? null : journey?.departure,
          nextArrival: available ? null : journey?.arrival,
        ),
      );
    }
    return RouteServiceAvailability(days: results);
  }

  _Journey? _findJourney({
    required List<GtfsTimetableTrip> trips,
    required Map<String, GtfsServiceCalendar> calendars,
    required Map<String, String> stopGroups,
    required Set<String> originStopIds,
    required Set<String> destinationStopIds,
    required List<String> serviceSequence,
    required DateTime requested,
  }) {
    final runsByService = <String, List<_Run>>{};
    for (final service in serviceSequence.toSet()) {
      final matchingTrips = trips
          .where((trip) => _normaliseService(trip.routeName) == service)
          .toList(growable: false);
      final runs = <_Run>[];
      for (var dayOffset = -1; dayOffset <= 2; dayOffset++) {
        final serviceDay = DateTime(
          requested.year,
          requested.month,
          requested.day + dayOffset,
        );
        for (final trip in matchingTrips) {
          final calendar = calendars[trip.serviceId];
          if (calendar == null || !calendar.isActive(serviceDay)) continue;
          runs.addAll(_runsForTrip(trip, serviceDay));
        }
      }
      runs.sort(
        (first, second) =>
            first.calls.first.departure.compareTo(second.calls.first.departure),
      );
      runsByService[service] = runs;
    }

    var states = <_State>[];
    for (var legIndex = 0; legIndex < serviceSequence.length; legIndex++) {
      final runs = runsByService[serviceSequence[legIndex]] ?? const <_Run>[];
      final isFirst = legIndex == 0;
      final isLast = legIndex == serviceSequence.length - 1;
      final nextStates = <_State>[];
      final journeys = <_Journey>[];

      for (final run in runs) {
        for (
          var boardIndex = 0;
          boardIndex < run.calls.length - 1;
          boardIndex++
        ) {
          final board = run.calls[boardIndex];
          if (isFirst) {
            if (!_matchesSavedStop(board.stopId, originStopIds)) continue;
            if (board.departure.isBefore(requested) ||
                board.departure.isAfter(
                  requested.add(const Duration(hours: 36)),
                )) {
              continue;
            }
            _continueRun(
              run: run,
              boardIndex: boardIndex,
              firstDeparture: board.departure,
              isLast: isLast,
              destinationStopIds: destinationStopIds,
              stopGroups: stopGroups,
              states: nextStates,
              journeys: journeys,
            );
            continue;
          }

          for (final state in states) {
            if (_groupFor(board.stopId, stopGroups) != state.stopGroup) {
              continue;
            }
            final transferMinutes =
                state.folder == 'rail' && run.trip.folder == 'rail' ? 3 : 5;
            if (board.departure.isBefore(
              state.arrival.add(Duration(minutes: transferMinutes)),
            )) {
              continue;
            }
            if (board.departure.isAfter(
              state.arrival.add(Duration(minutes: maximumTransferWaitMinutes)),
            )) {
              continue;
            }
            _continueRun(
              run: run,
              boardIndex: boardIndex,
              firstDeparture: state.firstDeparture,
              isLast: isLast,
              destinationStopIds: destinationStopIds,
              stopGroups: stopGroups,
              states: nextStates,
              journeys: journeys,
            );
          }
        }
      }

      if (isLast) {
        if (journeys.isEmpty) return null;
        journeys.sort((first, second) {
          final departureOrder = first.departure.compareTo(second.departure);
          return departureOrder != 0
              ? departureOrder
              : first.arrival.compareTo(second.arrival);
        });
        return journeys.first;
      }
      states = _removeDominatedStates(nextStates);
      if (states.isEmpty) return null;
    }
    return null;
  }

  void _continueRun({
    required _Run run,
    required int boardIndex,
    required DateTime firstDeparture,
    required bool isLast,
    required Set<String> destinationStopIds,
    required Map<String, String> stopGroups,
    required List<_State> states,
    required List<_Journey> journeys,
  }) {
    for (var index = boardIndex + 1; index < run.calls.length; index++) {
      final alight = run.calls[index];
      if (isLast) {
        if (_matchesSavedStop(alight.stopId, destinationStopIds)) {
          journeys.add(
            _Journey(departure: firstDeparture, arrival: alight.arrival),
          );
          break;
        }
      } else {
        states.add(
          _State(
            stopGroup: _groupFor(alight.stopId, stopGroups),
            arrival: alight.arrival,
            firstDeparture: firstDeparture,
            folder: run.trip.folder,
          ),
        );
      }
    }
  }

  List<_Run> _runsForTrip(GtfsTimetableTrip trip, DateTime serviceDay) {
    if (trip.calls.length < 2) return const [];
    if (trip.frequencies.isEmpty) return [_Run.fromTrip(trip, serviceDay)];
    final runs = <_Run>[];
    final templateStart = trip.calls.first.departureSeconds;
    for (final frequency in trip.frequencies) {
      if (frequency.headwaySeconds <= 0) continue;
      for (
        var start = frequency.startSeconds;
        start < frequency.endSeconds;
        start += frequency.headwaySeconds
      ) {
        runs.add(
          _Run.fromTrip(trip, serviceDay, shiftSeconds: start - templateStart),
        );
      }
    }
    return runs;
  }

  List<_State> _removeDominatedStates(List<_State> states) {
    final kept = <String, List<_State>>{};
    for (final state in states) {
      final candidates = kept.putIfAbsent(state.stopGroup, () => []);
      if (candidates.any(
        (existing) =>
            !existing.arrival.isAfter(state.arrival) &&
            !existing.firstDeparture.isAfter(state.firstDeparture),
      )) {
        continue;
      }
      candidates.removeWhere(
        (existing) =>
            !state.arrival.isAfter(existing.arrival) &&
            !state.firstDeparture.isAfter(existing.firstDeparture),
      );
      candidates.add(state);
    }
    return kept.values.expand((values) => values).toList(growable: false);
  }

  static bool _matchesSavedStop(String stopId, Set<String> savedIds) {
    if (savedIds.contains(stopId)) return true;
    final clean = _withoutFolder(stopId);
    return savedIds.any((id) => _withoutFolder(id) == clean);
  }

  static String _groupFor(String stopId, Map<String, String> groups) =>
      groups[stopId] ?? stopId;

  static String _withoutFolder(String value) {
    final separator = value.indexOf('_');
    return separator < 0 ? value : value.substring(separator + 1);
  }

  static DateTime _nextWeekday(DateTime reference, int weekday) {
    final date = DateTime(reference.year, reference.month, reference.day);
    final offset = (weekday - date.weekday) % 7;
    return date.add(Duration(days: offset));
  }

  static String _normaliseService(String value) {
    var result = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s*\(\s*VIA\b.*\)\s*$'), '')
        .replaceAll(RegExp(r'\s+VIA\s+.*$'), '')
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (result.contains('KELANA JAYA') ||
        result == 'KJ' ||
        result == 'KJL' ||
        result == 'LINE 5') {
      result = 'KELANA JAYA';
    }
    return result;
  }
}

class _RunCall {
  const _RunCall({
    required this.stopId,
    required this.arrival,
    required this.departure,
  });

  final String stopId;
  final DateTime arrival;
  final DateTime departure;
}

class _Run {
  _Run.fromTrip(this.trip, DateTime serviceDay, {int shiftSeconds = 0})
    : calls = [
        for (final call in trip.calls)
          _RunCall(
            stopId: call.stopId,
            arrival: DateTime(
              serviceDay.year,
              serviceDay.month,
              serviceDay.day,
            ).add(Duration(seconds: call.arrivalSeconds + shiftSeconds)),
            departure: DateTime(
              serviceDay.year,
              serviceDay.month,
              serviceDay.day,
            ).add(Duration(seconds: call.departureSeconds + shiftSeconds)),
          ),
      ];

  final GtfsTimetableTrip trip;
  final List<_RunCall> calls;
}

class _State {
  const _State({
    required this.stopGroup,
    required this.arrival,
    required this.firstDeparture,
    required this.folder,
  });

  final String stopGroup;
  final DateTime arrival;
  final DateTime firstDeparture;
  final String folder;
}

class _Journey {
  const _Journey({required this.departure, required this.arrival});

  final DateTime departure;
  final DateTime arrival;
}
