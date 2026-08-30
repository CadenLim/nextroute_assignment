import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.signedInScreen,
  });

  final Widget signedInScreen;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;

        if (session == null) {
          return const AuthScreen();
        }

        return signedInScreen;
      },
    );
  }
}