import 'dart:io';
import 'dart:math';

import 'package:eros_n/store/db/entity/gallery_history.dart';
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

  group('GalleryHistory CRUD', () {
    test('getAllHistoryAsync returns empty list initially', () async {
      expect(await store.getAllHistoryAsync(), isEmpty);
    });

    test('addHistory persists a record', () async {
      final h = GalleryHistory(
        gid: 1001,
        title: 'Test Gallery',
        lastReadTime: DateTime.now().millisecondsSinceEpoch,
      );
      await store.addHistory(h);
      final all = await store.getAllHistoryAsync();
      expect(all.length, 1);
      expect(all.first.gid, 1001);
      expect(all.first.title, 'Test Gallery');
    });

    test(
      'getAllHistoryAsync returns records sorted by lastReadTime descending',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await store.addHistory(
          GalleryHistory(gid: 1, title: 'Old', lastReadTime: now - 10000),
        );
        await store.addHistory(
          GalleryHistory(gid: 2, title: 'New', lastReadTime: now),
        );
        final all = await store.getAllHistoryAsync();
        expect(all.length, 2);
        expect(all.first.gid, 2);
        expect(all.last.gid, 1);
      },
    );

    test('addHistory upserts when gid already exists', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await store.addHistory(
        GalleryHistory(gid: 42, title: 'Original', lastReadTime: now),
      );
      await store.addHistory(
        GalleryHistory(gid: 42, title: 'Updated', lastReadTime: now + 1),
      );
      final all = await store.getAllHistoryAsync();
      expect(all.length, 1);
      expect(all.first.title, 'Updated');
    });

    test('removeHistory deletes a specific record', () async {
      await store.addHistory(GalleryHistory(gid: 10, lastReadTime: 1000));
      await store.addHistory(GalleryHistory(gid: 20, lastReadTime: 2000));
      await store.removeHistory(10);
      final all = await store.getAllHistoryAsync();
      expect(all.length, 1);
      expect(all.first.gid, 20);
    });

    test('removeHistory is no-op for null gid', () async {
      await store.addHistory(GalleryHistory(gid: 5, lastReadTime: 1000));
      await store.removeHistory(null);
      final all = await store.getAllHistoryAsync();
      expect(all.length, 1);
    });

    test('clearHistory removes all records', () async {
      await store.addHistory(GalleryHistory(gid: 1, lastReadTime: 1));
      await store.addHistory(GalleryHistory(gid: 2, lastReadTime: 2));
      await store.clearHistory();
      expect(await store.getAllHistoryAsync(), isEmpty);
    });
  });
}
