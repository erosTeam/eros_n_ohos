import 'dart:async';
import 'dart:io';

import 'package:eros_n/common/const/const.dart';
import 'package:eros_n/common/global.dart';
import 'package:eros_n/common/provider/settings_provider.dart';
import 'package:eros_n/component/models/gallery.dart';
import 'package:eros_n/network/request.dart';
import 'package:eros_n/pages/gallery/gallery_provider.dart';
import 'package:eros_n/store/db/entity/download_task.dart';
import 'package:eros_n/utils/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'download_provider.g.dart';

@Riverpod(keepAlive: true)
class DownloadNotifier extends _$DownloadNotifier {
  final _pendingQueue = <int>[];
  final _activeGids = <int>{};

  @override
  Map<int, DownloadTask> build() {
    _loadFromDb();
    return {};
  }

  Future<void> _loadFromDb() async {
    final tasks = await objectBoxHelper.getAllDownloadTasks();
    final map = <int, DownloadTask>{};
    for (final t in tasks) {
      // Tasks that were mid-download when app was killed are treated as paused.
      if (t.status == DownloadStatus.downloading) {
        await objectBoxHelper.updateDownloadProgress(
            t.gid, t.downloadedPages, DownloadStatus.paused);
        map[t.gid] = t.copyWith(status: DownloadStatus.paused);
      } else {
        map[t.gid] = t;
      }
    }
    state = map;
  }

  Future<void> addDownload(Gallery gallery) async {
    if (state.containsKey(gallery.gid)) return;

    final settings = ref.read(settingsProvider);
    final savedDir =
        await Global.resolveDownloadsPath(settings.customDownloadPath);
    final dir = '$savedDir/${gallery.gid}';

    final pages = gallery.images.pages;
    final pageExts = pages.map((p) {
      return NHConst.extMap[p.type] ?? 'jpg';
    }).toList();

    final task = DownloadTask(
      gid: gallery.gid,
      title: gallery.title.prettyTitle ??
          gallery.title.englishTitle ??
          gallery.gid.toString(),
      thumbUrl: gallery.thumbUrl ?? '',
      mediaId: gallery.mediaId ?? '',
      totalPages: pages.isNotEmpty ? pages.length : (gallery.numPages ?? 0),
      savedDir: dir,
    );
    task.pageExts = pageExts;

    await objectBoxHelper.upsertDownloadTask(task);
    state = {...state, task.gid: task};

    _pendingQueue.add(task.gid);
    _processQueue();
  }

  Future<void> pauseDownload(int gid) async {
    final task = state[gid];
    if (task == null) return;
    _pendingQueue.remove(gid);
    _activeGids.remove(gid);
    await objectBoxHelper.updateDownloadProgress(
        gid, task.downloadedPages, DownloadStatus.paused);
    state = {...state, gid: task.copyWith(status: DownloadStatus.paused)};
  }

  Future<void> resumeDownload(int gid) async {
    final task = state[gid];
    if (task == null) return;
    if (_pendingQueue.contains(gid) || _activeGids.contains(gid)) return;

    await objectBoxHelper.updateDownloadProgress(
        gid, task.downloadedPages, DownloadStatus.pending);
    state = {...state, gid: task.copyWith(status: DownloadStatus.pending)};

    _pendingQueue.add(gid);
    _processQueue();
  }

  Future<void> deleteDownload(int gid) async {
    _pendingQueue.remove(gid);
    _activeGids.remove(gid);
    final task = state[gid];
    if (task != null) {
      try {
        final dir = Directory(task.savedDir);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      } catch (e) {
        logger.e('deleteDownload dir error: $e');
      }
    }
    await objectBoxHelper.deleteDownloadTask(gid);
    final newState = Map<int, DownloadTask>.from(state)..remove(gid);
    state = newState;
  }

  bool isDownloaded(int gid) =>
      state[gid]?.status == DownloadStatus.completed;

  void _processQueue() {
    final maxGalleries =
        ref.read(settingsProvider).maxConcurrentGalleries;
    while (_activeGids.length < maxGalleries && _pendingQueue.isNotEmpty) {
      final gid = _pendingQueue.removeAt(0);
      if (state.containsKey(gid) &&
          state[gid]!.status != DownloadStatus.completed) {
        _activeGids.add(gid);
        _downloadGallery(gid);
      }
    }
  }

  Future<void> _downloadGallery(int gid) async {
    final task = state[gid];
    if (task == null) {
      _activeGids.remove(gid);
      _processQueue();
      return;
    }

    task.status = DownloadStatus.downloading;
    await objectBoxHelper.updateDownloadProgress(
        gid, task.downloadedPages, DownloadStatus.downloading);
    state = {...state, gid: task.copyWith(status: DownloadStatus.downloading)};

    try {
      await Directory(task.savedDir).create(recursive: true);

      final maxPages = ref.read(settingsProvider).maxConcurrentPages;
      final total = task.totalPages;

      // Build list of pages that still need downloading (resume support).
      final pending = <int>[];
      for (var i = 0; i < total; i++) {
        if (task.pageExts.isEmpty || i >= task.pageExts.length) continue;
        final localPath =
            '${task.savedDir}/${i + 1}.${task.pageExts[i]}';
        if (!File(localPath).existsSync()) {
          pending.add(i);
        }
      }

      // Process in batches of maxPages concurrent downloads.
      for (var start = 0; start < pending.length; start += maxPages) {
        // Check if paused/deleted mid-download.
        final current = state[gid];
        if (current == null || current.status != DownloadStatus.downloading) {
          _activeGids.remove(gid);
          return;
        }

        final end = (start + maxPages).clamp(0, pending.length);
        final batch = pending.sublist(start, end);
        await Future.wait(
          batch.map((idx) => _downloadPage(gid, idx)),
          eagerError: false,
        );

        // Update progress after each batch.
        final taskNow = state[gid];
        if (taskNow != null) {
          final downloaded = _countDownloaded(taskNow);
          await objectBoxHelper.updateDownloadProgress(
              gid, downloaded, DownloadStatus.downloading);
          state = {
            ...state,
            gid: taskNow.copyWith(downloadedPages: downloaded),
          };
        }
      }

      // Final check: count actual files.
      final taskDone = state[gid];
      if (taskDone == null) {
        _activeGids.remove(gid);
        _processQueue();
        return;
      }
      final downloaded = _countDownloaded(taskDone);
      final newStatus = downloaded >= total
          ? DownloadStatus.completed
          : DownloadStatus.failed;

      await objectBoxHelper.updateDownloadProgress(gid, downloaded, newStatus);
      state = {
        ...state,
        gid: taskDone.copyWith(downloadedPages: downloaded, status: newStatus),
      };
    } catch (e) {
      logger.e('_downloadGallery $gid error: $e');
      final taskErr = state[gid];
      if (taskErr != null) {
        await objectBoxHelper.updateDownloadProgress(
            gid, taskErr.downloadedPages, DownloadStatus.failed);
        state = {
          ...state,
          gid: taskErr.copyWith(status: DownloadStatus.failed),
        };
      }
    } finally {
      _activeGids.remove(gid);
      _processQueue();
    }
  }

  int _countDownloaded(DownloadTask task) {
    var count = 0;
    for (var i = 0; i < task.totalPages; i++) {
      if (i < task.pageExts.length) {
        final path = '${task.savedDir}/${i + 1}.${task.pageExts[i]}';
        if (File(path).existsSync()) count++;
      }
    }
    return count;
  }

  Future<void> _downloadPage(int gid, int index) async {
    final task = state[gid];
    if (task == null || index >= task.pageExts.length) return;

    final ext = task.pageExts[index];
    final localPath = '${task.savedDir}/${index + 1}.$ext';
    if (File(localPath).existsSync()) return;

    final url = getGalleryImageUrl(task.mediaId, index, ext);
    try {
      await nhDownload(url: url, savePath: localPath);
    } catch (e) {
      logger.e('_downloadPage gid=$gid index=$index error: $e');
    }
  }
}
