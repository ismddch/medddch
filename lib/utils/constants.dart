/// Supabase configuration constants.
/// Replace these with your actual Supabase project credentials.
class AppConstants {
  // ─── Supabase ───────────────────────────────────────────
  static const String supabaseUrl = 'https://YOUR_PROJECT_REF.supabase.co';
  static const String supabaseAnonKey = 'YOUR_ANON_KEY';

  // ─── App Info ───────────────────────────────────────────
  static const String appName = 'حلاقك';
  static const String appNameEn = 'Halaqak';
}

/// Supported payment wallets — single source of truth used by both
/// the barber panel (to set account numbers) and the customer payment
/// screen (to display the correct number when a wallet is selected).
const List<Map<String, String>> kWallets = [
  {'key': 'Bankily', 'label': 'Bankily'},
  {'key': 'Sedad',   'label': 'Sedad'},
  {'key': 'Masrvi',  'label': 'Masrvi'},
  {'key': 'Click',   'label': 'Click'},
];
