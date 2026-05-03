import 'dart:io';
import 'dart:math';

import 'package:eros_n/store/db/entity/nh_tag.dart';
import 'package:eros_n/store/db/sqlite_db_store.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tmpDir() {
  return Directory(
    '${Directory.systemTemp.path}/sqlite_test_${Random().nextInt(999999)}',
  );
}

void main() {
  late SqliteDbStore store;
  late Directory dir;

  setUp(() async {
    dir = _tmpDir();
    dir.createSync(recursive: true);
    store = SqliteDbStore();
    await store.init(path: dir.path);
  });

  tearDown(() {
    store.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  group('NhTag CRUD', () {
    test('findNhTagAsync returns null when store is empty', () async {
      expect(await store.findNhTagAsync(999), isNull);
    });

    test('putNhTag persists a tag and findNhTagAsync retrieves it', () async {
      final tag = NhTag(id: 1, name: 'doujinshi', type: 'category', count: 100);
      await store.putNhTag(tag);
      final found = await store.findNhTagAsync(1);
      expect(found, isNotNull);
      expect(found!.name, 'doujinshi');
      expect(found.type, 'category');
    });

    test('putAllNhTag persists multiple tags', () async {
      final tags = List.generate(
        5,
        (i) => NhTag(id: i + 1, name: 'tag$i', type: 'parody'),
      );
      await store.putAllNhTag(tags);
      final all = await store.getAllNhTag();
      expect(all.length, 5);
    });

    test('getAllNhTag returns all stored tags', () async {
      await store.putNhTag(NhTag(id: 10, name: 'alpha'));
      await store.putNhTag(NhTag(id: 20, name: 'beta'));
      final all = await store.getAllNhTag();
      expect(all.map((t) => t.id), containsAll([10, 20]));
    });

    test('findNhTagContains matches by name', () async {
      await store.putNhTag(NhTag(id: 1, name: 'full color'));
      await store.putNhTag(NhTag(id: 2, name: 'glasses'));
      final results = await store.findNhTagContains('color', 10);
      expect(results.length, 1);
      expect(results.first.name, 'full color');
    });

    test('findNhTagContains matches by translateName', () async {
      await store.putNhTag(NhTag(id: 3, name: 'glasses', translateName: '眼鏡'));
      await store.putNhTag(
        NhTag(id: 4, name: 'school uniform', translateName: '制服'),
      );
      final results = await store.findNhTagContains('眼', 10);
      expect(results.length, 1);
      expect(results.first.id, 3);
    });

    test('updateNhTagTime updates lastUseTime', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await store.putNhTag(NhTag(id: 5, name: 'test', lastUseTime: 0));
      await store.updateNhTagTime(5);
      final updated = await store.findNhTagAsync(5);
      expect(updated!.lastUseTime, greaterThanOrEqualTo(before));
    });

    test('updateNhTagTime is no-op for non-existent id', () async {
      await store.updateNhTagTime(9999);
    });
  });
}
