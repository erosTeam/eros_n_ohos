import 'package:auto_route/auto_route.dart';
import 'package:eros_n/common/global.dart';
import 'package:eros_n/utils/logger.dart';
import 'package:eros_n/common/provider/download_provider.dart';
import 'package:eros_n/component/widget/adaptive_app_bar.dart';
import 'package:eros_n/component/widget/eros_cached_network_image.dart';
import 'package:eros_n/generated/l10n.dart';
import 'package:eros_n/pages/gallery/gallery_provider.dart';
import 'package:eros_n/routes/routes.dart';
import 'package:eros_n/store/db/entity/download_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

@RoutePage()
class DownloadsPage extends HookConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = isLiquidGlass(ref);
    final tasks = ref.watch(downloadProvider);
    final l = L10n.of(context);

    final searchActive = useState(false);
    final searchQuery = useState('');
    final searchController = useTextEditingController();

    bool matchesQuery(DownloadTask t) =>
        searchQuery.value.isEmpty ||
        t.title.toLowerCase().contains(searchQuery.value.toLowerCase());

    List<DownloadTask> sorted(Iterable<DownloadTask> src) =>
        src.toList()..sort((a, b) => b.gid.compareTo(a.gid));

    final downloading = sorted(tasks.values.where((t) =>
        (t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.pending) &&
        matchesQuery(t)));
    final paused = sorted(tasks.values
        .where((t) => t.status == DownloadStatus.paused && matchesQuery(t)));
    final completed = sorted(tasks.values
        .where((t) => t.status == DownloadStatus.completed && matchesQuery(t)));
    final failed = sorted(tasks.values
        .where((t) => t.status == DownloadStatus.failed && matchesQuery(t)));

    final hasResults = downloading.isNotEmpty ||
        paused.isNotEmpty ||
        completed.isNotEmpty ||
        failed.isNotEmpty;

    void activateSearch() => searchActive.value = true;

    void deactivateSearch() {
      searchActive.value = false;
      searchQuery.value = '';
      searchController.clear();
    }

    final appBar = adaptiveAppBar(
      context: context,
      ref: ref,
      automaticallyImplyLeading: !searchActive.value,
      leading: searchActive.value
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: deactivateSearch,
            )
          : null,
      title: searchActive.value
          ? TextField(
              controller: searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l.search,
                border: InputBorder.none,
              ),
              onChanged: (v) => searchQuery.value = v,
            )
          : Text(l.download_management),
      actions: searchActive.value
          ? null
          : [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: activateSearch,
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => erosRouter.push(const DownloadSettingRoute()),
              ),
              const SizedBox(width: 8),
            ],
    );

    Widget buildSection(String label, int count, List<DownloadTask> list) {
      return MultiSliver(
        pushPinnedChildren: true,
        children: [
          SliverPinnedHeader(
            child: _SectionHeader(label: label, count: count),
          ),
          _TaskList(tasks: list),
        ],
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: glass,
      appBar: appBar,
      body: tasks.isEmpty
          ? const _EmptyState()
          : !hasResults
              ? const _NoResultsState()
              : CustomScrollView(
                  slivers: [
                    if (glass)
                      SliverToBoxAdapter(
                        child: SizedBox(height: glassBodyPadding(context).top),
                      ),
                    if (downloading.isNotEmpty)
                      buildSection(
                          l.downloading, downloading.length, downloading),
                    if (paused.isNotEmpty)
                      buildSection(l.download_paused, paused.length, paused),
                    if (completed.isNotEmpty)
                      buildSection(
                          l.download_completed, completed.length, completed),
                    if (failed.isNotEmpty)
                      buildSection(l.download_failed, failed.length, failed),
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
  const _EmptyState();

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
// No search results state
// ---------------------------------------------------------------------------

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            L10n.of(context).no_result,
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
// Section header — regular widget (wrapped in SliverPinnedHeader by parent)
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
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
      statusText = l.download_progress(task.downloadedPages, task.totalPages);
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
      logger.d('openReader gid=${task.gid}');
      pushGalleryPage(task.gid);
      erosRouter.push(ReadRoute(colorScheme: Theme.of(context).colorScheme));
    }

    void openGallery() {
      logger.d('openGallery gid=${task.gid}');
      RouteUtil.goGalleryByGid(ref, task.gid);
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
              InkWell(
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
                    PopupMenuButton<String>(
                      iconSize: 28,
                      iconColor: scheme.primary,
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        if (value == 'redownload') {
                          notifier.redownloadGallery(task.gid);
                        } else if (value == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(l.download_delete_confirm_title),
                              content:
                                  Text(l.download_delete_confirm_message),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: Text(l.cancel),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  child: Text(
                                    l.delete,
                                    style:
                                        TextStyle(color: scheme.error),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            notifier.deleteDownload(task.gid);
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        if (isCompleted)
                          PopupMenuItem<String>(
                            value: 'redownload',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh,
                                    size: 18,
                                    color: scheme.primary),
                                const SizedBox(width: 8),
                                Text(l.download_redownload),
                              ],
                            ),
                          ),
                        PopupMenuItem<String>(
                          value: 'delete',
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
            ],
          ),
        ),
      ),
    );
  }
}
