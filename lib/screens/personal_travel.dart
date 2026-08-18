import 'package:flutter/material.dart';

class PersonalTravelScreen extends StatefulWidget {
  const PersonalTravelScreen({super.key});

  @override
  State<PersonalTravelScreen> createState() => _PersonalTravelScreenState();
}

class _PersonalTravelScreenState extends State<PersonalTravelScreen> {
  bool _morningReminder = true;
  bool _eveningReminder = false;

  void _showRemindersDialog() {
    showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text('Smart Reminders', style: TextStyle(fontWeight: FontWeight.bold)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SwitchListTile(
                        title: const Text('Morning Commute (7:30 AM)', style: TextStyle(fontSize: 14)),
                        value: _morningReminder,
                        activeColor: const Color(0xFF2563EB),
                        onChanged: (val) {
                          setDialogState(() => _morningReminder = val);
                          setState(() => _morningReminder = val);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Evening Return (6:00 PM)', style: TextStyle(fontSize: 14)),
                        value: _eveningReminder,
                        activeColor: const Color(0xFF2563EB),
                        onChanged: (val) {
                          setDialogState(() => _eveningReminder = val);
                          setState(() => _eveningReminder = val);
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Save & Close', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold))
                    )
                  ],
                );
              }
          );
        }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            child: const Column(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 50, color: Color(0xFF1E3A8A)),
                ),
                SizedBox(height: 16),
                Text('Rapid Explorer Integrator', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Kuala Lumpur, Malaysia', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),

          // User Statistics
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn('142', 'Trips Taken'),
                Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.3)),
                _buildStatColumn('3', 'Saved Routes'),
                Container(width: 1, height: 40, color: Colors.grey.withValues(alpha: 0.3)),
                _buildStatColumn('2', 'Active Alerts'),
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
                    title: 'Travel History',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Viewing recent trips...')));
                    }
                ),
                _buildMenuTile(
                  icon: Icons.notifications_active,
                  iconColor: Colors.orange,
                  title: 'Smart Reminders',
                  onTap: _showRemindersDialog,
                ),
                _buildMenuTile(
                  icon: Icons.work,
                  iconColor: Colors.indigo,
                  title: 'Daily Commute Settings',
                  onTap: () {},
                ),
                _buildMenuTile(
                  icon: Icons.favorite,
                  iconColor: Colors.pink,
                  title: 'Favourite Routes',
                  onTap: () {},
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(height: 1),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.logout, color: Colors.red),
                  ),
                  title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logging out...')));
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

  Widget _buildMenuTile({required IconData icon, required Color iconColor, required String title, required VoidCallback onTap}) {
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
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: onTap,
        ),
        Divider(height: 1, indent: 72, endIndent: 24, color: Colors.grey.withValues(alpha: 0.2)),
      ],
    );
  }
}