import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:agro_alerta/models/field_model.dart';
import 'package:agro_alerta/models/sampling_model.dart';
import 'package:agro_alerta/services/database_service.dart';

/// Deleting a field used to look like it did nothing: the local row went away
/// and the next HomeScreen refresh wrote it straight back from Supabase. These
/// tests cover the tombstone that makes a delete stick.
///
/// They run against a real Hive box in a temp directory, because the bug was in
/// the storage layer itself - a mocked box would have passed either way.
void main() {
  late Directory tempDir;
  final db = DatabaseService();

  FieldModel field(String id) => FieldModel(
        id: id,
        producerId: 'producer-1',
        name: 'Talhão $id',
        cropType: 'soja',
        plantingDate: DateTime(2026, 1, 1),
        latitude: -16.32,
        longitude: -48.95,
        createdAt: DateTime(2026, 1, 1),
        isSynced: true,
      );

  SamplingModel sampling(String id, String fieldId) => SamplingModel(
        id: id,
        fieldId: fieldId,
        observerId: 'producer-1',
        species: 'Lagarta-da-soja',
        count: 7,
        unit: 'insetos',
        method: 'pano',
        latitude: -16.32,
        longitude: -48.95,
        createdAt: DateTime(2026, 1, 1),
        isSynced: true,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agro_alerta_test');
    await db.init(directory: tempDir.path);
    // DatabaseService is a singleton, so boxes survive between tests.
    await db.clearFields();
    await db.clearSamplings();
    await db.clearUserData();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('deleteField', () {
    test('removes the field from local storage', () async {
      await db.saveField(field('a'));
      expect(db.getFields().map((f) => f.id), ['a']);

      await db.deleteField('a');

      expect(db.getFields(), isEmpty);
      expect(db.getField('a'), isNull);
    });

    test('drops the field samplings and keeps every other field intact',
        () async {
      await db.saveField(field('a'));
      await db.saveField(field('b'));
      await db.saveSampling(sampling('s1', 'a'));
      await db.saveSampling(sampling('s2', 'a'));
      await db.saveSampling(sampling('s3', 'b'));

      await db.deleteField('a');

      expect(db.getSamplingsForField('a'), isEmpty);
      expect(db.getSamplingsForField('b').map((s) => s.id), ['s3']);
      expect(db.getFields().map((f) => f.id), ['b']);
    });

    test('records a tombstone, so a refresh cannot resurrect the field',
        () async {
      await db.saveField(field('a'));
      await db.deleteField('a');

      expect(db.getDeletedFieldIds(), {'a'});
    });

    test('keeps one tombstone per deleted field', () async {
      await db.saveField(field('a'));
      await db.saveField(field('b'));
      await db.deleteField('a');
      await db.deleteField('b');

      expect(db.getDeletedFieldIds(), {'a', 'b'});
    });

    test('deleting the same field twice does not duplicate its tombstone',
        () async {
      await db.saveField(field('a'));
      await db.deleteField('a');
      await db.deleteField('a');

      expect(db.getDeletedFieldIds(), {'a'});
    });
  });

  group('tombstone lifecycle', () {
    test('counts as pending work, so triggerSync does not short-circuit',
        () async {
      await db.saveField(field('a'));
      expect(db.pendingCount, 0, reason: 'synced field, nothing queued');

      await db.deleteField('a');

      expect(db.pendingCount, 1);
    });

    test('clearing one tombstone leaves the others queued', () async {
      await db.saveField(field('a'));
      await db.saveField(field('b'));
      await db.deleteField('a');
      await db.deleteField('b');

      await db.clearDeletedFieldId('a');

      expect(db.getDeletedFieldIds(), {'b'});
      expect(db.pendingCount, 1);
    });

    test('clearing the last tombstone empties the queue', () async {
      await db.saveField(field('a'));
      await db.deleteField('a');

      await db.clearDeletedFieldId('a');

      expect(db.getDeletedFieldIds(), isEmpty);
      expect(db.pendingCount, 0);
    });

    test('signing out discards tombstones with the rest of the producer data',
        () async {
      await db.saveField(field('a'));
      await db.saveSampling(sampling('s1', 'a'));
      await db.deleteField('a');

      await db.clearUserData();

      expect(db.getDeletedFieldIds(), isEmpty);
      expect(db.getFields(), isEmpty);
      expect(db.getSamplings(), isEmpty);
    });

    test('survives reopening the boxes, so an offline delete is not lost',
        () async {
      await db.saveField(field('a'));
      await db.deleteField('a');

      await Hive.close();
      await db.init(directory: tempDir.path);

      expect(db.getDeletedFieldIds(), {'a'});
    });
  });

  group('pruneOrphanSamplings', () {
    test('removes samplings whose field is gone and reports how many',
        () async {
      await db.saveField(field('a'));
      await db.saveSampling(sampling('s1', 'a'));
      await db.saveSampling(sampling('s2', 'ghost'));

      final removed = await db.pruneOrphanSamplings();

      expect(removed, 1);
      expect(db.getSamplings().map((s) => s.id), ['s1']);
    });
  });
}
