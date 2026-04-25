import 'package:eros_n/component/models/tag.dart';
import 'package:eros_n/store/db/db_store.dart';
import 'package:eros_n/store/db/entity/gallery_history.dart';
import 'package:eros_n/store/db/entity/nh_tag.dart';
import 'package:eros_n/store/db/entity/tag_translate.dart';
import 'package:eros_n/utils/eros_utils.dart';
import 'package:eros_n/utils/logger.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb/src/storage/io/io_storage_strategy.dart';
import 'package:path_provider/path_provider.dart';

/// ffastdb-backed DbStore for HarmonyOS.
/// Uses three separate FastDB instances (one per entity type) since ffastdb 0.0.1
/// has no multi-collection support.
class FfastDbStore implements DbStore {
  late FastDB _historyDb;
  late FastDB _tagTranslateDb;
  late FastDB _nhTagDb;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  @override
  Future<void> init({String? path}) async {
    final dir = path ?? await _resolveDbPath();

    _historyDb = FastDB(IoStorageStrategy('$dir/gallery_history.db'));
    _historyDb.addIndex('gid');
    await _historyDb.open();

    _tagTranslateDb = FastDB(IoStorageStrategy('$dir/tag_translate.db'));
    _tagTranslateDb.addIndex('name');
    _tagTranslateDb.addIndex('namespace');
    await _tagTranslateDb.open();

    _nhTagDb = FastDB(IoStorageStrategy('$dir/nh_tag.db'));
    _nhTagDb.addIndex('id');
    _nhTagDb.addIndex('name');
    _nhTagDb.addIndex('translateName');
    await _nhTagDb.open();

    _isInitialized = true;
  }

  Future<String> _resolveDbPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } catch (_) {
      // Fallback hardcoded path for HarmonyOS when path_provider isn't wired.
      return '/data/storage/el2/base/haps/entry/files';
    }
  }

  @override
  void close() {
    _historyDb.close();
    _tagTranslateDb.close();
    _nhTagDb.close();
  }

  // ---------------------------------------------------------------------------
  // GalleryHistory — use gid as integer primary key via put()
  // ---------------------------------------------------------------------------

  @override
  List<GalleryHistory> getAllHistory() {
    // Sync not supported — callers should migrate to getAllHistoryAsync().
    // Returns empty list to avoid crashes on HarmonyOS.
    return [];
  }

  Future<List<GalleryHistory>> getAllHistoryAsync() async {
    final all = await _historyDb.getAll();
    return (all as List)
        .cast<Map<String, dynamic>>()
        .map(_mapToHistory)
        .toList()
      ..sort((a, b) => (b.lastReadTime ?? 0).compareTo(a.lastReadTime ?? 0));
  }

  @override
  Future<void> addHistory(GalleryHistory h) async {
    await _historyDb.put(h.gid, _historyToMap(h));
  }

  @override
  Future<void> removeHistory(int? gid) async {
    if (gid == null) return;
    await _historyDb.delete(gid);
  }

  @override
  Future<void> clearHistory() async {
    final all = await _historyDb.getAll();
    for (final doc in (all as List).cast<Map<String, dynamic>>()) {
      final gid = (doc['gid'] as num?)?.toInt();
      if (gid != null) await _historyDb.delete(gid);
    }
  }

  // ---------------------------------------------------------------------------
  // TagTranslate — use auto-assigned int ID, upsert by (name, namespace)
  // ---------------------------------------------------------------------------

  @override
  Future<void> putAllTagTranslate(List<TagTranslate> tagTranslates) async {
    for (final t in tagTranslates) {
      await putTagTranslate(t);
    }
  }

  @override
  Future<void> putTagTranslate(TagTranslate t) async {
    final existing = await _tagTranslateDb.find(
      (q) => q.where('name').equals(t.name).and('namespace').equals(t.namespace).findIds(),
    );
    final doc = _tagTranslateToMap(t);
    if (existing.isNotEmpty) {
      // Get the internal ID from the stored doc to update
      final stored = existing.first as Map<String, dynamic>;
      final intId = stored['_ffdb_id'] as int?;
      if (intId != null) {
        await _tagTranslateDb.update(intId, doc);
        return;
      }
    }
    await _tagTranslateDb.insert(doc);
  }

  @override
  Future<void> deleteAllTagTranslate() async {
    final all = await _tagTranslateDb.getAll();
    for (final doc in (all as List).cast<Map<String, dynamic>>()) {
      final id = doc['_ffdb_id'] as int?;
      if (id != null) await _tagTranslateDb.delete(id);
    }
  }

  @override
  Future<List<String>> findAllTagNamespace() async {
    final all = await _tagTranslateDb.getAll();
    return (all as List)
        .cast<Map<String, dynamic>>()
        .map((d) => d['namespace'] as String)
        .toSet()
        .toList();
  }

  @override
  TagTranslate? findTagTranslate(String name, {String? namespace}) {
    // Sync not supported on HarmonyOS — returns null (tags won't be translated
    // during parsing). Use findTagTranslateAsync() where async is possible.
    return null;
  }

  @override
  Future<TagTranslate?> findTagTranslateAsync(
    String name, {
    String? namespace,
  }) async {
    if (name.contains('|')) {
      name = name.split('|').first.trim();
    }
    final results = await _tagTranslateDb.find((q) {
      var builder = q.where('name').equals(name);
      if (namespace != null && namespace.isNotEmpty) {
        builder = builder.and('namespace').equals(namespace);
      }
      return builder.findIds();
    });
    final filtered = (results as List)
        .cast<Map<String, dynamic>>()
        .where((d) =>
            namespace == null ||
            namespace.isEmpty ||
            d['namespace'] != 'rows')
        .toList();
    return filtered.isEmpty ? null : _mapToTagTranslate(filtered.last);
  }

  @override
  Future<List<TagTranslate>> findTagTranslateContains(
    String text,
    int limit,
  ) async {
    if (!_isInitialized) return const [];
    final all = await _tagTranslateDb.getAll();
    final lower = text.toLowerCase();
    final results = (all as List)
        .cast<Map<String, dynamic>>()
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
  // NhTag — use nhTag.id as integer primary key via put()
  // ---------------------------------------------------------------------------

  @override
  Future<void> putAllNhTag(List<NhTag> tags) async {
    for (final t in tags) {
      await putNhTag(t);
    }
  }

  @override
  Future<void> putNhTag(NhTag tag) async {
    if (!_isInitialized) return;
    await _nhTagDb.put(tag.id, _nhTagToMap(tag));
  }

  @override
  NhTag? findNhTag(int? id) {
    // Sync not supported — returns null on HarmonyOS.
    return null;
  }

  @override
  Future<NhTag?> findNhTagAsync(int? id) async {
    if (id == null) return null;
    final doc = await _nhTagDb.findById(id);
    if (doc == null) return null;
    return _mapToNhTag(doc as Map<String, dynamic>);
  }

  @override
  Future<List<NhTag>> getAllNhTag() async {
    final all = await _nhTagDb.getAll();
    return (all as List).cast<Map<String, dynamic>>().map(_mapToNhTag).toList();
  }

  @override
  Future<List<NhTag>> findNhTagContains(String text, int limit) async {
    if (!_isInitialized) return const [];
    final all = await _nhTagDb.getAll();
    final lower = text.toLowerCase();
    final results = (all as List)
        .cast<Map<String, dynamic>>()
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
    final doc = await _nhTagDb.findById(nhTagId);
    if (doc == null) return;
    final updated = Map<String, dynamic>.from(doc as Map)
      ..['lastUseTime'] = DateTime.now().millisecondsSinceEpoch;
    await _nhTagDb.put(nhTagId, updated);
  }

  @override
  Future<void> learnNhTags(List<Tag> tags) async {
    if (!_isInitialized) return;
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
        translateName =
            (await findTagTranslateAsync(name, namespace: ns))?.translateNameNotMD;
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

  static GalleryHistory _mapToHistory(Map<String, dynamic> d) =>
      GalleryHistory(
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
