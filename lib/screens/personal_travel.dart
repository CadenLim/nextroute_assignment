import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../localization/app_language.dart';
import 'edit_profile.dart';

class PersonalTravelScreen extends StatefulWidget {
  const PersonalTravelScreen({super.key});

  @override
  State<PersonalTravelScreen> createState() => _PersonalTravelScreenState();
}

class _PersonalTravelScreenState extends State<PersonalTravelScreen> {
  bool _morningReminder = true;
  bool _eveningReminder = false;
  String _displayName = 'Loading...';
  String _email = '';
  String _phoneNumber = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile({String? confirmedEmail}) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) return;

    // Auth already provides a stable, unique ID for every member. Set these
    // values before loading the optional profile row so they are always shown.
    _email = confirmedEmail ?? user.email ?? _email;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('display_name, phone_number')
          .eq('id', user.id)
          .single();

      if (!mounted) return;

      final name = (profile['display_name'] as String?)?.trim();

      setState(() {
        _displayName = name == null || name.isEmpty
            ? user.email ?? 'NextRoute User'
            : name;
        _phoneNumber = profile['phone_number'] as String? ?? '';
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Unable to load profile.'))),
      );
    }
  }

  Future<void> _openEditProfile() async {
    final confirmedEmail = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (context) => EditProfileScreen(
          displayName: _displayName,
          email: _email,
          phoneNumber: _phoneNumber,
        ),
      ),
    );

    if (mounted) {
      await _loadProfile(confirmedEmail: confirmedEmail);
    }
  }

  void _showRemindersDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                context.tr('Smart Reminders'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text(
                      context.tr('Morning Commute (7:30 AM)'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    value: _morningReminder,
                    activeThumbColor: const Color(0xFF2563EB),
                    onChanged: (value) {
                      setDialogState(() => _morningReminder = value);
                      setState(() => _morningReminder = value);
                    },
                  ),
                  SwitchListTile(
                    title: Text(
                      context.tr('Evening Return (6:00 PM)'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    value: _eveningReminder,
                    activeThumbColor: const Color(0xFF2563EB),
                    onChanged: (value) {
                      setDialogState(() => _eveningReminder = value);
                      setState(() => _eveningReminder = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    context.tr('Save & Close'),
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showLanguageDialog() async {
    final controller = context.languageController;
    final selectedLanguage = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        Widget languageOption(String code, String label) {
          return ListTile(
            leading: Icon(
              controller.languageCode == code
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: const Color(0xFF2563EB),
            ),
            title: Text(label),
            onTap: () => Navigator.pop(dialogContext, code),
          );
        }

        return AlertDialog(
          title: Text(context.tr('App Language')),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              languageOption('en', context.tr('English')),
              languageOption('zh', context.tr('Chinese')),
              languageOption('ms', context.tr('Malay')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
          ],
        );
      },
    );

    if (selectedLanguage != null) {
      await controller.setLanguage(selectedLanguage);
    }
  }

  String _currentLanguageName(BuildContext context) {
    return switch (context.languageController.languageCode) {
      'zh' => context.tr('Chinese'),
      'ms' => context.tr('Malay'),
      _ => context.tr('English'),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('My Profile'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Profile Header
          Container(
            width: double.infinity,
            color: const Color(0xFF1E3A8A),
            padding: const EdgeInsets.only(bottom: 32, top: 16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 50, color: Color(0xFF1E3A8A)),
                ),
                SizedBox(height: 16),
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // User Statistics
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn('142', context.tr('Trips Taken')),
                Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.3)),
                _buildStatColumn('3', context.tr('Saved Routes')),
                Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.3)),
                _buildStatColumn('2', context.tr('Active Alerts')),
              ],
            ),
          ),
          Container(height: 8, color: Colors.grey.withValues(alpha: 0.1)),

          // Settings & Menu Items
          Expanded(
            child: ListView(
              children: [
                _buildMenuTile(
                    icon: Icons.history,
                    iconColor: Colors.blue,
                    title: context.tr('Travel History'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr('Viewing recent trips...'),
                          ),
                        ),
                      );
                    }
                ),
                _buildMenuTile(
                  icon: Icons.notifications_active,
                  iconColor: Colors.orange,
                  title: context.tr('Smart Reminders'),
                  onTap: _showRemindersDialog,
                ),
                _buildMenuTile(
                  icon: Icons.work,
                  iconColor: Colors.indigo,
                  title: context.tr('Daily Commute Settings'),
                  onTap: () {},
                ),
                _buildMenuTile(
                  icon: Icons.favorite,
                  iconColor: Colors.pink,
                  title: context.tr('Favourite Routes'),
                  onTap: () {},
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(height: 1),
                ),
                _buildMenuTile(
                  icon: Icons.edit,
                  iconColor: Colors.teal,
                  title: context.tr('Edit Profile'),
                  onTap: _openEditProfile,
                ),
                _buildMenuTile(
                  icon: Icons.language,
                  iconColor: Colors.blue,
                  title: context.tr('Language'),
                  subtitle: _currentLanguageName(context),
                  onTap: _showLanguageDialog,
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.logout, color: Colors.red),
                  ),
                  title: Text(
                    context.tr('Sign Out'),
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () async {
                    await Supabase.instance.client.auth.signOut();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String val, String label) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: onTap,
        ),
        Divider(height: 1, indent: 72, endIndent: 24, color: Colors.grey.withValues(alpha: 0.2)),
      ],
    );
  }
}
