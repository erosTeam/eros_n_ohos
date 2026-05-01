import 'package:eros_n/component/models/tag.dart';
import 'package:eros_n/store/db/db_store.dart';
import 'package:eros_n/store/db/entity/download_task.dart';
import 'package:eros_n/store/db/entity/gallery_history.dart';
import 'package:eros_n/store/db/entity/nh_tag.dart';
import 'package:eros_n/store/db/entity/tag_translate.dart';
import 'package:eros_n/utils/eros_utils.dart';
import 'package:eros_n/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const int _kDbVersion = 4;

class SqliteDbStore implements DbStore {
  Database? _db;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('SqliteDbStore not initialized');
    }
    return db;
  }

  @override
  Future<void> init({String? path}) async {
    String dbPath;
    try {
      dbPath = path != null ? p.join(path, 'eros_n.db') : await _resolveDbPath();
    } catch (e) {
      logger.e('[SqliteDbStore] _resolveDbPath failed: $e');
      dbPath = 'eros_n.db';
    }
    logger.d('[SqliteDbStore] opening DB at: $dbPath');
    try {
      _db = await openDatabase(
        dbPath,
        version: _kDbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      _isInitialized = true;
      logger.d('[SqliteDbStore] DB opened OK, isInitialized=$_isInitialized');
    } catch (e, st) {
      logger.e('[SqliteDbStore] openDatabase failed: $e\n$st');
      rethrow;
    }
  }

  Future<String> _resolveDbPath() async {
    // sqflite on HarmonyOS uses getDatabasesPath() internally for relative paths.
    // Using getApplicationSupportDirectory() gives a path the native RDB API
    // cannot resolve correctly. Fall back to just the filename so sqflite
    // resolves it via getDatabasesPath() internally.
    try {
      final dbsDir = await getDatabasesPath();
      logger.d('[SqliteDbStore] getDatabasesPath=$dbsDir');
      return p.join(dbsDir, 'eros_n.db');
    } catch (_) {
      return 'eros_n.db';
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE gallery_history (
        gid INTEGER PRIMARY KEY,
        mediaId TEXT,
        csrfToken TEXT,
        title TEXT,
        japaneseTitle TEXT,
        url TEXT,
        thumbUrl TEXT,
        coverImgHeight INTEGER,
        coverImgWidth INTEGER,
        lastReadTime INTEGER,
        lastReadIndex INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE tag_translate (
        id INTEGER,
        namespace TEXT NOT NULL,
        name TEXT NOT NULL,
        translateName TEXT,
        intro TEXT,
        links TEXT,
        lastUseTime INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (namespace, name)
      )
    ''');
    await db.execute('CREATE INDEX idx_tt_name ON tag_translate(name)');

    await db.execute('''
      CREATE TABLE nh_tag (
        id INTEGER PRIMARY KEY,
        name TEXT,
        type TEXT,
        count INTEGER,
        translateName TEXT,
        lastUseTime INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_nh_name ON nh_tag(name)');
    await db.execute(
      'CREATE INDEX idx_nh_translateName ON nh_tag(translateName)',
    );

    await db.execute('''
      CREATE TABLE download_task (
        gid             INTEGER PRIMARY KEY,
        title           TEXT NOT NULL DEFAULT '',
        thumbUrl        TEXT NOT NULL DEFAULT '',
        mediaId         TEXT NOT NULL DEFAULT '',
        totalPages      INTEGER NOT NULL DEFAULT 0,
        downloadedPages INTEGER NOT NULL DEFAULT 0,
        status          TEXT NOT NULL DEFAULT 'pending',
        savedDir        TEXT NOT NULL DEFAULT '',
        pageExts        TEXT NOT NULL DEFAULT '[]',
        createdAt       INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE gallery_history ADD COLUMN lastReadIndex INTEGER',
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS download_task (
          gid             INTEGER PRIMARY KEY,
          title           TEXT NOT NULL DEFAULT '',
          thumbUrl        TEXT NOT NULL DEFAULT '',
          mediaId         TEXT NOT NULL DEFAULT '',
          totalPages      INTEGER NOT NULL DEFAULT 0,
          downloadedPages INTEGER NOT NULL DEFAULT 0,
          status          TEXT NOT NULL DEFAULT 'pending',
          savedDir        TEXT NOT NULL DEFAULT '',
          pageExts        TEXT NOT NULL DEFAULT '[]'
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE download_task ADD COLUMN createdAt INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  @override
  void close() {
    _db?.close();
    _db = null;
    _isInitialized = false;
  }

  // ---------------------------------------------------------------------------
  // GalleryHistory
  // ---------------------------------------------------------------------------

  @override
  List<GalleryHistory> getAllHistory() => [];

  @override
  Future<List<GalleryHistory>> getAllHistoryAsync() async {
    final rows = await _database.query(
      'gallery_history',
      orderBy: 'lastReadTime DESC',
    );
    return rows.map(_mapToHistory).toList();
  }

  @override
  Future<void> addHistory(GalleryHistory h) async {
    // Preserve lastReadIndex from existing row if present.
    final existing = await _database.query(
      'gallery_history',
      columns: ['lastReadIndex'],
      where: 'gid = ?',
      whereArgs: [h.gid],
    );
    if (existing.isNotEmpty && h.lastReadIndex == null) {
      h.lastReadIndex = (existing.first['lastReadIndex'] as num?)?.toInt();
    }
    await _database.insert(
      'gallery_history',
      _historyToMap(h),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeHistory(int? gid) async {
    if (gid == null) {
      return;
    }
    await _database.delete(
      'gallery_history',
      where: 'gid = ?',
      whereArgs: [gid],
    );
  }

  @override
  Future<void> clearHistory() async {
    await _database.delete('gallery_history');
  }

  @override
  Future<void> updateHistoryReadIndex(int gid, int index) async {
    await _database.update(
      'gallery_history',
      {'lastReadIndex': index},
      where: 'gid = ?',
      whereArgs: [gid],
    );
  }

  // ---------------------------------------------------------------------------
  // TagTranslate
  // ---------------------------------------------------------------------------

  @override
  Future<void> putAllTagTranslate(List<TagTranslate> tagTranslates) async {
    // All operations are batched into a single platform channel call,
    // which SQLite wraps in one transaction on the native side.
    final batch = _database.batch();
    batch.delete('tag_translate');
    for (final t in tagTranslates) {
      batch.insert('tag_translate', _tagTranslateToMap(t));
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> putTagTranslate(TagTranslate t) async {
    await _database.insert(
      'tag_translate',
      _tagTranslateToMap(t),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteAllTagTranslate() async {
    await _database.delete('tag_translate');
  }

  @override
  Future<List<String>> findAllTagNamespace() async {
    final rows = await _database.rawQuery(
      'SELECT DISTINCT namespace FROM tag_translate',
    );
    return rows.map((r) => r['namespace'] as String).toList();
  }

  @override
  TagTranslate? findTagTranslate(String name, {String? namespace}) => null;

  @override
  Future<TagTranslate?> findTagTranslateAsync(
    String name, {
    String? namespace,
  }) async {
    if (name.contains('|')) {
      name = name.split('|').first.trim();
    }
    var where = "name = ? AND namespace != 'rows'";
    final args = <Object?>[name];
    if (namespace != null && namespace.isNotEmpty) {
      where += ' AND namespace = ?';
      args.add(namespace);
    }
    final rows = await _database.query(
      'tag_translate',
      where: where,
      whereArgs: args,
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _mapToTagTranslate(rows.first);
  }

  @override
  Future<List<TagTranslate>> findTagTranslateContains(
    String text,
    int limit,
  ) async {
    if (!_isInitialized) {
      return const [];
    }
    final like = '%$text%';
    final rows = await _database.query(
      'tag_translate',
      where: "namespace != 'rows' AND (name LIKE ? OR translateName LIKE ?)",
      whereArgs: [like, like],
      orderBy: 'lastUseTime DESC',
      limit: limit,
    );
    logger.d('findTagTranslateContains result.len ${rows.length}');
    return rows.map(_mapToTagTranslate).toList();
  }

  // ---------------------------------------------------------------------------
  // NhTag
  // ---------------------------------------------------------------------------

  @override
  Future<void> putAllNhTag(List<NhTag> tags) async {
    for (final t in tags) {
      await putNhTag(t);
    }
  }

  @override
  Future<void> putNhTag(NhTag tag) async {
    if (!_isInitialized) {
      return;
    }
    await _database.insert(
      'nh_tag',
      _nhTagToMap(tag),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  NhTag? findNhTag(int? id) => null;

  @override
  Future<NhTag?> findNhTagAsync(int? id) async {
    if (id == null) {
      return null;
    }
    final rows = await _database.query(
      'nh_tag',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapToNhTag(rows.first);
  }

  @override
  Future<List<NhTag>> getAllNhTag() async {
    final rows = await _database.query('nh_tag');
    return rows.map(_mapToNhTag).toList();
  }

  @override
  Future<List<NhTag>> findNhTagContains(String text, int limit) async {
    if (!_isInitialized) {
      return const [];
    }
    final like = '%$text%';
    final rows = await _database.query(
      'nh_tag',
      where: 'name LIKE ? OR translateName LIKE ?',
      whereArgs: [like, like],
      orderBy: 'lastUseTime DESC',
      limit: limit,
    );
    logger.t('findNhTagContains result.len ${rows.length}');
    return rows.map(_mapToNhTag).toList();
  }

  @override
  Future<void> updateNhTagTime(int nhTagId) async {
    await _database.update(
      'nh_tag',
      {'lastUseTime': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [nhTagId],
    );
  }

  @override
  Future<void> learnNhTags(List<Tag> tags) async {
    if (!_isInitialized) {
      return;
    }
    if (tags.isEmpty) {
      return;
    }
    final candidates = tags
        .where((t) => t.id != null && t.id != 0 && (t.name ?? '').isNotEmpty)
        .toList();
    if (candidates.isEmpty) {
      return;
    }

    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < candidates.length; i++) {
      final tag = candidates[i];
      final name = tag.name!.trim();
      if (name.isEmpty) {
        continue;
      }

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
            (await findTagTranslateAsync(name, namespace: ns))
                ?.translateNameNotMD;
        if (i % 4 == 3) {
          await Future<void>.delayed(Duration.zero);
        }
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
  // DownloadTask
  // ---------------------------------------------------------------------------

  @override
  Future<List<DownloadTask>> getAllDownloadTasks() async {
    final rows = await _database.query('download_task');
    return rows.map(DownloadTask.fromMap).toList();
  }

  @override
  Future<void> upsertDownloadTask(DownloadTask task) async {
    await _database.insert(
      'download_task',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteDownloadTask(int gid) async {
    await _database.delete(
      'download_task',
      where: 'gid = ?',
      whereArgs: [gid],
    );
  }

  @override
  Future<void> updateDownloadProgress(
    int gid,
    int downloadedPages,
    DownloadStatus status,
  ) async {
    await _database.update(
      'download_task',
      {'downloadedPages': downloadedPages, 'status': status.name},
      where: 'gid = ?',
      whereArgs: [gid],
    );
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
        'lastReadIndex': h.lastReadIndex,
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
        lastReadIndex: (d['lastReadIndex'] as num?)?.toInt(),
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
