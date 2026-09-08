import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../services/gtfs_route_timetable.dart';
import '../services/personal_travel_service.dart';
import 'auth_screen.dart';
import 'favourite_routes.dart';
import 'journey_planning.dart';

enum _ProfilePage { dashboard, profile, history }

enum _HistoryFilter { all, today, lastSevenDays }

class PersonalTravelScreen extends StatefulWidget {
  const PersonalTravelScreen({
    super.key,
    this.service,
    this.imagePicker,
    this.savedRoutesRepository,
    this.savedPlacesRepository,
    this.dailyCommuteService,
    this.smartRoutineService,
    this.journeyApiService,
    this.journeyAuthenticate,
    this.onOpenJourneyPlanning,
    this.onAccountDeleted,
  });

  final PersonalTravelService? service;
  final ImagePicker? imagePicker;
  final SavedRoutesRepository? savedRoutesRepository;
  final SavedPlacesRepository? savedPlacesRepository;
  final DailyCommuteService? dailyCommuteService;
  final SmartRoutineService? smartRoutineService;
  final ApiService? journeyApiService;
  final Future<bool> Function(BuildContext)? journeyAuthenticate;
  final VoidCallback? onOpenJourneyPlanning;
  final VoidCallback? onAccountDeleted;

  @override
  State<PersonalTravelScreen> createState() => _PersonalTravelScreenState();
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: Color(0xFFDC3545),
        size: 34,
      ),
      title: const Text('Delete Account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is permanent. Your profile, travel history, favourite routes, reminders and saved places will also be deleted.',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 16),
            const Text(
              'Type DELETE to confirm',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            TextField(
              key: const Key('delete-account-confirmation'),
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'DELETE',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-delete-account'),
          onPressed: _controller.text.trim() == 'DELETE'
              ? () => Navigator.pop(context, true)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC3545),
          ),
          child: const Text('Delete Account'),
        ),
      ],
    );
  }
}

class _PersonalTravelScreenState extends State<PersonalTravelScreen> {
  static const _navy = Color(0xFF173A7A);
  static const _blue = Color(0xFF2862E9);
  static const _pageBackground = Color(0xFFF3F6FA);
  static const _border = Color(0xFFE6EBF2);

  late final PersonalTravelService _service;
  late final ImagePicker _imagePicker;
  late final SavedRoutesRepository _savedRoutesRepository;
  DailyCommuteService? _dailyCommuteService;
  late final SmartRoutineService _smartRoutineService;
  _ProfilePage _page = _ProfilePage.dashboard;
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  bool _isUploadingAvatar = false;
  bool _isLoadingHistory = true;
  bool _isLoadingDailyCommute = true;
  String _displayName = 'Loading...';
  String _email = '';
  String _phoneNumber = '';
  String _historySearch = '';
  int? _savedRoutesCount;
  String? _avatarUrl;
  DateTime? _memberSince;
  List<TravelHistoryEntry> _history = const [];
  List<DailyCommute> _dailyCommutes = const [];
  String? _dismissedRoutineKey;
  bool _isPreparingRoutine = false;
  bool _isDeletingAccount = false;
  bool _didSyncDailyCommuteNotifications = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PersonalTravelService();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    _savedRoutesRepository =
        widget.savedRoutesRepository ?? SupabaseSavedRoutesRepository();
    _dailyCommuteService =
        widget.dailyCommuteService ??
        (widget.service == null ? DailyCommuteService() : null);
    _smartRoutineService =
        widget.smartRoutineService ??
        SmartRoutineService(_savedRoutesRepository);
    _loadProfile();
    _loadSavedRoutes();
    _loadHistory();
    _loadDailyCommute();
  }

  Future<void> _loadDailyCommute() async {
    _isLoadingDailyCommute = true;
    final service = _dailyCommuteService;
    if (service == null) {
      _isLoadingDailyCommute = false;
      return;
    }
    try {
      final commutes = await service.loadAll();
      if (!_didSyncDailyCommuteNotifications) {
        _didSyncDailyCommuteNotifications = true;
        try {
          await service.syncNotifications(commutes);
        } catch (_) {
          // Loading the dashboard should still succeed if the OS rejects a
          // notification refresh. A later save/toggle will schedule again.
        }
      }
      if (mounted) {
        setState(() {
          _dailyCommutes = commutes;
          _isLoadingDailyCommute = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dailyCommutes = const [];
          _isLoadingDailyCommute = false;
        });
      }
    }
  }

  Future<void> _openDailyCommuteSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.72,
        child: DailyCommuteOverviewSheet(
          service: _dailyCommuteService,
          savedRoutesRepository: widget.savedRoutesRepository,
          onOpenJourneyPlanning: widget.onOpenJourneyPlanning,
        ),
      ),
    );
    if (!mounted) return;
    await _loadDailyCommute();
    await _loadSavedRoutes();
  }

  RoutineSuggestion? get _routineSuggestion {
    if (_isLoadingHistory || _isLoadingDailyCommute) return null;
    final suggestion = SmartRoutineService.detect(
      history: _history,
      configuredCommutes: _dailyCommutes
          .map(
            (commute) => DailyCommuteRoute(
              origin: commute.origin,
              destination: commute.destination,
            ),
          )
          .toList(),
    );
    return suggestion?.routeKey == _dismissedRoutineKey ? null : suggestion;
  }

  Future<void> _useRoutineSuggestion(RoutineSuggestion suggestion) async {
    if (_isPreparingRoutine) return;
    setState(() => _isPreparingRoutine = true);
    try {
      final route = await _smartRoutineService.findOrCreateFavourite(
        suggestion,
      );
      if (!mounted) return;
      await Navigator.push<DailyCommute>(
        context,
        MaterialPageRoute(
          builder: (_) => DailyCommuteSettingsScreen(
            service: _dailyCommuteService,
            savedRoutesRepository: _savedRoutesRepository,
            initialRoute: route,
            initialActiveDays: suggestion.commonWeekdays,
            addFavouriteJourney: widget.onOpenJourneyPlanning == null
                ? null
                : (settingsContext) async {
                    Navigator.pop(settingsContext);
                    widget.onOpenJourneyPlanning!();
                  },
          ),
        ),
      );
      if (!mounted) return;
      await Future.wait([
        _loadDailyCommute(),
        _loadSavedRoutes(),
        _loadHistory(),
      ]);
    } catch (error) {
      if (error is RoutineRouteUnavailableException && mounted) {
        await _offerRoutineRouteRefresh(suggestion);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_routineErrorMessage(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreparingRoutine = false);
    }
  }

  Future<void> _offerRoutineRouteRefresh(RoutineSuggestion suggestion) async {
    final continueToSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.route_outlined, color: _blue),
        title: const Text('Route needs refreshing'),
        content: Text(
          '${suggestion.origin} → ${suggestion.destination} does not have '
          'reusable route details. Add or select a Favourite Journey to '
          'continue setting up this Daily Commute.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('continue-routine-with-favourite'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (continueToSettings != true || !mounted) return;
    await Navigator.push<DailyCommute>(
      context,
      MaterialPageRoute(
        builder: (_) => DailyCommuteSettingsScreen(
          service: _dailyCommuteService,
          savedRoutesRepository: _savedRoutesRepository,
          initialActiveDays: suggestion.commonWeekdays,
        ),
      ),
    );
    if (!mounted) return;
    await Future.wait([
      _loadDailyCommute(),
      _loadSavedRoutes(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadProfile({String? confirmedEmail}) async {
    try {
      final profile = await _service.loadProfile(
        confirmedEmail: confirmedEmail,
      );
      if (!mounted) return;
      setState(() {
        _displayName = profile.displayName;
        _email = profile.email;
        _phoneNumber = profile.phoneNumber;
        _avatarUrl = profile.avatarUrl;
        _memberSince = profile.memberSince;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to load profile.')));
      }
    }
  }

  Future<void> _loadSavedRoutes() async {
    try {
      final routes = await _savedRoutesRepository.load();
      if (!mounted) return;
      setState(() {
        _savedRoutesCount = routes.length;
      });
    } catch (_) {
      if (mounted) setState(() => _savedRoutesCount = null);
    }
  }

  Future<void> _loadHistory() async {
    if (mounted) setState(() => _isLoadingHistory = true);
    try {
      final history = await _service.loadTravelHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _openFavouriteRoutes() async {
    var addRoute = false;
    final route = await showModalBottomSheet<SavedRoute>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.72,
        child: FavouriteRoutesScreen(
          repository: widget.savedRoutesRepository,
          sheetMode: true,
          onAddRoute: () {
            addRoute = true;
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
    if (!mounted) return;
    await _loadSavedRoutes();
    if (!mounted) return;
    if (addRoute) {
      final onOpenJourneyPlanning = widget.onOpenJourneyPlanning;
      if (onOpenJourneyPlanning != null) {
        onOpenJourneyPlanning();
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const JourneyPlanningScreen()),
      );
      if (mounted) await _loadSavedRoutes();
      return;
    }
    if (route != null && mounted) await _openJourney(route);
  }

  Future<void> _openSavedPlaces() async {
    final repository =
        widget.savedPlacesRepository ?? SupabaseSavedPlacesRepository();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SavedPlacesScreen(repository: repository),
      ),
    );
  }

  Future<void> _openJourneyPlanning() async {
    final onOpenJourneyPlanning = widget.onOpenJourneyPlanning;
    if (onOpenJourneyPlanning != null) {
      onOpenJourneyPlanning();
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const JourneyPlanningScreen()),
    );
    if (mounted) {
      await _loadSavedRoutes();
      await _loadHistory();
    }
  }

  Future<void> _openJourney(SavedRoute route) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JourneyPlanningScreen(savedRoute: route),
      ),
    );
    if (mounted) {
      await _loadSavedRoutes();
      await _loadHistory();
    }
  }

  Future<void> _startJourneyAgain(TravelHistoryEntry entry) async {
    final apiService = widget.journeyApiService ?? ApiService();
    var origin = entry.originStation;
    var destination = entry.destinationStation;

    try {
      if (origin == null || destination == null) {
        final stations = await apiService.loadAllStations();
        origin ??= _matchHistoryStation(stations, entry.origin);
        destination ??= _matchHistoryStation(stations, entry.destination);
      }

      if (origin == null || destination == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This older trip can no longer be matched to the current station list.',
            ),
          ),
        );
        return;
      }

      final services = SavedRoute.servicesFromLineName(entry.lineName);
      final transportModes = entry.transitSteps
          .map((step) => step.mode)
          .toList(growable: false);
      final signature = entry.routeSignature.trim().isNotEmpty
          ? entry.routeSignature
          : SavedRoute.stableSignatureFor(services, transportModes);
      final route = SavedRoute(
        name: '${entry.origin} → ${entry.destination}',
        origin: origin,
        destination: destination,
        signature: signature,
        lineName: entry.lineName,
        serviceSequence: services,
        transportModes: transportModes,
      );

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => JourneyPlanningScreen(
            savedRoute: route,
            apiService: apiService,
            savedRoutesRepository: widget.savedRoutesRepository,
            savedPlacesRepository: widget.savedPlacesRepository,
            authenticate: widget.journeyAuthenticate,
          ),
        ),
      );
      if (mounted) await _loadHistory();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to prepare this journey right now. Please try again.',
          ),
        ),
      );
    }
  }

  StationModel? _matchHistoryStation(
    Iterable<StationModel> stations,
    String historyName,
  ) {
    final key = _historyStationKey(historyName);
    if (key.isEmpty) return null;
    for (final station in stations) {
      if (_historyStationKey(station.name) == key) return station;
    }
    return null;
  }

  String _historyStationKey(String value) => value
      .toUpperCase()
      .replaceAll(RegExp(r'\(\s*OPP\s*\)'), '')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '');

  Future<void> _openEditProfile() async {
    final confirmedEmail = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => EditProfileScreen(
          displayName: _displayName,
          email: _email,
          phoneNumber: _phoneNumber,
          service: _service,
        ),
      ),
    );
    if (mounted) await _loadProfile(confirmedEmail: confirmedEmail);
  }

  Future<void> _confirmDeleteAccount() async {
    if (_isDeletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await _service.deleteAccount(confirmation: 'DELETE');
      if (!mounted) return;
      final onAccountDeleted = widget.onAccountDeleted;
      if (onAccountDeleted != null) {
        onAccountDeleted();
      } else {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_accountDeletionMessage(error)),
          backgroundColor: const Color(0xFFB42318),
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }

  String _accountDeletionMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('status: 404') ||
        raw.contains('NOT_FOUND') ||
        raw.contains('Requested function was not found')) {
      return 'Account deletion is not available yet. Deploy the delete-account Edge Function first.';
    }
    if (raw.contains('status: 401') || raw.toLowerCase().contains('session')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (error is FormatException || error is StateError) {
      return raw
          .replaceFirst('Bad state: ', '')
          .replaceFirst('FormatException: ', '');
    }
    return 'Account deletion failed. Nothing was deleted. Please try again.';
  }

  Future<void> _changePassword() async {
    final changed = await showChangePasswordDialog(context, service: _service);
    if (changed == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password updated successfully.')));
    }
  }

  Future<void> _pickAvatar() async {
    if (_isUploadingAvatar) return;
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (image == null || !mounted) return;
    setState(() => _isUploadingAvatar = true);
    try {
      final bytes = await image.readAsBytes();
      final extension = image.name.split('.').last.toLowerCase();
      final contentType =
          image.mimeType ??
          switch (extension) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            _ => 'image/jpeg',
          };
      final avatarUrl = await _service.uploadAvatar(
        bytes,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() => _avatarUrl = avatarUrl);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Profile photo updated.')));
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'Unable to upload photo. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page == _ProfilePage.dashboard
          ? _pageBackground
          : _navy,
      body: SafeArea(
        bottom: false,
        child: switch (_page) {
          _ProfilePage.dashboard => _buildDashboard(),
          _ProfilePage.profile => _buildProfilePage(),
          _ProfilePage.history => _buildHistoryPage(),
        },
      ),
    );
  }

  Widget _buildDashboard() {
    final firstName = _displayName.trim().split(RegExp(r'\s+')).first;
    final recent = _history.isEmpty ? null : _history.first;
    final routineSuggestion = _routineSuggestion;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadProfile(),
          _loadSavedRoutes(),
          _loadHistory(),
          _loadDailyCommute(),
        ]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: _blue,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        key: const Key('dashboard-home'),
                        onTap:
                            widget.onOpenJourneyPlanning ??
                            () => Navigator.maybePop(context),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chevron_left,
                                color: Colors.white,
                                size: 20,
                              ),
                              Text(
                                'Home',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        key: const Key('dashboard-avatar'),
                        onTap: () =>
                            setState(() => _page = _ProfilePage.profile),
                        borderRadius: BorderRadius.circular(22),
                        child: _avatar(radius: 20, showUpload: false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dashboard',
                    style: TextStyle(
                      color: Color(0xFFD9E5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_greeting()}, ${firstName == 'Loading...' ? 'there' : firstName} 👋',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
            sliver: SliverList.list(
              children: [
                _sectionLabel('NEXT COMMUTE'),
                const SizedBox(height: 8),
                _commuteCard(),
                if (routineSuggestion != null) ...[
                  const SizedBox(height: 16),
                  _smartRoutineCard(routineSuggestion),
                ],
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _reminderCard()),
                      const SizedBox(width: 10),
                      Expanded(child: _recentTripCard(recent)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('QUICK ACCESS'),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.55,
                  children: [
                    _quickAccessCard(
                      key: const Key('open-my-profile'),
                      icon: Icons.person_outline,
                      iconColor: _blue,
                      iconBackground: const Color(0xFFEAF2FF),
                      label: 'My Profile',
                      onTap: () => setState(() => _page = _ProfilePage.profile),
                    ),
                    _quickAccessCard(
                      icon: Icons.star_border_rounded,
                      iconColor: const Color(0xFFEF4E5B),
                      iconBackground: const Color(0xFFFFECEE),
                      label: 'Favourite Routes',
                      onTap: _openFavouriteRoutes,
                    ),
                    _quickAccessCard(
                      key: const Key('open-travel-history'),
                      icon: Icons.history_rounded,
                      iconColor: const Color(0xFF8056E8),
                      iconBackground: const Color(0xFFF0EAFF),
                      label: 'Travel History',
                      onTap: () {
                        setState(() => _page = _ProfilePage.history);
                        _loadHistory();
                      },
                    ),
                    _quickAccessCard(
                      icon: Icons.notifications_none_rounded,
                      iconColor: const Color(0xFFE88B17),
                      iconBackground: const Color(0xFFFFF2DE),
                      label: 'Smart Reminders',
                      onTap: _openDailyCommuteSettings,
                    ),
                    _quickAccessCard(
                      key: const Key('open-saved-places'),
                      icon: Icons.bookmark_border_rounded,
                      iconColor: const Color(0xFF16A085),
                      iconBackground: const Color(0xFFE7F8F3),
                      label: 'Saved Places',
                      onTap: _openSavedPlaces,
                    ),
                    _quickAccessCard(
                      key: const Key('open-journey-planning'),
                      icon: Icons.route_rounded,
                      iconColor: _navy,
                      iconBackground: const Color(0xFFE8EEFA),
                      label: 'Plan Journey',
                      onTap: _openJourneyPlanning,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    return Column(
      children: [
        _innerTopBar(),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              children: [
                const Center(child: _DragHandle()),
                Row(
                  children: [
                    const Text(
                      'My Profile',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    _closeButton(),
                  ],
                ),
                const SizedBox(height: 3),
                Center(child: _avatar(radius: 45, showUpload: true)),
                const SizedBox(height: 12),
                Text(
                  _displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF8A94A6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, color: _blue, size: 7),
                        const SizedBox(width: 5),
                        Text(
                          'Member since ${_memberSinceLabel()}',
                          style: const TextStyle(color: _blue, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _statCard('${_history.length}', 'Trips')),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statCard(
                        _savedRoutesCount?.toString() ?? '—',
                        'Saved Routes',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statCard(
                        '${_activeReminderCount()}',
                        'Reminders',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                _profileAction(
                  key: const Key('edit-profile-action'),
                  icon: Icons.edit_outlined,
                  iconColor: _blue,
                  iconBackground: const Color(0xFFEAF2FF),
                  label: 'Edit Profile',
                  onTap: _openEditProfile,
                ),
                const SizedBox(height: 9),
                _profileAction(
                  key: const Key('change-password-action'),
                  icon: Icons.lock_outline_rounded,
                  iconColor: const Color(0xFF8E62E8),
                  iconBackground: const Color(0xFFF0EAFF),
                  label: 'Change Password',
                  onTap: _changePassword,
                ),
                const SizedBox(height: 9),
                _profileAction(
                  icon: Icons.logout_rounded,
                  iconColor: const Color(0xFFEF4E5B),
                  iconBackground: const Color(0xFFFFECEE),
                  label: 'Sign Out',
                  labelColor: const Color(0xFFEF4E5B),
                  borderColor: const Color(0xFFFFD8DC),
                  showChevron: false,
                  onTap: () => Supabase.instance.client.auth.signOut(),
                ),
                const SizedBox(height: 24),
                const Text(
                  'DANGER ZONE',
                  style: TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Permanently remove your account and personal travel data.',
                  style: TextStyle(
                    color: Color(0xFF8290A5),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                _profileAction(
                  key: const Key('delete-account-action'),
                  icon: Icons.delete_forever_outlined,
                  iconColor: const Color(0xFFB42318),
                  iconBackground: const Color(0xFFFFECEE),
                  label: _isDeletingAccount
                      ? 'Deleting Account...'
                      : 'Delete Account',
                  labelColor: const Color(0xFFB42318),
                  borderColor: const Color(0xFFF5B7BD),
                  showChevron: false,
                  onTap: _isDeletingAccount ? () {} : _confirmDeleteAccount,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryPage() {
    final entries = _filteredHistory();
    final grouped = <String, List<TravelHistoryEntry>>{};
    for (final entry in entries) {
      grouped
          .putIfAbsent(_historySection(entry.createdAt), () => [])
          .add(entry);
    }
    return Column(
      children: [
        _innerTopBar(),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: _DragHandle(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 1, 10, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Travel History',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        key: const Key('history-filter'),
                        onPressed: _showHistoryFilter,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF536176),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          side: const BorderSide(color: _border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: const Icon(Icons.filter_alt_outlined, size: 15),
                        label: Text(
                          _historyFilterLabel(),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 7),
                      _closeButton(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: TextField(
                    key: const Key('history-search'),
                    onChanged: (value) =>
                        setState(() => _historySearch = value),
                    decoration: InputDecoration(
                      hintText: 'Search trips...',
                      hintStyle: const TextStyle(
                        color: Color(0xFF9BA6B7),
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 19,
                        color: Color(0xFF9BA6B7),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7F9FC),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _border),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoadingHistory
                      ? const Center(child: CircularProgressIndicator())
                      : entries.isEmpty
                      ? _emptyHistory()
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                            itemCount: grouped.length,
                            itemBuilder: (context, index) {
                              final section = grouped.entries.elementAt(index);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: index == 0 ? 2 : 12,
                                      bottom: 7,
                                    ),
                                    child: _sectionLabel(section.key),
                                  ),
                                  ...section.value.map(_historyRow),
                                ],
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _innerTopBar() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: _navy,
      child: Row(
        children: [
          InkWell(
            onTap: () => setState(() => _page = _ProfilePage.dashboard),
            borderRadius: BorderRadius.circular(18),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Row(
                children: [
                  Icon(Icons.chevron_left, color: Colors.white70, size: 19),
                  Text(
                    'Home',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _avatar(radius: 18, showUpload: false),
        ],
      ),
    );
  }

  Widget _avatar({required double radius, required bool showUpload}) {
    final avatar = CircleAvatar(
      key: showUpload ? const Key('profile-avatar') : null,
      radius: radius,
      backgroundColor: showUpload
          ? _blue
          : Colors.white.withValues(alpha: 0.16),
      backgroundImage: _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
      child: _avatarUrl == null
          ? Text(
              _initials(),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.62,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
    if (!showUpload) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -5,
          bottom: -4,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              key: const Key('change-profile-photo'),
              tooltip: 'Change profile photo',
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              onPressed: _isUploadingAvatar ? null : _pickAvatar,
              icon: _isUploadingAvatar
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.camera_alt_outlined,
                      color: _blue,
                      size: 17,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _commuteCard() {
    final commute = _dashboardCommute;
    return _surfaceCard(
      onTap: _openDailyCommuteSettings,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Row(
          children: [
            _softIcon(
              Icons.directions_transit_rounded,
              _blue,
              const Color(0xFFEAF2FF),
              size: 42,
              iconSize: 22,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    commute == null
                        ? 'Set up your Daily Commute'
                        : '${commute.origin} → ${commute.destination}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF172033),
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    commute == null
                        ? 'Choose a route and departure time'
                        : commute.hasServiceWarning
                        ? 'No scheduled service around this departure time'
                        : '${commute.estimatedDurationMinutes} min  •  ${_activeDaysLabel(commute.activeDays)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  commute == null ? 'SET UP' : 'DEPARTURE',
                  style: const TextStyle(
                    color: Color(0xFF8290A5),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  commute == null
                      ? 'Commute'
                      : _formatMinutes(commute.departureTimeMinutes),
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reminderCard() {
    final next = _nextReminder;
    final commute = next?.commute;
    final nextReminder = next?.time;
    return _surfaceCard(
      onTap: _openDailyCommuteSettings,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _softIcon(
                Icons.notifications_none_rounded,
                const Color(0xFFE88B17),
                const Color(0xFFFFF2DE),
                size: 31,
                iconSize: 18,
              ),
              const SizedBox(width: 8),
              Expanded(child: _sectionLabel('NEXT REMINDER')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            commute == null
                ? 'Set up commute'
                : nextReminder == null
                ? 'No reminder scheduled'
                : '${_weekdayName(nextReminder.weekday)} ${_formatMinutes(nextReminder.hour * 60 + nextReminder.minute)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            commute == null
                ? 'Tap to configure'
                : nextReminder == null
                ? (commute.reminderEnabled
                      ? 'Choose at least one active day'
                      : 'Reminder is turned off')
                : commute.hasServiceWarning
                ? '${commute.origin} → ${commute.destination}\nNo scheduled service around this departure time'
                : '${commute.origin} → ${commute.destination}\n${commute.reminderMinutesBefore} min before departure',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smartRoutineCard(RoutineSuggestion suggestion) {
    return _surfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _softIcon(
                Icons.auto_awesome_rounded,
                _blue,
                const Color(0xFFEAF2FF),
              ),
              const SizedBox(width: 9),
              Expanded(child: _sectionLabel('SMART ROUTINE SUGGESTION')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'We noticed you frequently travel',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 7),
          Text(
            '${suggestion.origin}\n→\n${suggestion.destination}',
            style: const TextStyle(
              color: _navy,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '${suggestion.tripCount} trips in the last 30 days',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (suggestion.commonWeekdays.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Frequently travelled on ${_activeDaysLabel(suggestion.commonWeekdays)}',
              style: const TextStyle(color: Color(0xFF8290A5), fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('set-routine-as-commute'),
                  onPressed: _isPreparingRoutine
                      ? null
                      : () => _useRoutineSuggestion(suggestion),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  child: _isPreparingRoutine
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Set as Daily Commute'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('dismiss-routine-suggestion'),
                onPressed: () =>
                    setState(() => _dismissedRoutineKey = suggestion.routeKey),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recentTripCard(TravelHistoryEntry? trip) {
    return _surfaceCard(
      onTap: () => setState(() => _page = _ProfilePage.history),
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _softIcon(
                Icons.history_rounded,
                const Color(0xFF8056E8),
                const Color(0xFFF0EAFF),
                size: 31,
                iconSize: 18,
              ),
              const SizedBox(width: 8),
              Expanded(child: _sectionLabel('RECENT TRIP')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            trip == null
                ? 'No recent trips'
                : '${trip.origin} → ${trip.destination}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            trip == null
                ? 'Plan a journey to begin'
                : 'RM ${trip.fare.toStringAsFixed(2)}\n${_friendlyRecentDate(trip.createdAt)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF718096),
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAccessCard({
    Key? key,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String label,
    required VoidCallback onTap,
  }) {
    return _surfaceCard(
      key: key,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF263044),
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _surfaceCard({
    Key? key,
    required Widget child,
    required EdgeInsets padding,
    VoidCallback? onTap,
  }) {
    return Material(
      key: key,
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _softIcon(
    IconData icon,
    Color color,
    Color background, {
    double size = 34,
    double iconSize = 19,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }

  Widget _statCard(String value, String label) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8A94A6), fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _profileAction({
    Key? key,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String label,
    required VoidCallback onTap,
    Color labelColor = const Color(0xFF2A3140),
    Color borderColor = _border,
    bool showChevron = true,
  }) {
    return Material(
      key: key,
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              _softIcon(icon, iconColor, iconBackground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showChevron)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB0B8C5),
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _closeButton() {
    return Material(
      color: const Color(0xFFF1F4F8),
      shape: const CircleBorder(),
      child: InkWell(
        key: const Key('close-profile-page'),
        onTap: () => setState(() => _page = _ProfilePage.dashboard),
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 31,
          height: 31,
          child: Icon(Icons.close, size: 17, color: Color(0xFF9BA6B7)),
        ),
      ),
    );
  }

  Widget _emptyHistory() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _softIcon(Icons.route_outlined, _blue, const Color(0xFFEAF2FF)),
            const SizedBox(height: 12),
            const Text(
              'No trips found',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            const Text(
              'Your completed journeys will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A94A6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(TravelHistoryEntry entry) {
    final line = _lineDetails(entry.lineName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          key: Key('history-trip-${entry.createdAt.toIso8601String()}'),
          onTap: () => _showTripDetails(entry),
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            child: Row(
              children: [
                _lineBadge(line.$1, line.$2, large: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${entry.origin} → ${entry.destination}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _timeLabel(entry),
                        style: const TextStyle(
                          color: Color(0xFF8290A5),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_currencyLabel(entry.currency)} ${entry.fare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF9BA6B7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTripDetails(TravelHistoryEntry entry) async {
    final line = _lineDetails(entry.lineName);
    final startAgain = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Trip Details',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('close-trip-details'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: _border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _lineBadge(line.$1, line.$2, large: true),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  entry.lineName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F7ED),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'COMPLETED',
                                  style: TextStyle(
                                    color: Color(0xFF25824E),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            entry.origin,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Icon(
                              Icons.south_rounded,
                              size: 18,
                              color: _blue,
                            ),
                          ),
                          Text(
                            entry.destination,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          _tripMetric('DEPART', _timeLabel(entry)),
                          _metricDivider(),
                          _tripMetric(
                            'ARRIVE',
                            _storedTimeLabel(entry.estimatedArrivalTime),
                          ),
                          _metricDivider(),
                          _tripMetric(
                            'DURATION',
                            entry.durationMinutes > 0
                                ? '${entry.durationMinutes} min'
                                : '—',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _detailTile(
                            Icons.payments_outlined,
                            'TOTAL FARE',
                            '${_currencyLabel(entry.currency)} ${entry.fare.toStringAsFixed(2)}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _detailTile(
                            Icons.calendar_today_outlined,
                            'TRIP DATE',
                            _historySection(entry.createdAt),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('JOURNEY DETAILS'),
                    const SizedBox(height: 9),
                    if (entry.transitSteps.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F9FC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'Detailed transit steps were not recorded for this trip.',
                          style: TextStyle(
                            color: Color(0xFF6F7C90),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ...entry.transitSteps.indexed.map(
                        (indexedStep) => _tripStep(
                          indexedStep.$2,
                          isLast:
                              indexedStep.$1 == entry.transitSteps.length - 1,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('start-journey-again'),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text(
                      'Start Journey Again',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (startAgain == true && mounted) {
      await _startJourneyAgain(entry);
    }
  }

  Widget _tripMetric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8290A5),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _metricDivider() => Container(width: 1, height: 34, color: _border);

  Widget _detailTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: _blue),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8290A5),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripStep(TravelHistoryStep step, {required bool isLast}) {
    final mode = step.mode.toLowerCase();
    final icon = mode.contains('walk')
        ? Icons.directions_walk_rounded
        : mode.contains('bus')
        ? Icons.directions_bus_rounded
        : mode.contains('rail') || mode.contains('train')
        ? Icons.train_rounded
        : Icons.route_rounded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFEAF2FF),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: _blue),
            ),
            if (!isLast)
              Container(width: 2, height: 38, color: const Color(0xFFC9DAFF)),
          ],
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1, bottom: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (step.duration.isNotEmpty)
                      Text(
                        step.duration,
                        style: const TextStyle(
                          color: Color(0xFF6F7C90),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (step.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.description,
                    style: const TextStyle(
                      color: Color(0xFF8290A5),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _currencyLabel(String currency) =>
      currency.toUpperCase() == 'MYR' ? 'RM' : currency.toUpperCase();

  Widget _lineBadge(String code, Color color, {bool large = false}) {
    return Container(
      width: large ? 31 : 19,
      height: large ? 31 : 19,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(large ? 9 : 5),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: Colors.white,
          fontSize: large ? 8 : 7,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF8290A5),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }

  List<TravelHistoryEntry> _filteredHistory() {
    final query = _historySearch.trim().toLowerCase();
    final today = DateTime.now();
    return _history.where((entry) {
      final searchable =
          '${entry.origin} ${entry.destination} ${entry.lineName}'
              .toLowerCase();
      if (query.isNotEmpty && !searchable.contains(query)) return false;
      return switch (_historyFilter) {
        _HistoryFilter.all => true,
        _HistoryFilter.today => DateUtils.isSameDay(entry.createdAt, today),
        _HistoryFilter.lastSevenDays => entry.createdAt.isAfter(
          today.subtract(const Duration(days: 7)),
        ),
      };
    }).toList();
  }

  Future<void> _showHistoryFilter() async {
    final selected = await showModalBottomSheet<_HistoryFilter>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Filter trips',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final filter in _HistoryFilter.values)
              ListTile(
                leading: Icon(
                  filter == _historyFilter
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _blue,
                ),
                title: Text(_historyFilterLabel(filter)),
                onTap: () => Navigator.pop(context, filter),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _historyFilter = selected);
    }
  }

  String _historyFilterLabel([_HistoryFilter? value]) =>
      switch (value ?? _historyFilter) {
        _HistoryFilter.all => 'Filter',
        _HistoryFilter.today => 'Today',
        _HistoryFilter.lastSevenDays => '7 days',
      };

  String _historySection(DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) return 'TODAY';
    if (DateUtils.isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'YESTERDAY';
    }
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  (String, Color) _lineDetails(String lineName) {
    final upper = lineName.toUpperCase();
    if (upper.contains('KELANA') || upper.contains('KJ')) {
      return ('KJ', const Color(0xFFED4956));
    }
    if (upper.contains('PUTRAJAYA') || upper.contains('PY')) {
      return ('PY', const Color(0xFF17A295));
    }
    if (upper.contains('KAJANG') || upper.contains('KG')) {
      return ('KG', const Color(0xFF3C9B5F));
    }
    if (upper.contains('MONORAIL') || upper.contains('MR')) {
      return ('MR', const Color(0xFFE08A13));
    }
    if (upper.contains('AMPANG') || upper.contains('AG')) {
      return ('AG', const Color(0xFFE77928));
    }
    return ('PT', _blue);
  }

  String _timeLabel(TravelHistoryEntry entry) {
    final raw = entry.departureTime.trim();
    if (raw.isEmpty) return _clockTime(entry.createdAt);
    return _storedTimeLabel(raw);
  }

  String _storedTimeLabel(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return _clockTime(parsed.toLocal());
    final parts = raw.split(':');
    if (parts.length >= 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        return _clockTime(DateTime(2000, 1, 1, hour, minute));
      }
    }
    return raw;
  }

  String _clockTime(DateTime date) {
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '$hour:${date.minute.toString().padLeft(2, '0')} $period';
  }

  String _friendlyRecentDate(DateTime date) {
    if (DateUtils.isSameDay(date, DateTime.now())) {
      return 'Today, ${_clockTime(date)}';
    }
    return '${_historySection(date)}, ${_clockTime(date)}';
  }

  String _memberSinceLabel() {
    final date = _memberSince;
    if (date == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _initials() {
    final words = _displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty || _displayName == 'Loading...') return 'NR';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _routineErrorMessage(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');

  int _activeReminderCount() =>
      _dailyCommutes.where((commute) => commute.reminderEnabled).length;

  UpcomingDailyCommuteReminder? get _nextReminder =>
      DailyCommuteService.nextReminder(_dailyCommutes, DateTime.now());

  DailyCommute? get _dashboardCommute =>
      _nextReminder?.commute ?? _dailyCommutes.firstOrNull;

  String _weekdayName(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];

  String _activeDaysLabel(Set<int> days) {
    const short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (days.length == 7) return 'Every day';
    const weekdays = {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    };
    if (days.length == 5 && days.containsAll(weekdays)) return 'Mon–Fri';
    final sorted = days.toList()..sort();
    return sorted.map((day) => short[day - 1]).join(', ');
  }

  String _formatMinutes(int minutes) {
    final normalized = (minutes % 1440 + 1440) % 1440;
    final hour24 = normalized ~/ 60;
    final minute = normalized % 60;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 3,
      decoration: BoxDecoration(
        color: const Color(0xFFD7DDE6),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({
    super.key,
    required this.repository,
    this.apiService,
  });

  final SavedPlacesRepository repository;
  final ApiService? apiService;

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  static const _navy = Color(0xFF173A7A);
  static const _blue = Color(0xFF2862E9);
  static const _background = Color(0xFFF3F6FA);
  late final ApiService _apiService;
  Map<SavedPlaceType, SavedPlace> _places = const {};
  List<StationModel> _stations = const [];
  SavedPlaceType? _savingType;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.repository.load(),
        _apiService.loadAllStations(),
      ]);
      final places = results[0] as List<SavedPlace>;
      if (!mounted) return;
      setState(() {
        _places = {for (final place in places) place.type: place};
        _stations = results[1] as List<StationModel>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _setPlace(SavedPlaceType type) async {
    var query = '';
    final station = await showModalBottomSheet<StationModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = _stations.where((station) {
            final needle = query.trim().toLowerCase();
            return needle.isEmpty ||
                station.name.toLowerCase().contains(needle) ||
                station.lines.join(' ').toLowerCase().contains(needle);
          }).toList();
          return FractionallySizedBox(
            heightFactor: .82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set ${type.label}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('saved-place-search'),
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search stations or stops',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF3F6FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) => setSheetState(() => query = value),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching station'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final station = filtered[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFEAF2FF),
                                  child: Icon(
                                    Icons.place_outlined,
                                    color: _blue,
                                  ),
                                ),
                                title: Text(
                                  station.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: station.lines.isEmpty
                                    ? null
                                    : Text(station.lines.join(' • ')),
                                onTap: () =>
                                    Navigator.pop(sheetContext, station),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (station == null || !mounted) return;
    setState(() => _savingType = type);
    try {
      final saved = await widget.repository.upsert(
        SavedPlace(type: type, station: station),
      );
      if (mounted) {
        setState(() => _places = {..._places, type: saved});
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingType = null);
    }
  }

  Future<void> _removePlace(SavedPlaceType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${type.label}?'),
        content: const Text('You can add this saved place again at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingType = type);
    try {
      await widget.repository.delete(type);
      if (mounted) {
        final updated = Map<SavedPlaceType, SavedPlace>.from(_places)
          ..remove(type);
        setState(() => _places = updated);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _savingType = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'Saved Places',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        foregroundColor: Colors.white,
        backgroundColor: _navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'SAVED PLACES',
                    style: TextStyle(
                      color: Color(0xFF8290A5),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final type in SavedPlaceType.values) ...[
                    _placeCard(type),
                    const SizedBox(height: 10),
                  ],
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
    );
  }

  Widget _placeCard(SavedPlaceType type) {
    final place = _places[type];
    final saving = _savingType == type;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFEAF2FF),
              child: Icon(_placeIcon(type), color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    place?.station.name ?? 'Not set',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            if (saving)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              TextButton(
                key: Key('set-saved-place-${type.databaseValue}'),
                onPressed: () => _setPlace(type),
                child: Text(place == null ? 'Add' : 'Edit'),
              ),
              if (place != null)
                IconButton(
                  tooltip: 'Remove ${type.label}',
                  onPressed: () => _removePlace(type),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF4E5B),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _placeIcon(SavedPlaceType type) => switch (type) {
    SavedPlaceType.home => Icons.home_outlined,
    SavedPlaceType.university => Icons.school_outlined,
    SavedPlaceType.work => Icons.work_outline,
  };

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_message(error)), backgroundColor: Colors.red),
    );
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}

// -----------------------------------------------------------------------------
// Daily Commute settings and overview
// -----------------------------------------------------------------------------

class DailyCommuteSettingsScreen extends StatefulWidget {
  const DailyCommuteSettingsScreen({
    super.key,
    this.service,
    this.savedRoutesRepository,
    this.initialRoute,
    this.initialActiveDays,
    this.initialCommute,
    this.addFavouriteJourney,
    this.chooseJourneyRoute,
  });

  final DailyCommuteService? service;
  final SavedRoutesRepository? savedRoutesRepository;
  final SavedRoute? initialRoute;
  final Set<int>? initialActiveDays;
  final DailyCommute? initialCommute;
  final Future<void> Function(BuildContext context)? addFavouriteJourney;
  final Future<SavedRoute?> Function(BuildContext context)? chooseJourneyRoute;

  @override
  State<DailyCommuteSettingsScreen> createState() =>
      _DailyCommuteSettingsScreenState();
}

class _DailyCommuteSettingsScreenState
    extends State<DailyCommuteSettingsScreen> {
  static const _navy = Color(0xFF173A7A);
  static const _blue = Color(0xFF2862E9);
  static const _background = Color(0xFFF3F6FA);
  static const _border = Color(0xFFE2E8F0);
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  late final DailyCommuteService _service;
  late final SavedRoutesRepository _routesRepository;
  bool _loading = true;
  bool _saving = false;
  List<SavedRoute> _routes = const [];
  SavedRoute? _selectedRoute;
  DailyCommute? _commute;
  TimeOfDay _departureTime = const TimeOfDay(hour: 9, minute: 0);
  Set<int> _activeDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  bool _reminderEnabled = true;
  int _reminderMinutes = 10;
  String? _error;
  int _routePickerRevision = 0;
  SavedRoute? _plannedRoute;
  RouteServiceAvailability? _serviceAvailability;
  bool _validatingService = false;
  String? _serviceValidationError;
  int _serviceValidationRevision = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DailyCommuteService();
    _routesRepository =
        widget.savedRoutesRepository ?? SupabaseSavedRoutesRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final routes = await _routesRepository.load();
      final commute = widget.initialCommute;
      SavedRoute? selected;
      if (commute?.savedRouteId != null) {
        for (final route in routes) {
          if (route.id == commute!.savedRouteId) {
            selected = route;
            break;
          }
        }
      }
      final suggestedRoute = widget.initialRoute;
      if (suggestedRoute?.id != null) {
        selected = routes
            .where((route) => route.id == suggestedRoute!.id)
            .firstOrNull;
      }
      if (!mounted) return;
      setState(() {
        _routes = routes.where((route) => route.id != null).toList();
        _commute = commute;
        _selectedRoute = selected;
        if (commute != null) {
          _departureTime = TimeOfDay(
            hour: commute.departureTimeMinutes ~/ 60,
            minute: commute.departureTimeMinutes % 60,
          );
          _activeDays = Set<int>.from(commute.activeDays);
          _reminderEnabled = commute.reminderEnabled;
          _reminderMinutes = commute.reminderMinutesBefore;
        }
        if (suggestedRoute != null) {
          _activeDays = widget.initialActiveDays?.isNotEmpty == true
              ? Set<int>.from(widget.initialActiveDays!)
              : _activeDays;
        }
        _loading = false;
      });
      await _validateServiceAvailability();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load Daily Commute settings. ${_message(error)}';
      });
    }
  }

  Future<RouteServiceAvailability?> _validateServiceAvailability() async {
    final route = _selectedRoute ?? _plannedRoute;
    final revision = ++_serviceValidationRevision;
    if (route == null || _activeDays.isEmpty) {
      if (mounted) {
        setState(() {
          _serviceAvailability = null;
          _serviceValidationError = null;
          _validatingService = false;
        });
      }
      return null;
    }
    setState(() {
      _validatingService = true;
      _serviceValidationError = null;
    });
    try {
      final result = await _service.validateRouteAvailability(
        route: route,
        departureTimeMinutes: _departureTime.hour * 60 + _departureTime.minute,
        activeDays: Set<int>.from(_activeDays),
      );
      if (!mounted || revision != _serviceValidationRevision) return result;
      setState(() {
        _serviceAvailability = result;
        _validatingService = false;
      });
      return result;
    } catch (error) {
      if (!mounted || revision != _serviceValidationRevision) return null;
      setState(() {
        _serviceAvailability = null;
        _validatingService = false;
        _serviceValidationError =
            'Unable to validate this route against the GTFS timetable. '
            '${_message(error)}';
      });
      return null;
    }
  }

  Future<void> _chooseTime() async {
    var hour12 = _departureTime.hourOfPeriod == 0
        ? 12
        : _departureTime.hourOfPeriod;
    var minute = _departureTime.minute;
    var isPm = _departureTime.period == DayPeriod.pm;
    final hourController = FixedExtentScrollController(initialItem: hour12 - 1);
    final minuteController = FixedExtentScrollController(initialItem: minute);
    final periodController = FixedExtentScrollController(
      initialItem: isPm ? 1 : 0,
    );
    final selected = await showModalBottomSheet<TimeOfDay>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: 330,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Departure Time',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          final hour24 = isPm
                              ? (hour12 == 12 ? 12 : hour12 + 12)
                              : (hour12 == 12 ? 0 : hour12);
                          Navigator.pop(
                            sheetContext,
                            TimeOfDay(hour: hour24, minute: minute),
                          );
                        },
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(60, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          key: const Key('departure-hour-wheel'),
                          scrollController: hourController,
                          itemExtent: 44,
                          onSelectedItemChanged: (index) =>
                              setSheetState(() => hour12 = index + 1),
                          children: List.generate(
                            12,
                            (index) => Center(child: Text('${index + 1}')),
                          ),
                        ),
                      ),
                      const Text(
                        ':',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          key: const Key('departure-minute-wheel'),
                          scrollController: minuteController,
                          itemExtent: 44,
                          onSelectedItemChanged: (index) =>
                              setSheetState(() => minute = index),
                          children: List.generate(
                            60,
                            (index) => Center(
                              child: Text(index.toString().padLeft(2, '0')),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          key: const Key('departure-period-wheel'),
                          scrollController: periodController,
                          itemExtent: 44,
                          onSelectedItemChanged: (index) =>
                              setSheetState(() => isPm = index == 1),
                          children: const [
                            Center(child: Text('AM')),
                            Center(child: Text('PM')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    hourController.dispose();
    minuteController.dispose();
    periodController.dispose();
    if (selected != null && mounted) {
      setState(() => _departureTime = selected);
      await _validateServiceAvailability();
    }
  }

  Future<void> _openFavouriteRoutes() async {
    final selected = await Navigator.push<SavedRoute>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FavouriteRoutesScreen(repository: widget.savedRoutesRepository),
      ),
    );
    if (!mounted) return;
    await _load();
    if (selected?.id != null && mounted) {
      setState(() {
        _selectedRoute = _routes
            .where((route) => route.id == selected!.id)
            .firstOrNull;
        _plannedRoute = null;
      });
      await _validateServiceAvailability();
    }
  }

  Future<void> _chooseJourneyRoute() async {
    final callback = widget.chooseJourneyRoute;
    final selected = callback != null
        ? await callback(context)
        : await Navigator.push<SavedRoute>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const JourneyPlanningScreen(selectForDailyCommute: true),
            ),
          );
    if (selected == null || !mounted) return;
    try {
      final routes = (await _routesRepository.load())
          .where((route) => route.id != null)
          .toList();
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _plannedRoute = selected;
        _selectedRoute = null;
        _routePickerRevision++;
        _error = null;
      });
      await _validateServiceAvailability();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _plannedRoute = selected;
        _selectedRoute = null;
        _routePickerRevision++;
        _error = 'Route selected, but Favourite Routes could not be refreshed.';
      });
      await _validateServiceAvailability();
    }
  }

  Future<void> _addNewFavouriteJourney() async {
    final previousIds = _routes
        .map((route) => route.id)
        .whereType<String>()
        .toSet();
    final callback = widget.addFavouriteJourney;
    if (callback != null) {
      await callback(context);
    } else {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const JourneyPlanningScreen()),
      );
    }
    if (!mounted) return;

    try {
      final routes = (await _routesRepository.load())
          .where((route) => route.id != null)
          .toList();
      final added = routes
          .where((route) => !previousIds.contains(route.id))
          .firstOrNull;
      final currentId = _selectedRoute?.id;
      setState(() {
        _routes = routes;
        _selectedRoute =
            added ?? routes.where((route) => route.id == currentId).firstOrNull;
        if (_selectedRoute != null) _plannedRoute = null;
        _routePickerRevision++;
        _error = null;
      });
      await _validateServiceAvailability();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to refresh Favourite Routes.');
      }
    }
  }

  Future<void> _selectRoute(String? id) async {
    if (id == '__add_favourite_journey__') {
      await _addNewFavouriteJourney();
      return;
    }
    setState(() {
      _selectedRoute = _routes.where((route) => route.id == id).firstOrNull;
      if (_selectedRoute != null) _plannedRoute = null;
    });
    await _validateServiceAvailability();
  }

  Future<void> _save() async {
    if (_saving) return;
    final route = _selectedRoute ?? _plannedRoute;
    final existing = _commute;
    if (route == null && existing == null) {
      setState(
        () => _error =
            'Choose a route in Journey Planning or select a Favourite Route.',
      );
      return;
    }
    if (_activeDays.isEmpty) {
      setState(() => _error = 'Select at least one active day.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      RouteServiceAvailability? availability;
      var saveWithWarning = existing?.hasServiceWarning ?? false;
      if (route != null) {
        availability = await _validateServiceAvailability();
        if (availability == null) {
          throw StateError(
            _serviceValidationError ??
                'Unable to validate this route against the GTFS timetable.',
          );
        }
        saveWithWarning = !availability.isAvailable;
        if (saveWithWarning) {
          if (!mounted) return;
          setState(() => _saving = false);
          final saveAnyway = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('No scheduled service'),
              content: Text(_unavailableMessage(availability!)),
              actions: [
                TextButton(
                  key: const Key('choose-another-commute-time'),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Choose Another Time'),
                ),
                FilledButton(
                  key: const Key('save-commute-anyway'),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save Anyway'),
                ),
              ],
            ),
          );
          if (saveAnyway != true) {
            return;
          }
          if (!mounted) return;
          setState(() => _saving = true);
        }
      }
      final commute = await _service.save(
        reminderId: _commute?.id,
        route: route,
        origin: route?.origin.name ?? existing?.origin,
        destination: route?.destination.name ?? existing?.destination,
        estimatedDurationMinutes: route == null
            ? existing?.estimatedDurationMinutes
            : null,
        validatedDurationMinutes:
            availability?.estimatedDurationMinutes ??
            availability?.fallbackDurationMinutes,
        hasServiceWarning: saveWithWarning,
        departureTimeMinutes: _departureTime.hour * 60 + _departureTime.minute,
        activeDays: _activeDays,
        reminderEnabled: _reminderEnabled,
        reminderMinutesBefore: _reminderMinutes,
      );
      if (!mounted) return;
      setState(() {
        _commute = commute;
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Daily Commute saved.')));
      Navigator.pop(context, commute);
    } on NotificationPermissionException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Notification or Alarms & reminders permission was denied. '
            'Allow both permissions or turn the reminder off.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _message(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'Daily Commute',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        foregroundColor: Colors.white,
        backgroundColor: _navy,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _section(title: 'Route', child: _routeChooser()),
                  const SizedBox(height: 14),
                  _section(
                    title: 'Departure Time',
                    child: InkWell(
                      key: const Key('commute-departure-time'),
                      onTap: _chooseTime,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          Icons.schedule_outlined,
                          'Departure Time',
                        ),
                        child: Text(
                          _formatMinutes(
                            _departureTime.hour * 60 + _departureTime.minute,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section(
                    title: 'Active Days',
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final weekday = index + 1;
                        final selected = _activeDays.contains(weekday);
                        return InkWell(
                          key: Key('commute-day-$weekday'),
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _activeDays.remove(weekday);
                              } else {
                                _activeDays.add(weekday);
                              }
                            });
                            _validateServiceAvailability();
                          },
                          customBorder: const CircleBorder(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? _blue : const Color(0xFFF2F5F9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? _blue : _border,
                              ),
                            ),
                            child: Text(
                              _dayLabels[index],
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF64748B),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _section(
                    title: 'Reminder',
                    child: Column(
                      children: [
                        SwitchListTile(
                          key: const Key('commute-reminder'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Reminder Enabled',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Receive a notification before departure',
                          ),
                          value: _reminderEnabled,
                          activeThumbColor: _blue,
                          onChanged: (value) =>
                              setState(() => _reminderEnabled = value),
                        ),
                        const Divider(),
                        DropdownButtonFormField<int>(
                          key: const Key('commute-notify-before'),
                          initialValue: _reminderMinutes,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            Icons.notifications_none_rounded,
                            'Notify Me',
                          ),
                          items: const [5, 10, 15, 30]
                              .map(
                                (minutes) => DropdownMenuItem(
                                  value: minutes,
                                  child: Text(
                                    '$minutes minutes before departure',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _reminderEnabled
                              ? (value) => setState(
                                  () => _reminderMinutes = value ?? 10,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _calculationCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _notice(_error!, error: true),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      key: const Key('save-daily-commute'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _commute == null ? 'Save Commute' : 'Update Commute',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF8290A5),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _routeChooser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_plannedRoute != null) ...[
          _selectedRouteSummary(
            _plannedRoute!.origin.name,
            _plannedRoute!.destination.name,
            label: 'Selected in Journey Planning',
            routeName: _plannedRoute!.name,
          ),
          const SizedBox(height: 10),
        ] else if (_selectedRoute == null && _commute != null) ...[
          _selectedRouteSummary(
            _commute!.origin,
            _commute!.destination,
            label: 'Current Daily Commute route',
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          key: const Key('choose-commute-route'),
          onPressed: _saving ? null : _chooseJourneyRoute,
          icon: const Icon(Icons.route_outlined),
          label: Text(
            _plannedRoute == null && _commute == null
                ? 'Choose in Journey Planning'
                : 'Change in Journey Planning',
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'OR USE A FAVOURITE ROUTE',
                  style: TextStyle(
                    color: Color(0xFF8290A5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
        ),
        if (_routes.isEmpty) ...[
          const Text(
            'No Favourite Routes yet. You can choose a route above without saving it as a favourite.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('add-favourite-journey'),
            onPressed: _saving ? null : _addNewFavouriteJourney,
            icon: const Icon(Icons.favorite_border),
            label: const Text('Add New Favourite Journey'),
          ),
        ] else ...[
          KeyedSubtree(
            key: const Key('commute-route'),
            child: DropdownButtonFormField<String>(
              key: ValueKey(_routePickerRevision),
              initialValue: _selectedRoute?.id,
              isExpanded: true,
              decoration: _inputDecoration(
                Icons.favorite_border,
                'Favourite Route (optional)',
              ),
              items: [
                ..._routes.map(
                  (route) => DropdownMenuItem(
                    value: route.id,
                    child: _favouriteRouteOption(route),
                  ),
                ),
                const DropdownMenuItem(
                  value: '__add_favourite_journey__',
                  child: Row(
                    children: [
                      Icon(Icons.add_road_rounded, color: _blue),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Add New Favourite Journey',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _blue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: _saving ? null : _selectRoute,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _openFavouriteRoutes,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Manage Favourite Routes'),
          ),
        ],
      ],
    );
  }

  Widget _selectedRouteSummary(
    String origin,
    String destination, {
    required String label,
    String? routeName,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
          const SizedBox(height: 4),
          if (routeName != null) ...[
            Text(
              routeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
          ],
          Text(
            '$origin → $destination',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: routeName == null
                  ? const Color(0xFF172033)
                  : const Color(0xFF64748B),
              fontSize: routeName == null ? 14 : 11,
              fontWeight: routeName == null ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _favouriteRouteOption(SavedRoute route) {
    return Row(
      children: [
        Flexible(
          flex: 2,
          child: Text(
            route.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Text(
          '  ·  ',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
        Expanded(
          flex: 3,
          child: Text(
            '${route.origin.name} → ${route.destination.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _calculationCard() {
    final saved = _commute;
    final departureMinutes = _departureTime.hour * 60 + _departureTime.minute;
    final availability = _serviceAvailability;
    final unavailable =
        availability?.isAvailable == false ||
        (availability == null && saved?.hasServiceWarning == true);
    final duration =
        availability?.estimatedDurationMinutes ??
        (!unavailable ? saved?.estimatedDurationMinutes : null);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _calculationRow('Departure time', _formatMinutes(departureMinutes)),
          const SizedBox(height: 10),
          if (_validatingService) ...[
            const Row(
              key: Key('commute-service-validating'),
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 9),
                Expanded(child: Text('Checking the GTFS timetable…')),
              ],
            ),
          ] else if (_serviceValidationError != null) ...[
            _serviceStatus(
              icon: Icons.error_outline,
              color: Colors.red.shade700,
              message: _serviceValidationError!,
            ),
          ] else if (availability?.isAvailable == true) ...[
            _serviceStatus(
              key: const Key('commute-service-available'),
              icon: Icons.check_circle,
              color: const Color(0xFF15803D),
              message: 'Service available',
            ),
          ] else if (unavailable && availability != null) ...[
            _serviceStatus(
              key: const Key('commute-service-unavailable'),
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFB45309),
              message: _unavailableMessage(availability),
            ),
          ] else if (unavailable) ...[
            _serviceStatus(
              key: const Key('commute-service-unavailable'),
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFB45309),
              message:
                  'No scheduled service around ${_formatMinutes(departureMinutes)}.',
            ),
          ],
          if (duration != null && !_validatingService && !unavailable) ...[
            const SizedBox(height: 10),
            _calculationRow('Estimated travel time', '$duration min'),
            const SizedBox(height: 10),
            _calculationRow(
              'Estimated arrival',
              _formatMinutes(departureMinutes + duration),
            ),
          ],
          if (_reminderEnabled) ...[
            const SizedBox(height: 10),
            _calculationRow(
              'Notification time',
              _formatMinutes(
                _departureTime.hour * 60 +
                    _departureTime.minute -
                    _reminderMinutes,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _serviceStatus({
    Key? key,
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: color, fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }

  String _unavailableMessage(RouteServiceAvailability availability) {
    final time = _formatMinutes(
      _departureTime.hour * 60 + _departureTime.minute,
    );
    final unavailableDays = availability.unavailableWeekdays.toList()..sort();
    final daySuffix = unavailableDays.length == _activeDays.length
        ? ''
        : ' on ${unavailableDays.map(_fullDayLabel).join(', ')}';
    var message = 'No scheduled service around $time$daySuffix.';
    final next = availability.nextDeparture;
    if (next != null) {
      message +=
          '\nNext available service: '
          '${_formatMinutes(next.hour * 60 + next.minute)} '
          '(${_fullDayLabel(next.weekday)})';
    }
    return message;
  }

  static String _fullDayLabel(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  Widget _calculationRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF48627F), fontSize: 12),
          ),
        ),
        Text(
          value,
          style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _notice(String message, {bool error = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (error ? Colors.red : Colors.orange).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? Colors.red.shade700 : Colors.orange.shade900,
          fontSize: 12,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String label) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    final normalized = (minutes % 1440 + 1440) % 1440;
    final hour24 = normalized ~/ 60;
    final minute = normalized % 60;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  static String _message(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }
}

class DailyCommuteOverviewSheet extends StatefulWidget {
  const DailyCommuteOverviewSheet({
    super.key,
    this.service,
    this.savedRoutesRepository,
    this.onOpenJourneyPlanning,
  });

  final DailyCommuteService? service;
  final SavedRoutesRepository? savedRoutesRepository;
  final VoidCallback? onOpenJourneyPlanning;

  @override
  State<DailyCommuteOverviewSheet> createState() =>
      _DailyCommuteOverviewSheetState();
}

class _DailyCommuteOverviewSheetState extends State<DailyCommuteOverviewSheet> {
  static const _blue = Color(0xFF2862E9);
  late final DailyCommuteService _service;
  List<DailyCommute> _commutes = const [];
  bool _loading = true;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DailyCommuteService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final commutes = await _service.loadAll();
      if (mounted) setState(() => _commutes = commutes);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([DailyCommute? commute]) async {
    await Navigator.push<DailyCommute>(
      context,
      MaterialPageRoute(
        builder: (_) => DailyCommuteSettingsScreen(
          service: _service,
          savedRoutesRepository: widget.savedRoutesRepository,
          initialCommute: commute,
          addFavouriteJourney: widget.onOpenJourneyPlanning == null
              ? null
              : (settingsContext) async {
                  Navigator.pop(settingsContext);
                  if (!mounted) return;
                  Navigator.pop(context);
                  widget.onOpenJourneyPlanning!();
                },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _toggle(DailyCommute commute, bool enabled) async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final updated = await _service.setReminderEnabled(commute, enabled);
      if (mounted) {
        setState(() {
          _commutes = [
            for (final item in _commutes)
              if (item.id == updated.id) updated else item,
          ];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _delete(DailyCommute commute) async {
    if (_updating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Daily Commute?'),
        content: const Text(
          'This removes the routine and cancels all scheduled commute notifications.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _updating = true);
    try {
      await _service.delete(commute);
      if (mounted) {
        setState(
          () => _commutes = _commutes
              .where((item) => item.id != commute.id)
              .toList(),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD8DEE8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Smart Reminders',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading || _updating ? null : () => _edit(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(Icons.add, size: 15),
                  label: Text(
                    'Add',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F4F8),
                    foregroundColor: const Color(0xFF94A0B2),
                    minimumSize: const Size(34, 34),
                    maximumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EDF4)),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_commutes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF2DE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFFE88B17),
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No Daily Commute yet',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose when you will leave and receive a reminder before departure.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7B879A), fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Create Daily Commute'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        for (final commute in _commutes) ...[
          _commuteCard(commute),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          const SizedBox(height: 2),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _commuteCard(DailyCommute commute) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  color: _blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Commute',
                      style: TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${commute.origin} → ${commute.destination}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1E293B),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_daysLabel(commute.activeDays)} · Departure ${_formatMinutes(commute.departureTimeMinutes)}',
                      style: const TextStyle(
                        color: Color(0xFF8793A6),
                        fontSize: 10,
                      ),
                    ),
                    if (commute.hasServiceWarning) ...[
                      const SizedBox(height: 5),
                      const Text(
                        'No scheduled service around this departure time',
                        key: Key('saved-commute-service-warning'),
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(
                value: commute.reminderEnabled,
                activeThumbColor: _blue,
                onChanged: _updating
                    ? null
                    : (enabled) => _toggle(commute, enabled),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Divider(height: 1, color: Color(0xFFE1E7EF)),
          const SizedBox(height: 9),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _updating ? null : () => _edit(commute),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: Color(0xFFD9E1EC)),
                ),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Edit', style: TextStyle(fontSize: 10)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _updating ? null : () => _delete(commute),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4E5B),
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: Color(0xFFFFCCD1)),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 14),
                label: const Text('Delete', style: TextStyle(fontSize: 10)),
              ),
              const Spacer(),
              if (_updating)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _daysLabel(Set<int> days) {
    if (days.length == 7) return 'Every day';
    const weekdays = {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    };
    if (days.length == 5 && days.containsAll(weekdays)) return 'Mon – Fri';
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = days.toList()..sort();
    return sorted.map((day) => labels[day - 1]).join(', ');
  }

  static String _formatMinutes(int minutes) {
    final normalized = (minutes % 1440 + 1440) % 1440;
    final hour24 = normalized ~/ 60;
    final minute = normalized % 60;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
