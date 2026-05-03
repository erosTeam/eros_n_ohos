import 'dart:io';
import 'dart:math';

import 'package:eros_n/store/db/entity/tag_translate.dart';
import 'package:eros_n/store/db/sqlite_db_store.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _tmpDir() {
  return Directory(
    '${Directory.systemTemp.path}/sqlite_test_${Random().nextInt(999999)}',
  );
}

TagTranslate _makeTag({
  required String name,
  required String namespace,
  String? translateName,
  int lastUseTime = 0,
}) => TagTranslate(
  name: name,
  namespace: namespace,
  translateName: translateName,
  lastUseTime: lastUseTime,
);

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

  group('TagTranslate CRUD', () {
    test('findTagTranslateAsync returns null when store is empty', () async {
      expect(await store.findTagTranslateAsync('nonexistent'), isNull);
    });

    test('putAllTagTranslate persists multiple tags', () async {
      final tags = [
        _makeTag(name: 'full color', namespace: 'tag', translateName: '全彩'),
        _makeTag(name: 'glasses', namespace: 'tag', translateName: '眼鏡'),
        _makeTag(name: 'naruto', namespace: 'parody', translateName: '火影忍者'),
      ];
      await store.putAllTagTranslate(tags);
      final namespaces = await store.findAllTagNamespace();
      expect(namespaces, containsAll(['tag', 'parody']));
    });

    test('findTagTranslateAsync finds by name and namespace', () async {
      await store.putAllTagTranslate([
        _makeTag(name: 'glasses', namespace: 'tag', translateName: '眼鏡'),
      ]);
      final result = await store.findTagTranslateAsync(
        'glasses',
        namespace: 'tag',
      );
      expect(result, isNotNull);
      expect(result!.translateName, '眼鏡');
    });

    test(
      'findTagTranslateAsync excludes rows namespace when no namespace given',
      () async {
        await store.putAllTagTranslate([
          _makeTag(name: 'glasses', namespace: 'tag'),
          _makeTag(name: 'glasses', namespace: 'rows'),
        ]);
        final result = await store.findTagTranslateAsync('glasses');
        expect(result, isNotNull);
        expect(result!.namespace, isNot('rows'));
      },
    );

    test(
      'putAllTagTranslate upserts by name+namespace composite key',
      () async {
        await store.putAllTagTranslate([
          _makeTag(
            name: 'glasses',
            namespace: 'tag',
            translateName: 'Original',
          ),
        ]);
        await store.putAllTagTranslate([
          _makeTag(name: 'glasses', namespace: 'tag', translateName: 'Updated'),
        ]);
        final result = await store.findTagTranslateAsync(
          'glasses',
          namespace: 'tag',
        );
        expect(result!.translateName, 'Updated');
        final all = await store.findTagTranslateContains('glasses', 10);
        expect(all.length, 1);
      },
    );

    test('findTagTranslateContains matches by name', () async {
      await store.putAllTagTranslate([
        _makeTag(name: 'full color', namespace: 'tag'),
        _makeTag(name: 'glasses', namespace: 'tag'),
      ]);
      final results = await store.findTagTranslateContains('color', 10);
      expect(results.length, 1);
      expect(results.first.name, 'full color');
    });

    test('findTagTranslateContains matches by translateName', () async {
      await store.putAllTagTranslate([
        _makeTag(name: 'full color', namespace: 'tag', translateName: '全彩'),
        _makeTag(name: 'glasses', namespace: 'tag', translateName: '眼鏡'),
      ]);
      final results = await store.findTagTranslateContains('全', 10);
      expect(results.length, 1);
      expect(results.first.name, 'full color');
    });

    test('findTagTranslateContains excludes rows namespace', () async {
      await store.putAllTagTranslate([
        _makeTag(name: 'test', namespace: 'tag'),
        _makeTag(name: 'test', namespace: 'rows'),
      ]);
      final results = await store.findTagTranslateContains('test', 10);
      expect(results.every((t) => t.namespace != 'rows'), isTrue);
    });

    test('findTagTranslateContains respects limit', () async {
      final tags = List.generate(
        10,
        (i) => _makeTag(name: 'tag$i', namespace: 'tag'),
      );
      await store.putAllTagTranslate(tags);
      final results = await store.findTagTranslateContains('tag', 3);
      expect(results.length, lessThanOrEqualTo(3));
    });

    test('deleteAllTagTranslate clears all records', () async {
      await store.putAllTagTranslate([
        _makeTag(name: 'a', namespace: 'tag'),
        _makeTag(name: 'b', namespace: 'parody'),
      ]);
      await store.deleteAllTagTranslate();
      final results = await store.findTagTranslateContains('', 100);
      expect(results, isEmpty);
    });

    test('findAllTagNamespace returns distinct namespaces', () async {
      await store.putAllTagTranslate([
        _makeTag(name: 'a', namespace: 'tag'),
        _makeTag(name: 'b', namespace: 'tag'),
        _makeTag(name: 'c', namespace: 'parody'),
      ]);
      final namespaces = await store.findAllTagNamespace();
      expect(namespaces.toSet(), {'tag', 'parody'});
    });

    test('translateNameNotMD strips markdown image syntax', () {
      final t = _makeTag(
        name: 'test',
        namespace: 'tag',
        translateName: '![img](http://example.com/img.png)suffix',
      );
      expect(t.translateNameNotMD, 'suffix');
    });
  });
}
