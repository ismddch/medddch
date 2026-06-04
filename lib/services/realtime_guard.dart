import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Manages every Supabase Realtime channel in one place.
///
/// Solves four iOS-specific problems:
///   1. Channel name collisions — each registration gets a unique suffix.
///   2. Stale sockets after background/foreground — auto-reconnects on resume.
///   3. Event storms — a per-channel debounce collapses rapid bursts.
///   4. Leak prevention — a single dispose() tears down every channel.
///
/// Usage:
///   final guard = RealtimeGuard.instance;
///   guard.init();                          // once, in main()
///   guard.watchBarberQueue(id, onChanged); // in initState()
///   guard.cancel('barber-queue-$id');      // in dispose() — or call dispose()
class RealtimeGuard with WidgetsBindingObserver {
  RealtimeGuard._();
  static final RealtimeGuard instance = RealtimeGuard._();

  final _client = Supabase.instance.client;
  final Map<String, _Entry> _entries = {};

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void init() => WidgetsBinding.instance.addObserver(this);

  void disposeGuard() {
    WidgetsBinding.instance.removeObserver(this);
    for (final e in _entries.values) {
      e.debounce?.cancel();
      _client.removeChannel(e.channel);
    }
    _entries.clear();
  }

  /// iOS returns from background → WebSocket was killed → rebuild all channels.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reconnectAll();
  }

  void _reconnectAll() {
    for (final key in _entries.keys.toList()) {
      final entry = _entries[key]!;
      entry.debounce?.cancel();
      _client.removeChannel(entry.channel);
      final rebuilt = entry.rebuild();
      _entries[key] = entry.copyWith(channel: rebuilt, debounce: null);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Watch all queue changes for a single barber (filtered by barber_id).
  /// Replaces the broad 'queue-changes' channel that fired for every barber.
  RealtimeChannel watchBarberQueue(
    String barberId, {
    required VoidCallback onChanged,
    Duration debounce = const Duration(milliseconds: 300),
  }) =>
      _registerFiltered(
        key: 'barber-queue-$barberId',
        table: 'queues',
        event: PostgresChangeEvent.all,
        filterColumn: 'barber_id',
        filterValue: barberId,
        onChanged: onChanged,
        debounce: debounce,
      );

  /// Watch queue changes for a specific customer (filtered by user_id).
  RealtimeChannel watchUserQueueEntry(
    String userId, {
    required VoidCallback onChanged,
    Duration debounce = const Duration(milliseconds: 300),
  }) =>
      _registerFiltered(
        key: 'user-queue-$userId',
        table: 'queues',
        event: PostgresChangeEvent.all,
        filterColumn: 'user_id',
        filterValue: userId,
        onChanged: onChanged,
        debounce: debounce,
      );

  /// Watch new/updated payment requests for a barber.
  RealtimeChannel watchBarberPayments(
    String barberId, {
    required VoidCallback onChanged,
    Duration debounce = const Duration(milliseconds: 200),
  }) =>
      _registerFiltered(
        key: 'barber-payments-$barberId',
        table: 'payment_requests',
        event: PostgresChangeEvent.all,
        filterColumn: 'barber_id',
        filterValue: barberId,
        onChanged: onChanged,
        debounce: debounce,
      );

  /// Watch all queue changes for list screens (AllBarbers, ShopBarbers, Manager).
  /// Pass a [key] unique to the calling screen so screens don't cancel each other.
  RealtimeChannel watchAllQueues({
    required String key,
    required VoidCallback onChanged,
    Duration debounce = const Duration(milliseconds: 500),
  }) =>
      _registerBroadcast(
        key: 'all-queues-$key',
        table: 'queues',
        event: PostgresChangeEvent.all,
        onChanged: onChanged,
        debounce: debounce,
      );

  /// Watch all payment_requests changes (for manager / payment-manager screens).
  RealtimeChannel watchAllPayments({
    required String key,
    required VoidCallback onChanged,
    Duration debounce = const Duration(milliseconds: 300),
  }) =>
      _registerBroadcast(
        key: 'all-payments-$key',
        table: 'payment_requests',
        event: PostgresChangeEvent.all,
        onChanged: onChanged,
        debounce: debounce,
      );

  /// Watch payment status updates for a specific customer (approval/rejection).
  /// Delivers the full new record so the caller can react without a DB fetch.
  RealtimeChannel watchUserPaymentStatus(
    String userId, {
    required void Function(Map<String, dynamic> record) onRecord,
  }) {
    const key = 'user-payment-status';
    final fullKey = '$key-$userId';
    _unregister(fullKey);

    late RealtimeChannel ch;
    ch = _client
        .channel('$fullKey-${_ts()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'payment_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (p) => onRecord(p.newRecord),
        )
        .subscribe();

    _entries[fullKey] = _Entry(
      channel: ch,
      rebuild: () => watchUserPaymentStatus(
        userId,
        onRecord: onRecord,
      ),
    );
    return ch;
  }

  /// Cancel a specific channel by key prefix (e.g. 'barber-queue-$id').
  void cancel(String key) => _unregister(key);

  // ── Private ───────────────────────────────────────────────────────────────

  RealtimeChannel _registerFiltered({
    required String key,
    required String table,
    required PostgresChangeEvent event,
    required String filterColumn,
    required String filterValue,
    required VoidCallback onChanged,
    required Duration debounce,
  }) {
    _unregister(key);

    late RealtimeChannel ch;

    void handleEvent(PostgresChangePayload _) {
      final e = _entries[key];
      if (e == null) return;
      e.debounce?.cancel();
      _entries[key] = e.copyWith(
        debounce: Timer(debounce, onChanged),
      );
    }

    ch = _client
        .channel('$key-${_ts()}')
        .onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: filterColumn,
            value: filterValue,
          ),
          callback: handleEvent,
        )
        .subscribe();

    _entries[key] = _Entry(
      channel: ch,
      rebuild: () => _registerFiltered(
        key: key,
        table: table,
        event: event,
        filterColumn: filterColumn,
        filterValue: filterValue,
        onChanged: onChanged,
        debounce: debounce,
      ),
    );
    return ch;
  }

  RealtimeChannel _registerBroadcast({
    required String key,
    required String table,
    required PostgresChangeEvent event,
    required VoidCallback onChanged,
    required Duration debounce,
  }) {
    _unregister(key);

    void handleEvent(PostgresChangePayload _) {
      final e = _entries[key];
      if (e == null) return;
      e.debounce?.cancel();
      _entries[key] = e.copyWith(debounce: Timer(debounce, onChanged));
    }

    late RealtimeChannel ch;
    ch = _client
        .channel('$key-${_ts()}')
        .onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          callback: handleEvent,
        )
        .subscribe();

    _entries[key] = _Entry(
      channel: ch,
      rebuild: () => _registerBroadcast(
        key: key,
        table: table,
        event: event,
        onChanged: onChanged,
        debounce: debounce,
      ),
    );
    return ch;
  }

  void _unregister(String key) {
    final e = _entries.remove(key);
    if (e != null) {
      e.debounce?.cancel();
      _client.removeChannel(e.channel);
    }
  }

  String _ts() => DateTime.now().millisecondsSinceEpoch.toString();
}

// ── Internal model ────────────────────────────────────────────────────────────

class _Entry {
  final RealtimeChannel channel;
  final RealtimeChannel Function() rebuild;
  final Timer? debounce;

  const _Entry({
    required this.channel,
    required this.rebuild,
    this.debounce,
  });

  _Entry copyWith({RealtimeChannel? channel, Timer? debounce}) => _Entry(
        channel: channel ?? this.channel,
        rebuild: rebuild,
        debounce: debounce,
      );
}
