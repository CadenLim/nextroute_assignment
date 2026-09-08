import 'package:flutter/material.dart';

import '../services/database.dart';

class SupabaseConnectionScreen extends StatefulWidget {
  const SupabaseConnectionScreen({super.key});

  @override
  State<SupabaseConnectionScreen> createState() =>
      _SupabaseConnectionScreenState();
}

class _SupabaseConnectionScreenState extends State<SupabaseConnectionScreen> {
  late Future<String> _connectionResult;

  @override
  void initState() {
    super.initState();
    _connectionResult = Database.checkConnection();
  }

  void _retry() {
    setState(() {
      _connectionResult = Database.checkConnection();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NextRoute'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<String>(
            future: _connectionResult,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Connecting to Supabase...'),
                  ],
                );
              }

              final error = snapshot.error;
              final isConnected = error == null && snapshot.hasData;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isConnected ? Icons.cloud_done : Icons.cloud_off,
                    size: 72,
                    color: isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isConnected
                        ? 'Connected to Supabase'
                        : 'Unable to connect to Supabase',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isConnected ? snapshot.data! : error.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
