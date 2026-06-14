import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  Timer? _syncTimer;
  bool _isSyncing = false;

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  void startPeriodicSync() {
    _syncTimer?.cancel();
    // Check and sync every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      triggerSync();
    });
  }

  void stopPeriodicSync() {
    _syncTimer?.cancel();
  }

  Future<void> triggerSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      if (!_isSupabaseInitialized) {
        print("Sync Service: Supabase is not initialized. Sync skipped.");
        _isSyncing = false;
        return;
      }

      final db = DatabaseService();
      final unsynced = db.getUnsyncedSamplings();
      if (unsynced.isEmpty) {
        _isSyncing = false;
        return;
      }

      print("Sync Service: Found ${unsynced.length} records pending synchronization.");

      // Batch sync: up to 50 records at a time
      final client = Supabase.instance.client;
      final chunks = _chunkList(unsynced, 50);

      for (var chunk in chunks) {
        final payload = chunk.map((s) => s.toJson()).toList();
        
        // Push payload to Supabase
        await client.from('samplings').insert(payload);

        // Update local sync status
        for (var sampling in chunk) {
          await db.markSamplingSynced(sampling.id);
        }
        print("Sync Service: Successfully synchronized batch of ${chunk.length} records.");
      }
    } catch (e) {
      print("Sync Service Error: Sincronização falhou. Nova tentativa agendada. Detalhe: $e");
    } finally {
      _isSyncing = false;
    }
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }
}
