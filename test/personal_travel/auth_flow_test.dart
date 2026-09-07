import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nextroute_assignment/screens/auth_screen.dart';
import 'package:nextroute_assignment/services/personal_travel_service.dart';

import 'saved_routes_test.dart'
    show MemoryRoutes, PlanningApi, sampleRoute, launch;
import 'package:nextroute_assignment/screens/journey_planning.dart';

const _userId = '00000000-0000-4000-8000-000000000001';

class TestAuthStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

Map<String, dynamic> sessionJson() {
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': _userId, 'exp': expiry})))
      .replaceAll('=', '');
  return {
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': _userId,
      'aud': 'authenticated',
      'email': 'test@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
}

class TestLoginAttemptGuard implements LoginAttemptGuard {
  TestLoginAttemptGuard({this.accountExists = true, this.valid = true});

  bool accountExists;
  bool valid;
  int failedAttempts = 0;
  bool locked = false;
  final attemptedEmails = <String>[];

  @override
  Future<void> verifyLogin({
    required String email,
    required String password,
  }) async {
    attemptedEmails.add(email);
    if (!accountExists) {
      throw const AuthException('No user found with this email.');
    }
    if (locked) {
      throw const AuthException(
        'Too many failed login attempts. Please try again in 15 minutes.',
      );
    }
    if (!valid) {
      failedAttempts++;
      if (failedAttempts >= 5) {
        locked = true;
        throw const AuthException(
          'Too many failed login attempts. Please try again in 15 minutes.',
        );
      }
      final remaining = 5 - failedAttempts;
      throw AuthException(
        'Incorrect password. $remaining attempt${remaining == 1 ? '' : 's'} remaining.',
      );
    }
    failedAttempts = 0;
    locked = false;
  }
}

PasswordCodeLogin mockPasswordLogin(
  GoTrueClient auth, {
  bool valid = true,
  TestLoginAttemptGuard? loginAttemptGuard,
}) => PasswordCodeLogin(
  auth: auth,
  projectUrl: 'https://example.supabase.co',
  publishableKey: 'test-key',
  loginAttemptGuard: loginAttemptGuard ?? TestLoginAttemptGuard(valid: valid),
  passwordClientFactory: () => MockClient((request) async {
    expect(auth.currentSession, isNull);
    if (request.url.path.endsWith('/logout')) {
      expect(request.url.queryParameters['scope'], 'local');
      return http.Response('', 204);
    }
    expect(request.url.queryParameters['grant_type'], 'password');
    expect(jsonDecode(request.body)['password'], 'test-password');
    return http.Response(
      valid ? jsonEncode(sessionJson()) : '{"msg":"Invalid login credentials"}',
      valid ? 200 : 400,
      headers: {'content-type': 'application/json'},
    );
  }),
);

Future<void> openLogin(
  WidgetTester tester,
  GoTrueClient client, {
  PasswordCodeLogin? passwordLogin,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => AuthScreen(
                  auth: client,
                  passwordLogin: passwordLogin ?? mockPasswordLogin(client),
                ),
              ),
            ),
            child: const Text('Browse as guest'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Browse as guest'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('registration requires an eight character password', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: TestAuthStorage(),
      flowType: AuthFlowType.pkce,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    await openLogin(tester, client);
    await tester.tap(find.text('New user? Create an account'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Tester');
    await tester.enterText(fields.at(1), 'test@example.com');
    await tester.enterText(fields.at(2), '123456');
    await tester.tap(find.text('Register'));
    await tester.pump();

    expect(
      find.text('Password must contain at least 8 characters.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
  });

  testWidgets('wrong password shows a specific error and never sends OTP', (
    tester,
  ) async {
    final otpRequests = <http.Request>[];
    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: TestAuthStorage(),
      flowType: AuthFlowType.pkce,
      httpClient: MockClient((request) async {
        otpRequests.add(request);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    final loginGuard = TestLoginAttemptGuard(valid: false);
    await openLogin(
      tester,
      client,
      passwordLogin: mockPasswordLogin(client, loginAttemptGuard: loginGuard),
    );
    await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');
    await tester.tap(find.text('Send sign-in code'));
    await tester.pumpAndSettle();
    expect(loginGuard.attemptedEmails, ['test@example.com']);
    expect(otpRequests, isEmpty);
    expect(client.currentSession, isNull);
    expect(
      find.text('Incorrect password. 4 attempts remaining.'),
      findsOneWidget,
    );
    expect(find.text('Verify your email'), findsNothing);
  });

  testWidgets('unknown login email shows no-user-found error', (tester) async {
    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: TestAuthStorage(),
      flowType: AuthFlowType.pkce,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(client.dispose);
    final loginGuard = TestLoginAttemptGuard(accountExists: false);
    await openLogin(
      tester,
      client,
      passwordLogin: mockPasswordLogin(client, loginAttemptGuard: loginGuard),
    );
    await tester.enterText(find.byType(TextField).at(0), 'missing@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');
    await tester.tap(find.text('Send sign-in code'));
    await tester.pumpAndSettle();
    expect(find.text('No user found with this email.'), findsOneWidget);
    expect(client.currentSession, isNull);
    expect(loginGuard.failedAttempts, 0);
  });

  testWidgets('fifth incorrect password locks login and success resets count', (
    tester,
  ) async {
    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: TestAuthStorage(),
      flowType: AuthFlowType.pkce,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    addTearDown(client.dispose);
    final loginGuard = TestLoginAttemptGuard(valid: false);
    await openLogin(
      tester,
      client,
      passwordLogin: mockPasswordLogin(client, loginAttemptGuard: loginGuard),
    );
    await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-password');

    for (var attempt = 1; attempt <= 5; attempt++) {
      await tester.tap(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
    }
    expect(loginGuard.failedAttempts, 5);
    expect(loginGuard.locked, isTrue);
    expect(
      find.text(
        'Too many failed login attempts. Please try again in 15 minutes.',
      ),
      findsOneWidget,
    );

    loginGuard.locked = false;
    loginGuard.valid = true;
    await tester.tap(find.text('Send sign-in code'));
    await tester.pumpAndSettle();
    expect(loginGuard.failedAttempts, 0);
    expect(find.text('Verify your email'), findsOneWidget);
  });

  testWidgets(
    'guest sign-in prompt returns to the selected route and resumes saving',
    (tester) async {
      final client = GoTrueClient(
        url: 'https://example.supabase.co/auth/v1',
        autoRefreshToken: false,
        asyncStorage: TestAuthStorage(),
        flowType: AuthFlowType.pkce,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/verify') ? sessionJson() : {},
            ),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(client.dispose);
      final repository = MemoryRoutes();
      await launch(
        tester,
        JourneyPlanningScreen(
          apiService: PlanningApi(),
          savedRoute: sampleRoute(),
          savedRoutesRepository: repository,
          authenticate: (context) => requireSignIn(
            context,
            authClient: client,
            passwordLogin: mockPasswordLogin(client),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Save route'));
      await tester.tap(find.text('Save route'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to save this route'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(repository.routes, isEmpty);
      await tester.tap(find.text('Save route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'test-password');
      await tester.tap(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
      expect(repository.routes, isEmpty);
      expect(client.currentSession, isNull);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.ensureVisible(find.text('Verify Code'));
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(find.text('Route name'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.routes.single.signature, sampleRoute().signature);
    },
  );

  testWidgets('profile switches back to guest after sign-out', (tester) async {
    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: TestAuthStorage(),
      flowType: AuthFlowType.pkce,
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(sessionJson()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);
    await launch(
      tester,
      AuthGate(
        authClient: client,
        signedInScreen: const Text('Private profile'),
      ),
    );
    expect(find.text('Private profile'), findsNothing);
    await client.verifyOTP(
      type: OtpType.email,
      email: 'test@example.com',
      token: '123456',
    );
    await tester.pumpAndSettle();
    expect(find.text('Private profile'), findsOneWidget);
    await client.signOut(scope: SignOutScope.local);
    await tester.pumpAndSettle();
    expect(find.text('Private profile'), findsNothing);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets(
    'login checks password then sends OTP, and only signs in after verification',
    (tester) async {
      final requests = <http.Request>[];
      var validCode = false;
      final client = GoTrueClient(
        url: 'https://example.supabase.co/auth/v1',
        autoRefreshToken: false,
        asyncStorage: TestAuthStorage(),
        flowType: AuthFlowType.pkce,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/verify')) {
            if (!validCode) {
              return http.Response(
                '{"msg":"Invalid code"}',
                400,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode(sessionJson()),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final loginGuard = TestLoginAttemptGuard();
      await openLogin(
        tester,
        client,
        passwordLogin: mockPasswordLogin(client, loginAttemptGuard: loginGuard),
      );
      expect(find.text('Password'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'test@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'test-password');
      await tester.tap(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
      expect(client.currentSession, isNull);
      expect(loginGuard.attemptedEmails, ['test@example.com']);
      expect(requests.single.url.path, '/auth/v1/otp');
      expect(jsonDecode(requests.single.body)['create_user'], false);
      expect(find.text('Verify your email'), findsOneWidget);
      final verificationField = tester.widget<TextField>(
        find.byKey(const Key('auth-verification-code')),
      );
      expect(verificationField.focusNode?.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '123450');
      await tester.ensureVisible(find.text('Verify Code'));
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(client.currentSession, isNull);
      expect(find.text('Invalid code'), findsOneWidget);
      expect(jsonDecode(requests.last.body)['type'], 'email');
      validCode = true;
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(client.currentUser?.id, _userId);
      expect(find.text('Browse as guest'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'register verifies signup OTP and cancelling login leaves a guest session',
    (tester) async {
      final requests = <http.Request>[];
      final client = GoTrueClient(
        url: 'https://example.supabase.co/auth/v1',
        autoRefreshToken: false,
        asyncStorage: TestAuthStorage(),
        flowType: AuthFlowType.pkce,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/verify')
                  ? sessionJson()
                  : sessionJson()['user'],
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await openLogin(tester, client);
      await tester.tap(find.text('Continue as guest'));
      await tester.pumpAndSettle();
      expect(client.currentSession, isNull);
      expect(requests, isEmpty);
      await tester.tap(find.text('Browse as guest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New user? Create an account'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Tester');
      await tester.enterText(fields.at(1), 'test@example.com');
      await tester.enterText(fields.at(2), 'test-password');
      await tester.ensureVisible(find.text('Register'));
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(client.currentSession, isNull);
      expect(requests.first.url.path, '/auth/v1/signup');
      final verificationField = tester.widget<TextField>(
        find.byKey(const Key('auth-verification-code')),
      );
      expect(verificationField.focusNode?.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.ensureVisible(find.text('Verify Code'));
      await tester.tap(find.text('Verify Code'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests.last.body)['type'], 'signup');
      expect(client.currentUser?.id, _userId);
    },
  );

  testWidgets('forgot password resets through a six digit recovery code', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = GoTrueClient(
      url: 'https://example.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: TestAuthStorage(),
      flowType: AuthFlowType.pkce,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/verify')) {
          return http.Response(
            jsonEncode(sessionJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/user')) {
          return http.Response(
            jsonEncode(sessionJson()['user']),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/logout')) {
          return http.Response('', 204);
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await openLogin(tester, client);

    await tester.tap(find.byKey(const Key('forgot-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reset-email')),
      'test@example.com',
    );
    await tester.tap(find.byKey(const Key('send-reset-code')));
    await tester.pumpAndSettle();
    expect(requests.last.url.path, '/auth/v1/recover');
    expect(jsonDecode(requests.last.body)['email'], 'test@example.com');
    final resetCodeField = tester.widget<TextField>(
      find.byKey(const Key('reset-code')),
    );
    expect(resetCodeField.focusNode?.hasFocus, isTrue);

    await tester.enterText(find.byKey(const Key('reset-code')), '123456');
    await tester.tap(find.byKey(const Key('verify-reset-code')));
    await tester.pumpAndSettle();
    expect(jsonDecode(requests.last.body)['type'], 'recovery');
    expect(find.text('Create new password'), findsOneWidget);

    final newPassword = find.byKey(const Key('reset-new-password'));
    expect(tester.widget<TextField>(newPassword).obscureText, isTrue);
    await tester.tap(
      find.descendant(
        of: newPassword,
        matching: find.byTooltip('Show password'),
      ),
    );
    await tester.pump();
    expect(tester.widget<TextField>(newPassword).obscureText, isFalse);

    await tester.enterText(newPassword, 'new-password');
    await tester.enterText(
      find.byKey(const Key('reset-confirm-password')),
      'new-password',
    );
    await tester.tap(find.byKey(const Key('reset-password-submit')));
    await tester.pumpAndSettle();
    expect(
      requests.any((request) => request.url.path.endsWith('/user')),
      isTrue,
    );
    expect(
      requests.any((request) => request.url.path.endsWith('/logout')),
      isTrue,
    );
    expect(client.currentSession, isNull);
    expect(
      find.text('Password reset successfully. Sign in with your new password.'),
      findsOneWidget,
    );
  });

  testWidgets('password change requires old, new and matching confirmation', (
    tester,
  ) async {
    String? receivedOldPassword;
    String? receivedNewPassword;
    var rejectOldPassword = true;
    await launch(
      tester,
      EditProfileScreen(
        displayName: 'Tester',
        email: 'test@example.com',
        phoneNumber: '',
        changePassword: (oldPassword, newPassword) async {
          receivedOldPassword = oldPassword;
          receivedNewPassword = newPassword;
          if (rejectOldPassword) {
            throw const AuthException('Invalid login credentials');
          }
        },
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('change-password')));
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();
    final oldPasswordField = find.byKey(const Key('old-password'));
    final oldPasswordTextField = find.descendant(
      of: oldPasswordField,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(oldPasswordTextField).obscureText, isTrue);
    await tester.tap(
      find.descendant(
        of: oldPasswordField,
        matching: find.byTooltip('Show password'),
      ),
    );
    await tester.pump();
    expect(tester.widget<TextField>(oldPasswordTextField).obscureText, isFalse);
    await tester.enterText(find.byKey(const Key('old-password')), 'old-secret');
    await tester.enterText(find.byKey(const Key('new-password')), 'new-secret');
    await tester.enterText(
      find.byKey(const Key('confirm-password')),
      'different',
    );
    await tester.tap(find.byKey(const Key('confirm-password-change')));
    await tester.pump();
    expect(find.text('New passwords do not match.'), findsOneWidget);
    final confirmationTextField = find.descendant(
      of: find.byKey(const Key('confirm-password')),
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(confirmationTextField).decoration?.errorMaxLines,
      3,
    );
    expect(receivedOldPassword, isNull);

    await tester.enterText(
      find.byKey(const Key('confirm-password')),
      'new-secret',
    );
    await tester.tap(find.byKey(const Key('confirm-password-change')));
    await tester.pumpAndSettle();
    expect(receivedOldPassword, 'old-secret');
    expect(receivedNewPassword, 'new-secret');
    expect(find.text('Old password is incorrect.'), findsOneWidget);
    expect(find.byKey(const Key('old-password')), findsOneWidget);

    rejectOldPassword = false;
    await tester.tap(find.byKey(const Key('confirm-password-change')));
    await tester.pumpAndSettle();
    expect(find.text('Password updated successfully.'), findsOneWidget);
  });
}
