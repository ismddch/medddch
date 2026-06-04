/// All runtime secrets are injected at build time via --dart-define so they
/// never appear in source code or git history.
///
/// Build command:
///   flutter build ios \
///     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=sb_publishable_... \
///     --dart-define=FIREBASE_PROJECT_ID=your-project
///
/// CI: store these as GitHub Secrets and pass via the workflow env.
library app_config;

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '', // intentionally empty — fail fast if not set
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);
