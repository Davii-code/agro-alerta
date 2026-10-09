import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'database_service.dart';

/// What the dashboard indicator shows. The old UI displayed a fixed yellow
/// "MODO DE SINCRONIZACAO OFFLINE ATIVO" banner regardless of the real state,
/// and always reported success after a sync even when the batch had failed.
enum SyncStatus {
  /// Nothing pending, last attempt succeeded.
  upToDate,

  /// Records waiting, no usable connection.
  offlinePending,

  /// A push is in flight.
  syncing,

  /// Connection exists but the last push failed.
  error,

  /// Signed in with a local stub identity, so nothing can be pushed.
  blockedNoAccount,
}

class SyncState {
  final SyncStatus status;
  final int pending;
  final String? message;
  final DateTime? lastSuccess;

  const SyncState({
    required this.status,
    required this.pending,
    this.message,
    this.lastSuccess,
  });
}

/// Pushes locally queued records to Supabase (RF02).
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static const int _batchSize = 50;

  final _db = DatabaseService();
  final _auth = AuthService();
  final _controller = StreamController<SyncState>.broadcast();

  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;
  bool _hasConnection = true;
  DateTime? _lastSuccess;

  /// Screens listen to this instead of guessing.
  Stream<SyncState> get stream => _controller.stream;

  SyncState get currentState => _buildState(
        _isSyncing ? SyncStatus.syncing : _idleStatus(),
      );

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  void start() {
    _syncTimer?.cancel();

    // Two triggers rather than one. The timer is the safety net; the
    // connectivity stream is what makes "syncs when the signal comes back"
    // actually true instead of "syncs up to 30 s later".
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => triggerSync());

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      final regained = online && !_hasConnection;
      _hasConnection = online;
      _emit();
      if (regained) triggerSync();
    });

    Connectivity().checkConnectivity().then((results) {
      _hasConnection = results.any((r) => r != ConnectivityResult.none);
      _emit();
    });
  }

  void stop() {
    _syncTimer?.cancel();
    _connectivitySub?.cancel();
  }

  Future<SyncState> triggerSync() async {
    if (_isSyncing) return currentState;

    // Nothing queued: say so and stop. Without this the 30 s timer kept
    // reporting "entre com sua conta" on the login screen, where there is no
    // signed-in user and also nothing to send.
    if (_db.pendingCount == 0) {
      return _emit(status: SyncStatus.upToDate);
    }

    if (!_isSupabaseInitialized || !_hasConnection) {
      return _emit(status: SyncStatus.offlinePending);
    }

    final user = _auth.currentUser;
    // A non-UUID owner id can never satisfy `auth.uid() = observer_id`, so the
    // insert would be rejected by RLS, swallowed by the catch, and the record
    // would sit in the queue forever. Surface it instead of retrying blindly.
    if (user == null || !_uuidPattern.hasMatch(user.id)) {
      return _emit(
        status: SyncStatus.blockedNoAccount,
        message: 'Entre com sua conta para enviar os registros guardados.',
      );
    }

    _isSyncing = true;
    _emit(status: SyncStatus.syncing);

    try {
      final client = Supabase.instance.client;

      await _db.pruneOrphanSamplings();

      // Deletions first: replaying a tombstone after pushing would re-upload a
      // field the producer just removed, and the row would survive the sync.
      await _pushFieldDeletions(client);

      // Fields first: a sampling references field_id, so pushing a sampling
      // before its field violates samplings_field_id_fkey.
      await _pushFields(client);
      await _pushSamplings(client);

      _lastSuccess = DateTime.now();
      _isSyncing = false;
      return _emit(status: _idleStatus());
    } catch (e) {
      _isSyncing = false;
      debugPrint('SyncService: falha ao sincronizar ($e)');
      return _emit(
        status: SyncStatus.error,
        message: 'Não foi possível enviar agora. Vamos tentar de novo sozinho.',
      );
    }
  }

  /// Applies the fields the producer deleted on the phone to the server.
  ///
  /// Each tombstone is cleared only after its delete returns, so a failed call
  /// is retried on the next sync instead of leaving the row orphaned on the
  /// server, where the next refresh would pull it back into the list.
  Future<void> _pushFieldDeletions(SupabaseClient client) async {
    final ids = _db.getDeletedFieldIds();
    if (ids.isEmpty) return;

    for (final id in ids) {
      try {
        await client.from('fields').delete().eq('id', id);
        await _db.clearDeletedFieldId(id);
      } catch (e) {
        // A field that was never pushed has no server row; the delete is a
        // no-op and the tombstone can go. Anything else stays queued.
        debugPrint('SyncService: falha ao apagar o talhão $id no servidor ($e)');
      }
    }
  }

  Future<void> _pushFields(SupabaseClient client) async {
    final pending = _db.getUnsyncedFields();
    if (pending.isEmpty) return;

    for (final chunk in _chunk(pending, _batchSize)) {
      // upsert, not insert: if a previous attempt committed server-side but the
      // local flag never flipped, a plain insert would duplicate the row.
      await client
          .from('fields')
          .upsert(chunk.map((f) => f.toJson()).toList(), onConflict: 'id');
      for (final f in chunk) {
        await _db.markFieldSynced(f.id);
      }
    }
  }

  Future<void> _pushSamplings(SupabaseClient client) async {
    final pending = _db.getUnsyncedSamplings();
    if (pending.isEmpty) return;

    for (final chunk in _chunk(pending, _batchSize)) {
      await client
          .from('samplings')
          .upsert(chunk.map((s) => s.toJson()).toList(), onConflict: 'id');
      for (final s in chunk) {
        await _db.markSamplingSynced(s.id);
      }
    }
  }

  SyncStatus _idleStatus() =>
      _db.pendingCount > 0 ? SyncStatus.offlinePending : SyncStatus.upToDate;

  SyncState _buildState(SyncStatus status, [String? message]) => SyncState(
        status: status,
        pending: _db.pendingCount,
        message: message,
        lastSuccess: _lastSuccess,
      );

  SyncState _emit({SyncStatus? status, String? message}) {
    final state = _buildState(status ?? _idleStatus(), message);
    if (!_controller.isClosed) _controller.add(state);
    return state;
  }

  List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}
