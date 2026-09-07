import 'package:flutter/material.dart';
import 'package:nextroute_assignment/screens/notification_centre.dart';
import 'package:nextroute_assignment/screens/service_analytics.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:nextroute_assignment/services/module5_route_preferences.dart';
import 'package:nextroute_assignment/services/module5_user_route_context.dart';

class AnalyticsCentreScreen extends StatefulWidget {
  const AnalyticsCentreScreen({this.showBackButton = false, super.key});

  final bool showBackButton;

  @override
  State<AnalyticsCentreScreen> createState() => _AnalyticsCentreScreenState();
}

class _AnalyticsCentreScreenState extends State<AnalyticsCentreScreen> {
  late final NotificationRepository _repository;
  late final Module5RoutePreferences _routePreferences;
  late final Module5UserRouteContext _routeContext;
  int _selectedSection = 0;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _repository = NotificationRepository(
      SharedPreferencesNotificationLocalStorage(),
      pushService: LocalPushNotificationService(),
    );
    _routePreferences = Module5RoutePreferences();
    _routeContext = Module5UserRouteContext.shared;
    _routePreferences.load();
    // Re-read Favourite Routes and Daily Commutes whenever Module 5 opens so
    // a route saved moments ago is immediately available for prioritisation.
    _routeContext.load(forcePersonalRoutes: true);
    _refreshUnreadCount();
  }

  @override
  void dispose() {
    _routePreferences.dispose();
    super.dispose();
  }

  Future<void> _refreshUnreadCount() async {
    try {
      final notifications = await _repository.loadNotifications();
      if (mounted) {
        setState(() {
          _unreadCount = _repository.unreadCount(notifications);
        });
      }
    } on Object {
      // Child screens provide detailed storage errors when opened.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      body: SafeArea(
        child: Column(
          children: [
            _CentreHeader(
              selectedSection: _selectedSection,
              unreadCount: _unreadCount,
              showBackButton: widget.showBackButton,
              onBack: widget.showBackButton
                  ? () => Navigator.of(context).pop()
                  : null,
              onSectionChanged: (index) {
                setState(() => _selectedSection = index);
                if (index == 1) {
                  _refreshUnreadCount();
                }
              },
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedSection,
                children: [
                  ServiceAnalyticsScreen(
                    embedded: true,
                    routePreferences: _routePreferences,
                    routeContext: _routeContext,
                  ),
                  NotificationCentreScreen(
                    embedded: true,
                    repository: _repository,
                    onNotificationsChanged: _refreshUnreadCount,
                    routePreferences: _routePreferences,
                    routeContext: _routeContext,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CentreHeader extends StatelessWidget {
  const _CentreHeader({
    required this.selectedSection,
    required this.unreadCount,
    required this.showBackButton,
    this.onBack,
    required this.onSectionChanged,
  });

  final int selectedSection;
  final int unreadCount;
  final bool showBackButton;
  final VoidCallback? onBack;
  final ValueChanged<int> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF2457D6),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBackButton) ...[
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Back to active journey',
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 4),
              ],
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ANALYTICS & NOTIFICATION',
                      style: TextStyle(
                        color: Color(0xFFBDD0FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Analytics & Notification Centre',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (unreadCount > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 28),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF2D3D),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.17),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _SectionButton(
                  icon: Icons.analytics_outlined,
                  label: 'Analytics',
                  selected: selectedSection == 0,
                  onTap: () => onSectionChanged(0),
                ),
                _SectionButton(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  selected: selectedSection == 1,
                  onTap: () => onSectionChanged(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? const Color(0xFF2457D6) : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? const Color(0xFF2457D6) : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
