# NextRoute

## Supabase setup

1. In the Supabase dashboard, open your project and select **Connect**.
2. Copy `config/supabase.example.json` to `config/supabase.json`.
3. Replace the placeholders with the project's **Project URL** and
   **Publishable Key**. Never put a `service_role` or secret key in this app.
4. Fetch dependencies and start Flutter with the local config:

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.json
```

For a release build, pass the same option:

```powershell
flutter build apk --dart-define-from-file=config/supabase.json
```

The initialized client is available through `Database.client` in
`lib/services/database.dart`. For example:

```dart
final rows = await Database.client.from('your_table').select();
```

`config/supabase.json` is ignored by Git. The publishable key is intended for
client applications, but database access must still be protected with Row Level
Security (RLS) policies in Supabase.
