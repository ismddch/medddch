class AppConstants {
  // ─── App Info ───────────────────────────────────────────
  static const String appName   = 'حلاقك';
  static const String appNameEn = 'Halaqak';

  // ─── Amount limits ───────────────────────────────────────
  static const double maxPaymentAmount = 1000000;
  static const double minPaymentAmount = 1;

  // ─── Safe error message ──────────────────────────────────
  /// Strip internal Supabase/Dart stack details before showing to the user.
  static String safeError(Object e) {
    final raw = e.toString().replaceAll('Exception: ', '').trim();
    // Known Arabic user-facing messages pass through directly
    if (_isArabic(raw)) return raw;
    // Anything else is an internal error — show a generic message
    return 'حدث خطأ، يرجى المحاولة مرة أخرى';
  }

  static bool _isArabic(String s) =>
      s.runes.any((r) => r >= 0x0600 && r <= 0x06FF);
}

/// Supported payment wallets — single source of truth used by both
/// the barber panel (to set account numbers) and the customer payment
/// screen (to display the correct number when a wallet is selected).

/// Supported payment wallets — single source of truth used by both
/// the barber panel (to set account numbers) and the customer payment
/// screen (to display the correct number when a wallet is selected).
const List<Map<String, String>> kWallets = [
  {'key': 'Bankily', 'label': 'Bankily'},
  {'key': 'Sedad',   'label': 'Sedad'},
  {'key': 'Masrvi',  'label': 'Masrvi'},
  {'key': 'Click',   'label': 'Click'},
];
