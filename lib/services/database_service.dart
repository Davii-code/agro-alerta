import 'package:hive_flutter/hive_flutter.dart';
import '../models/field_model.dart';
import '../models/sampling_model.dart';

/// Local-first storage. Every write in the app lands here first; the network is
/// always a later, optional step (RF01).
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  late Box<FieldModel> _fieldBox;
  late Box<SamplingModel> _samplingBox;

  /// Untyped string box for reference data and small flags. Using JSON strings
  /// instead of typed adapters means reference data can gain fields without a
  /// Hive schema migration on the producer's phone.
  late Box<String> _cacheBox;

  /// [directory] exists for tests: Hive.initFlutter() resolves the app
  /// documents path through path_provider, which has no implementation under
  /// flutter_test. Passing a temp dir lets the storage layer be tested for
  /// real instead of behind a mock that cannot catch a Hive-level mistake.
  Future<void> init({String? directory}) async {
    if (directory != null) {
      Hive.init(directory);
    } else {
      await Hive.initFlutter();
    }

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FieldModelAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SamplingModelAdapter());
    }

    _fieldBox = await Hive.openBox<FieldModel>('fields');
    _samplingBox = await Hive.openBox<SamplingModel>('samplings');
    _cacheBox = await Hive.openBox<String>('cache');
  }

  // --- FIELDS ---------------------------------------------------------------

  Future<void> saveField(FieldModel field) async {
    // The box key is the model id, so put() behaves as an upsert.
    await _fieldBox.put(field.id, field);
  }

  Future<void> saveFields(List<FieldModel> fields) async {
    await _fieldBox.putAll({for (final f in fields) f.id: f});
  }

  List<FieldModel> getFields() => _fieldBox.values.toList();

  FieldModel? getField(String id) => _fieldBox.get(id);

  /// Fields created while offline. They queue exactly like samplings do, so a
  /// field registered with no signal is not lost (RF02).
  List<FieldModel> getUnsyncedFields() =>
      _fieldBox.values.where((f) => !f.isSynced).toList();

  Future<void> markFieldSynced(String id) async {
    final field = _fieldBox.get(id);
    if (field == null) return;
    field.isSynced = true;
    await field.save();
  }

  Future<void> deleteField(String id) async {
    // Drop the field's samplings too, otherwise they become orphans that can
    // never satisfy the samplings_field_id_fkey constraint on sync.
    final orphans =
        _samplingBox.values.where((s) => s.fieldId == id).map((s) => s.id).toList();
    await _samplingBox.deleteAll(orphans);
    await _fieldBox.delete(id);
    // A local delete alone does not stick: HomeScreen refreshes from
    // `fields` on every load and would write the row straight back. Record the
    // id so the refresh skips it and SyncService can delete it server-side.
    await _recordDeletedField(id);
  }

  Future<void> clearFields() async => _fieldBox.clear();

  // --- SAMPLINGS ------------------------------------------------------------

  Future<void> saveSampling(SamplingModel sampling) async {
    await _samplingBox.put(sampling.id, sampling);
  }

  List<SamplingModel> getSamplings() => _samplingBox.values.toList();

  /// Newest first, for the history screen.
  List<SamplingModel> getSamplingsSorted() {
    final list = _samplingBox.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<SamplingModel> getSamplingsForField(String fieldId) {
    final list =
        _samplingBox.values.where((s) => s.fieldId == fieldId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  SamplingModel? getLatestSamplingForField(String fieldId) {
    final list = getSamplingsForField(fieldId);
    return list.isEmpty ? null : list.first;
  }

  List<SamplingModel> getUnsyncedSamplings() =>
      _samplingBox.values.where((s) => !s.isSynced).toList();

  /// Drives the sync badge and the "nothing to send" short-circuit in
  /// SyncService. Pending deletions count: a tombstone is queued work too, and
  /// leaving it out meant triggerSync() returned early and never replayed it.
  int get pendingCount =>
      getUnsyncedSamplings().length +
      getUnsyncedFields().length +
      getDeletedFieldIds().length;

  Future<void> markSamplingSynced(String id) async {
    final sampling = _samplingBox.get(id);
    if (sampling == null) return;
    sampling.isSynced = true;
    await sampling.save();
  }

  /// Removes samplings whose field no longer exists locally. Such records can
  /// never be inserted (foreign key on field_id) and would block the queue
  /// forever if left in place.
  Future<int> pruneOrphanSamplings() async {
    final fieldIds = _fieldBox.keys.toSet();
    final orphans = _samplingBox.values
        .where((s) => !fieldIds.contains(s.fieldId))
        .map((s) => s.id)
        .toList();
    if (orphans.isNotEmpty) await _samplingBox.deleteAll(orphans);
    return orphans.length;
  }

  Future<void> clearSamplings() async => _samplingBox.clear();

  // --- CACHE / FLAGS --------------------------------------------------------

  Future<void> putCache(String key, String value) => _cacheBox.put(key, value);

  String? getCache(String key) => _cacheBox.get(key);

  bool hasSeenOnboarding() => _cacheBox.get('onboarding_done') == 'true';

  Future<void> markOnboardingSeen() => _cacheBox.put('onboarding_done', 'true');

  // --- DELETION QUEUE -------------------------------------------------------

  /// Ids of fields deleted on the phone whose server row is still there.
  ///
  /// Deleting offline has to be remembered, not just applied: the next refresh
  /// reads `fields` from Supabase, and without a tombstone the deleted field
  /// comes back and the delete looks like it did nothing. Kept in the string
  /// cache box as a comma-separated list - a handful of uuids until the next
  /// successful sync, so a typed box would be overkill.
  static const _deletedFieldsKey = 'deleted_field_ids';

  Set<String> getDeletedFieldIds() {
    final raw = _cacheBox.get(_deletedFieldsKey);
    if (raw == null || raw.isEmpty) return const {};
    return raw.split(',').where((e) => e.isNotEmpty).toSet();
  }

  Future<void> _recordDeletedField(String id) async {
    final ids = getDeletedFieldIds().toSet()..add(id);
    await _cacheBox.put(_deletedFieldsKey, ids.join(','));
  }

  /// Called once the server row is gone, so the tombstone stops being replayed.
  Future<void> clearDeletedFieldId(String id) async {
    final ids = getDeletedFieldIds().toSet()..remove(id);
    if (ids.isEmpty) {
      await _cacheBox.delete(_deletedFieldsKey);
    } else {
      await _cacheBox.put(_deletedFieldsKey, ids.join(','));
    }
  }

  /// Wipes producer data on sign-out while keeping reference data cached.
  Future<void> clearUserData() async {
    await _fieldBox.clear();
    await _samplingBox.clear();
    // Tombstones belong to the account that created them. Leaving them behind
    // would hide another producer's fields with a colliding id.
    await _cacheBox.delete(_deletedFieldsKey);
  }
}
