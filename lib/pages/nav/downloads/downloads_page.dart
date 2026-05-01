import 'package:auto_route/auto_route.dart';
import 'package:eros_n/common/global.dart';
import 'package:eros_n/common/provider/download_provider.dart';
import 'package:eros_n/component/widget/adaptive_app_bar.dart';
import 'package:eros_n/component/widget/eros_cached_network_image.dart';
import 'package:eros_n/generated/l10n.dart';
import 'package:eros_n/pages/gallery/gallery_provider.dart';
import 'package:eros_n/routes/routes.dart';
import 'package:eros_n/store/db/entity/download_task.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = isLiquidGlass(ref);
    final tasks = ref.watch(downloadProvider);
    final l = L10n.of(context);

    List<DownloadTask> _sorted(Iterable<DownloadTask> src) =>
        src.toList()..sort((a, b) => b.gid.compareTo(a.gid));

    final downloading = _sorted(tasks.values.where((t) =>
        t.status == DownloadStatus.downloading ||
        t.status == DownloadStatus.pending));
    final paused =
        _sorted(tasks.values.where((t) => t.status == DownloadStatus.paused));
    final completed =
        _sorted(tasks.values.where((t) => t.status == DownloadStatus.completed));
    final failed =
        _sorted(tasks.values.where((t) => t.status == DownloadStatus.failed));

    return Scaffold(
      extendBodyBehindAppBar: glass,
      appBar: adaptiveAppBar(
        context: context,
        ref: ref,
        title: Text(l.download_management),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => erosRouter.push(const DownloadSettingRoute()),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: tasks.isEmpty
          ? _EmptyState()
          : CustomScrollView(
              slivers: [
                if (glass)
                  SliverToBoxAdapter(
                    child: SizedBox(height: glassBodyPadding(context).top),
                  ),
                if (downloading.isNotEmpty) ...[
                  _SectionHeader(
                      label: l.downloading, count: downloading.length),
                  _TaskList(tasks: downloading),
                ],
                if (paused.isNotEmpty) ...[
                  _SectionHeader(
                      label: l.download_paused, count: paused.length),
                  _TaskList(tasks: paused),
                ],
                if (completed.isNotEmpty) ...[
                  _SectionHeader(
                      label: l.download_completed, count: completed.length),
                  _TaskList(tasks: completed),
                ],
                if (failed.isNotEmpty) ...[
                  _SectionHeader(
                      label: l.download_failed, count: failed.length),
                  _TaskList(tasks: failed),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            L10n.of(context).no_downloads,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task list
// ---------------------------------------------------------------------------

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: _TaskCard(task: tasks[index]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Task card — thumbnail is edge-to-edge on left/top/bottom
// ---------------------------------------------------------------------------

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(downloadProvider.notifier);
    final l = L10n.of(context);

    final progress = task.totalPages > 0
        ? (task.downloadedPages / task.totalPages).clamp(0.0, 1.0)
        : 0.0;

    final isDownloading = task.status == DownloadStatus.downloading;
    final isPending = task.status == DownloadStatus.pending;
    final isPaused = task.status == DownloadStatus.paused;
    final isCompleted = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed;
    final isActive = isDownloading || isPending;

    // Status text
    final String statusText;
    if (isCompleted) {
      statusText = l.download_total_pages(task.totalPages);
    } else if (isPending) {
      statusText = l.download_pending;
    } else {
      statusText =
          l.download_progress(task.downloadedPages, task.totalPages);
    }

    // Primary action
    Widget? primaryActionIcon;
    VoidCallback? primaryAction;
    if (isDownloading) {
      primaryActionIcon = Icon(Icons.pause, size: 28, color: scheme.primary);
      primaryAction = () => notifier.pauseDownload(task.gid);
    } else if (isPaused) {
      primaryActionIcon =
          Icon(Icons.play_arrow, size: 28, color: scheme.primary);
      primaryAction = () => notifier.resumeDownload(task.gid);
    } else if (isFailed) {
      primaryActionIcon = Icon(Icons.refresh, size: 28, color: scheme.primary);
      primaryAction = () => notifier.resumeDownload(task.gid);
    }

    final String overflowLabel = isActive ? l.cancel : l.delete;

    void openReader() {
      pushGalleryPage(task.gid);
      erosRouter.push(ReadRoute(colorScheme: Theme.of(context).colorScheme));
    }

    void openGallery() {
      pushGalleryPage(task.gid);
      erosRouter.push(GalleryRoute(gid: task.gid));
      popGalleryPage();
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isCompleted ? openReader : null,
        child: SizedBox(
          height: 88,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Thumbnail — touches card edges on left/top/bottom
            GestureDetector(
              onTap: openGallery,
              child: SizedBox(
                width: 60,
                child: task.thumbUrl.isNotEmpty
                    ? ErosCachedNetworkImage(
                        imageUrl: task.thumbUrl,
                        fit: BoxFit.cover,
                      )
                    : ColoredBox(color: scheme.surfaceContainerHighest),
              ),
            ),
            // Info column
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.3),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isFailed
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                    ),
                    if (!isCompleted) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: isFailed
                              ? scheme.error
                              : isActive
                                  ? scheme.primary
                                  : scheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (primaryActionIcon != null)
                    IconButton(
                      icon: primaryActionIcon,
                      onPressed: primaryAction,
                      visualDensity: VisualDensity.compact,
                    ),
                  PopupMenuButton<bool>(
                    iconSize: 28,
                    iconColor: scheme.primary,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (_) => notifier.deleteDownload(task.gid),
                    itemBuilder: (context) => [
                      PopupMenuItem<bool>(
                        value: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isActive
                                  ? Icons.cancel_outlined
                                  : Icons.delete_outline,
                              size: 18,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              overflowLabel,
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // end action buttons Padding
          ],
        ),
      ),
    ),
  );
  }
}
