import 'dart:io';

import 'package:eros_n/component/models/tag.dart';
import 'package:eros_n/store/db/db_store.dart';
import 'package:eros_n/store/db/entity/gallery_history.dart';
import 'package:eros_n/store/db/entity/nh_tag.dart';
import 'package:eros_n/store/db/entity/tag_translate.dart';
import 'package:eros_n/utils/eros_utils.dart';
import 'package:eros_n/utils/logger.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:path_provider/path_provider.dart';

/// ffastdb-backed implementation of DbStore for HarmonyOS.
/// Replaces ObjectBoxHelper which relies on native C++ and cannot run on OHOS.
class FfastDbStore implements DbStore {
  late FastDB _db;

  @override
  Future<void> init({String? path}) async {
    final dir = path ?? await _resolveDbPath();
    final dbFile = '$dir/eros_n.db';
    _db = FastDB(IoStorageStrategy(dbFile));
    await _db.open();
  }

  Future<String> _resolveDbPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } catch (_) {
      // Fallback for HarmonyOS if path_provider_harmonyos is not yet wired.
      return '/data/storage/el2/base/haps/entry/files';
    }
  }

  @override
  void close() => _db.close();

  // ---------------------------------------------------------------------------
  // GalleryHistory
  // ---------------------------------------------------------------------------

  static const _historyCol = 'gallery_history';

  @override
  List<GalleryHistory> getAllHistory() {
    // ffastdb is async; callers expecting sync results get a snapshot from cache.
    // This is a temporary shim — sync callers should be migrated to async over time.
    throw UnimplementedError(
      'getAllHistory: use getAllHistoryAsync on HarmonyOS',
    );
  }

  Future<List<GalleryHistory>> getAllHistoryAsync() async {
    final all = await _db.getAll(collection: _historyCol);
    return all
        .map(_mapToHistory)
        .toList()
      ..sort((a, b) => (b.lastReadTime ?? 0).compareTo(a.lastReadTime ?? 0));
  }

  @override
  Future<void> addHistory(GalleryHistory h) async {
    final existing = await _db.query(collection: _historyCol)
        .where('gid').equals(h.gid)
        .find();
    final doc = _historyToMap(h);
    if (existing.isNotEmpty) {
      await _db.update(existing.first['_id'] as String, doc,
          collection: _historyCol);
    } else {
      await _db.insert(doc, collection: _historyCol);
    }
  }

  @override
  Future<void> removeHistory(int? gid) async {
    if (gid == null) return;
    final existing = await _db.query(collection: _historyCol)
        .where('gid').equals(gid)
        .find();
    for (final doc in existing) {
      await _db.delete(doc['_id'] as String, collection: _historyCol);
    }
  }

  @override
  Future<void> clearHistory() async {
    final all = await _db.getAll(collection: _historyCol);
    for (final doc in all) {
      await _db.delete(doc['_id'] as String, collection: _historyCol);
    }
  }

  // ---------------------------------------------------------------------------
  // TagTranslate
  // ---------------------------------------------------------------------------

  static const _tagTranslateCol = 'tag_translate';

  @override
  Future<void> putAllTagTranslate(List<TagTranslate> tagTranslates) async {
    for (final t in tagTranslates) {
      await putTagTranslate(t);
    }
  }

  @override
  Future<void> putTagTranslate(TagTranslate t) async {
    final existing = await _db.query(collection: _tagTranslateCol)
        .where('name').equals(t.name)
        .and('namespace').equals(t.namespace)
        .find();
    final doc = _tagTranslateToMap(t);
    if (existing.isNotEmpty) {
      await _db.update(existing.first['_id'] as String, doc,
          collection: _tagTranslateCol);
    } else {
      await _db.insert(doc, collection: _tagTranslateCol);
    }
  }

  @override
  Future<void> deleteAllTagTranslate() async {
    final all = await _db.getAll(collection: _tagTranslateCol);
    for (final doc in all) {
      await _db.delete(doc['_id'] as String, collection: _tagTranslateCol);
    }
  }

  @override
  Future<List<String>> findAllTagNamespace() async {
    final all = await _db.getAll(collection: _tagTranslateCol);
    return all.map((d) => d['namespace'] as String).toSet().toList();
  }

  @override
  TagTranslate? findTagTranslate(String name, {String? namespace}) {
    throw UnimplementedError(
      'findTagTranslate: use findTagTranslateAsync on HarmonyOS',
    );
  }

  @override
  Future<TagTranslate?> findTagTranslateAsync(
    String name, {
    String? namespace,
  }) async {
    if (name.contains('|')) {
      name = name.split('|').first.trim();
    }
    var q = _db.query(collection: _tagTranslateCol).where('name').equals(name);
    if (namespace != null && namespace.isNotEmpty) {
      q = q.and('namespace').equals(namespace);
    } else {
      q = q.and('namespace').notEquals('rows');
    }
    final results = await q.find();
    return results.isEmpty ? null : _mapToTagTranslate(results.last);
  }

  @override
  Future<List<TagTranslate>> findTagTranslateContains(
    String text,
    int limit,
  ) async {
    final all = await _db.getAll(collection: _tagTranslateCol);
    final lower = text.toLowerCase();
    final results = all
        .where((d) =>
            d['namespace'] != 'rows' &&
            ((d['name'] as String?)?.toLowerCase().contains(lower) == true ||
                (d['translateName'] as String?)
                        ?.toLowerCase()
                        .contains(lower) ==
                    true))
        .map(_mapToTagTranslate)
        .toList()
      ..sort((a, b) => b.lastUseTime.compareTo(a.lastUseTime));
    logger.d('findTagTranslateContains result.len ${results.length}');
    return results.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // NhTag
  // ---------------------------------------------------------------------------

  static const _nhTagCol = 'nh_tag';

  @override
  Future<void> putAllNhTag(List<NhTag> tags) async {
    for (final t in tags) {
      await putNhTag(t);
    }
  }

  @override
  Future<void> putNhTag(NhTag tag) async {
    final existing = await _db.query(collection: _nhTagCol)
        .where('id').equals(tag.id)
        .find();
    final doc = _nhTagToMap(tag);
    if (existing.isNotEmpty) {
      await _db.update(existing.first['_id'] as String, doc,
          collection: _nhTagCol);
    } else {
      await _db.insert(doc, collection: _nhTagCol);
    }
  }

  @override
  NhTag? findNhTag(int? id) {
    throw UnimplementedError('findNhTag: use findNhTagAsync on HarmonyOS');
  }

  @override
  Future<NhTag?> findNhTagAsync(int? id) async {
    if (id == null) return null;
    final results = await _db.query(collection: _nhTagCol)
        .where('id').equals(id)
        .find();
    return results.isEmpty ? null : _mapToNhTag(results.first);
  }

  @override
  Future<List<NhTag>> getAllNhTag() async {
    final all = await _db.getAll(collection: _nhTagCol);
    return all.map(_mapToNhTag).toList();
  }

  @override
  Future<List<NhTag>> findNhTagContains(String text, int limit) async {
    final all = await _db.getAll(collection: _nhTagCol);
    final lower = text.toLowerCase();
    final results = all
        .where((d) =>
            (d['name'] as String?)?.toLowerCase().contains(lower) == true ||
            (d['translateName'] as String?)?.toLowerCase().contains(lower) ==
                true)
        .map(_mapToNhTag)
        .toList()
      ..sort((a, b) => b.lastUseTime.compareTo(a.lastUseTime));
    logger.t('findNhTagContains result.len ${results.length}');
    return results.take(limit).toList();
  }

  @override
  Future<void> updateNhTagTime(int nhTagId) async {
    final existing = await _db.query(collection: _nhTagCol)
        .where('id').equals(nhTagId)
        .find();
    if (existing.isEmpty) return;
    final doc = Map<String, dynamic>.from(existing.first)
      ..['lastUseTime'] = DateTime.now().millisecondsSinceEpoch;
    await _db.update(existing.first['_id'] as String, doc,
        collection: _nhTagCol);
  }

  @override
  Future<void> learnNhTags(List<Tag> tags) async {
    if (tags.isEmpty) return;
    final candidates = tags
        .where((t) => t.id != null && t.id != 0 && (t.name ?? '').isNotEmpty)
        .toList();
    if (candidates.isEmpty) return;

    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < candidates.length; i++) {
      final tag = candidates[i];
      final name = tag.name!.trim();
      if (name.isEmpty) continue;

      final type = tag.type == null || tag.type!.isEmpty
          ? null
          : singularizeTagType(tag.type!);

      final existing = await findNhTagAsync(tag.id);
      var translateName = tag.translatedName;
      if (translateName == null || translateName.isEmpty) {
        translateName = existing?.translateName;
      }
      if ((translateName == null || translateName.isEmpty) && type != null) {
        final ns = (type == 'tag' || type == 'category') ? null : type;
        translateName = (await findTagTranslateAsync(name, namespace: ns))
            ?.translateNameNotMD;
        if (i % 4 == 3) await Future<void>.delayed(Duration.zero);
      }

      await putNhTag(NhTag(
        id: tag.id!,
        name: name,
        type: type ?? existing?.type,
        count: tag.count ?? existing?.count,
        translateName: translateName,
        lastUseTime: existing?.lastUseTime ?? 0,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Mapping helpers
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _historyToMap(GalleryHistory h) => {
        'gid': h.gid,
        'mediaId': h.mediaId,
        'csrfToken': h.csrfToken,
        'title': h.title,
        'japaneseTitle': h.japaneseTitle,
        'url': h.url,
        'thumbUrl': h.thumbUrl,
        'coverImgHeight': h.coverImgHeight,
        'coverImgWidth': h.coverImgWidth,
        'lastReadTime': h.lastReadTime,
      };

  static GalleryHistory _mapToHistory(Map<String, dynamic> d) => GalleryHistory(
        gid: (d['gid'] as num).toInt(),
        mediaId: d['mediaId'] as String?,
        csrfToken: d['csrfToken'] as String?,
        title: d['title'] as String?,
        japaneseTitle: d['japaneseTitle'] as String?,
        url: d['url'] as String?,
        thumbUrl: d['thumbUrl'] as String?,
        coverImgHeight: (d['coverImgHeight'] as num?)?.toInt(),
        coverImgWidth: (d['coverImgWidth'] as num?)?.toInt(),
        lastReadTime: (d['lastReadTime'] as num?)?.toInt(),
      );

  static Map<String, dynamic> _tagTranslateToMap(TagTranslate t) => {
        'id': t.id,
        'namespace': t.namespace,
        'name': t.name,
        'translateName': t.translateName,
        'intro': t.intro,
        'links': t.links,
        'lastUseTime': t.lastUseTime,
      };

  static TagTranslate _mapToTagTranslate(Map<String, dynamic> d) =>
      TagTranslate(
        id: (d['id'] as num?)?.toInt() ?? 0,
        namespace: d['namespace'] as String,
        name: d['name'] as String,
        translateName: d['translateName'] as String?,
        intro: d['intro'] as String?,
        links: d['links'] as String?,
        lastUseTime: (d['lastUseTime'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _nhTagToMap(NhTag t) => {
        'id': t.id,
        'name': t.name,
        'type': t.type,
        'count': t.count,
        'translateName': t.translateName,
        'lastUseTime': t.lastUseTime,
      };

  static NhTag _mapToNhTag(Map<String, dynamic> d) => NhTag(
        id: (d['id'] as num).toInt(),
        name: d['name'] as String?,
        type: d['type'] as String?,
        count: (d['count'] as num?)?.toInt(),
        translateName: d['translateName'] as String?,
        lastUseTime: (d['lastUseTime'] as num?)?.toInt() ?? 0,
      );
}
