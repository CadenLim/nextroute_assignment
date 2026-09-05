import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
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
    this.dailyCommuteService,
    this.onOpenJourneyPlanning,
  });

  final PersonalTravelService? service;
  final ImagePicker? imagePicker;
  final SavedRoutesRepository? savedRoutesRepository;
  final DailyCommuteService? dailyCommuteService;
  final VoidCallback? onOpenJourneyPlanning;

  @override
  State<PersonalTravelScreen> createState() => _PersonalTravelScreenState();
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
  _ProfilePage _page = _ProfilePage.dashboard;
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  bool _isUploadingAvatar = false;
  bool _isLoadingHistory = true;
  String _displayName = 'Loading...';
  String _email = '';
  String _phoneNumber = '';
  String _historySearch = '';
  int? _savedRoutesCount;
  String? _avatarUrl;
  DateTime? _memberSince;
  List<TravelHistoryEntry> _history = const [];
  DailyCommute? _dailyCommute;

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
    _loadProfile();
    _loadSavedRoutes();
    _loadHistory();
    _loadDailyCommute();
  }

  Future<void> _loadDailyCommute() async {
    final service = _dailyCommuteService;
    if (service == null) return;
    try {
      final commute = await service.load();
      if (mounted) setState(() => _dailyCommute = commute);
    } catch (_) {
      if (mounted) setState(() => _dailyCommute = null);
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
        ),
      ),
    );
    if (!mounted) return;
    await _loadDailyCommute();
    await _loadSavedRoutes();
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
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 20,
                      ),
                      const Text(
                        'Home',
                        style: TextStyle(color: Colors.white, fontSize: 12),
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
                  const SizedBox(height: 18),
                  const Text(
                    'Dashboard',
                    style: TextStyle(color: Color(0xFFD9E5FF), fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_greeting()}, ${firstName == 'Loading...' ? 'there' : firstName} 👋',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            sliver: SliverList.list(
              children: [
                _sectionLabel("TODAY'S COMMUTE"),
                const SizedBox(height: 7),
                _commuteCard(),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _reminderCard()),
                    const SizedBox(width: 10),
                    Expanded(child: _recentTripCard(recent)),
                  ],
                ),
                const SizedBox(height: 17),
                _sectionLabel('QUICK ACCESS'),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.15,
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
    final commute = _dailyCommute;
    return _surfaceCard(
      onTap: _openDailyCommuteSettings,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: [
          _softIcon(
            Icons.directions_transit_rounded,
            _blue,
            const Color(0xFFEAF2FF),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commute == null
                      ? 'Set up your Daily Commute'
                      : '${commute.origin} → ${commute.destination}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  commute == null
                      ? 'Choose a favourite route and arrival time'
                      : '${commute.estimatedDurationMinutes} min · ${_activeDaysLabel(commute.activeDays)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A94A6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                commute == null
                    ? 'Set up'
                    : _formatMinutes(commute.recommendedDepartureMinutes),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                commute == null ? 'commute' : 'leave by',
                style: const TextStyle(color: Color(0xFF9BA6B7), fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reminderCard() {
    final commute = _dailyCommute;
    return _surfaceCard(
      onTap: _openDailyCommuteSettings,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('NEXT REMINDER'),
          const SizedBox(height: 10),
          _softIcon(
            Icons.notifications_none_rounded,
            const Color(0xFFE88B17),
            const Color(0xFFFFF2DE),
          ),
          const SizedBox(height: 9),
          Text(
            commute == null
                ? 'Set up commute'
                : commute.reminderEnabled
                ? '${commute.reminderMinutesBefore} min before'
                : 'Reminder OFF',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            commute == null
                ? 'Tap to configure'
                : '${_activeDaysLabel(commute.activeDays)}\nArrive ${_formatMinutes(commute.arriveByMinutes)}',
            style: const TextStyle(
              color: Color(0xFF8290A5),
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentTripCard(TravelHistoryEntry? trip) {
    return _surfaceCard(
      onTap: () => setState(() => _page = _ProfilePage.history),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('RECENT TRIP'),
          const SizedBox(height: 10),
          _softIcon(
            Icons.history_rounded,
            const Color(0xFF8056E8),
            const Color(0xFFF0EAFF),
          ),
          const SizedBox(height: 9),
          Text(
            trip == null
                ? 'No recent trips'
                : '${trip.origin} → ${trip.destination}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            trip == null
                ? 'Plan a journey to begin'
                : 'RM ${trip.fare.toStringAsFixed(2)}\n${_friendlyRecentDate(trip.createdAt)}',
            maxLines: 2,
            style: const TextStyle(
              color: Color(0xFF8290A5),
              fontSize: 10,
              height: 1.35,
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
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
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

  Widget _softIcon(IconData icon, Color color, Color background) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 19),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(13),
      ),
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
                  style: const TextStyle(color: Color(0xFF8290A5), fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'RM ${entry.fare.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

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
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.45,
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

  int _activeReminderCount() => _dailyCommute == null ? 0 : 1;

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

// -----------------------------------------------------------------------------
// Daily Commute settings and overview
// -----------------------------------------------------------------------------

class DailyCommuteSettingsScreen extends StatefulWidget {
  const DailyCommuteSettingsScreen({
    super.key,
    this.service,
    this.savedRoutesRepository,
  });

  final DailyCommuteService? service;
  final SavedRoutesRepository? savedRoutesRepository;

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
  TimeOfDay _arriveBy = const TimeOfDay(hour: 9, minute: 0);
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
      final results = await Future.wait<dynamic>([
        _routesRepository.load(),
        _service.load(),
      ]);
      final routes = results[0] as List<SavedRoute>;
      final commute = results[1] as DailyCommute?;
      SavedRoute? selected;
      if (commute?.savedRouteId != null) {
        for (final route in routes) {
          if (route.id == commute!.savedRouteId) {
            selected = route;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _routes = routes.where((route) => route.id != null).toList();
        _commute = commute;
        _selectedRoute = selected;
        if (commute != null) {
          _arriveBy = TimeOfDay(
            hour: commute.arriveByMinutes ~/ 60,
            minute: commute.arriveByMinutes % 60,
          );
          _activeDays = Set<int>.from(commute.activeDays);
          _reminderEnabled = commute.reminderEnabled;
          _reminderMinutes = commute.reminderMinutesBefore;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load Daily Commute settings. ${_message(error)}';
      });
    }
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _arriveBy,
      helpText: 'ARRIVE BY',
    );
    if (selected != null && mounted) setState(() => _arriveBy = selected);
  }

  Future<void> _openFavouriteRoutes() async {
    await Navigator.push<SavedRoute>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FavouriteRoutesScreen(repository: widget.savedRoutesRepository),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _save() async {
    if (_saving) return;
    final route = _selectedRoute;
    if (route == null) {
      setState(() => _error = 'Select one of your favourite routes.');
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
      final commute = await _service.save(
        route: route,
        arriveByMinutes: _arriveBy.hour * 60 + _arriveBy.minute,
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
                  _section(
                    title: 'Route',
                    child: _routes.isEmpty
                        ? _emptyRoutes()
                        : DropdownButtonFormField<String>(
                            key: const Key('commute-route'),
                            initialValue: _selectedRoute?.id,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              Icons.route_outlined,
                              'Favourite Route',
                            ),
                            items: _routes
                                .map(
                                  (route) => DropdownMenuItem(
                                    value: route.id,
                                    child: Text(
                                      '${route.origin.name} → ${route.destination.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) {
                              setState(() {
                                _selectedRoute = _routes
                                    .where((route) => route.id == id)
                                    .firstOrNull;
                                _commute = null;
                              });
                            },
                          ),
                  ),
                  if (_commute != null && _selectedRoute == null) ...[
                    const SizedBox(height: 10),
                    _notice(
                      'The favourite route used by this commute was deleted. '
                      'Select another route before updating it.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  _section(
                    title: 'Arrive By',
                    child: InkWell(
                      key: const Key('commute-arrive-by'),
                      onTap: _chooseTime,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          Icons.schedule_outlined,
                          'Arrive By',
                        ),
                        child: Text(
                          _formatMinutes(
                            _arriveBy.hour * 60 + _arriveBy.minute,
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
                          onTap: () => setState(() {
                            if (selected) {
                              _activeDays.remove(weekday);
                            } else {
                              _activeDays.add(weekday);
                            }
                          }),
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

  Widget _emptyRoutes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Save a favourite route before setting up your daily commute.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openFavouriteRoutes,
          icon: const Icon(Icons.favorite_border),
          label: const Text('Open Favourite Routes'),
        ),
      ],
    );
  }

  Widget _calculationCard() {
    final saved = _commute;
    final commute = saved?.copyWith(
      arriveByMinutes: _arriveBy.hour * 60 + _arriveBy.minute,
      activeDays: _activeDays,
      reminderEnabled: _reminderEnabled,
      reminderMinutesBefore: _reminderMinutes,
    );
    final routeChanged = commute == null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(15),
      ),
      child: routeChanged
          ? const Row(
              children: [
                Icon(Icons.calculate_outlined, color: _blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Travel time and departure time will be calculated when you save.',
                    style: TextStyle(color: Color(0xFF48627F), fontSize: 12),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _calculationRow(
                  'Estimated travel time',
                  '${commute.estimatedDurationMinutes} min',
                ),
                const SizedBox(height: 10),
                _calculationRow(
                  'Recommended departure',
                  _formatMinutes(commute.recommendedDepartureMinutes),
                ),
                if (commute.reminderEnabled) ...[
                  const SizedBox(height: 10),
                  _calculationRow(
                    'Notification time',
                    _formatMinutes(commute.notificationTimeMinutes),
                  ),
                ],
              ],
            ),
    );
  }

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
  });

  final DailyCommuteService? service;
  final SavedRoutesRepository? savedRoutesRepository;

  @override
  State<DailyCommuteOverviewSheet> createState() =>
      _DailyCommuteOverviewSheetState();
}

class _DailyCommuteOverviewSheetState extends State<DailyCommuteOverviewSheet> {
  static const _blue = Color(0xFF2862E9);
  late final DailyCommuteService _service;
  DailyCommute? _commute;
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
      final commute = await _service.load();
      if (mounted) setState(() => _commute = commute);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    await Navigator.push<DailyCommute>(
      context,
      MaterialPageRoute(
        builder: (_) => DailyCommuteSettingsScreen(
          service: _service,
          savedRoutesRepository: widget.savedRoutesRepository,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _toggle(bool enabled) async {
    final commute = _commute;
    if (commute == null || _updating) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final updated = await _service.setReminderEnabled(commute, enabled);
      if (mounted) setState(() => _commute = updated);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _delete() async {
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
      await _service.delete();
      if (mounted) setState(() => _commute = null);
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
                  onPressed: _loading || _updating ? null : _edit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    _commute == null ? Icons.add : Icons.edit_outlined,
                    size: 15,
                  ),
                  label: Text(
                    _commute == null ? 'Create' : 'Edit',
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
    if (_commute == null) {
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
                'Create one routine and NextRoute will calculate when you should leave.',
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
                onPressed: _edit,
                icon: const Icon(Icons.add),
                label: const Text('Create Daily Commute'),
              ),
            ],
          ),
        ),
      );
    }
    final commute = _commute!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Container(
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
                          '${_daysLabel(commute.activeDays)} · Leave ${_formatMinutes(commute.recommendedDepartureMinutes)}',
                          style: const TextStyle(
                            color: Color(0xFF8793A6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: commute.reminderEnabled,
                    activeThumbColor: _blue,
                    onChanged: _updating ? null : _toggle,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              const Divider(height: 1, color: Color(0xFFE1E7EF)),
              const SizedBox(height: 9),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _updating ? null : _edit,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: Color(0xFFD9E1EC)),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit', style: TextStyle(fontSize: 10)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _updating ? null : _delete,
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
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 11),
          ),
        ],
      ],
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
