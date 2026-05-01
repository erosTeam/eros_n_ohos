import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:eros_n/common/global.dart';
import 'package:eros_n/common/provider/settings_provider.dart';
import 'package:eros_n/component/widget/adaptive_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@RoutePage()
class DownloadSettingPage extends ConsumerWidget {
  const DownloadSettingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = isLiquidGlass(ref);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      extendBodyBehindAppBar: glass,
      appBar: adaptiveAppBar(
        context: context,
        ref: ref,
        title: const Text('下载设置'),
      ),
      body: ListView(
        padding: glass ? glassBodyPadding(context) : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '并发下载',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ListTile(
            title: const Text('同时下载的画廊数量'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<int>(
                segments: [
                  for (var i = 1; i <= 5; i++)
                    ButtonSegment<int>(value: i, label: Text('$i')),
                ],
                selected: {settings.maxConcurrentGalleries},
                onSelectionChanged: (v) =>
                    notifier.setMaxConcurrentGalleries(v.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          ListTile(
            title: const Text('每画廊同时下载的页数'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<int>(
                segments: [
                  for (var i = 1; i <= 5; i++)
                    ButtonSegment<int>(value: i, label: Text('$i')),
                ],
                selected: {settings.maxConcurrentPages},
                onSelectionChanged: (v) =>
                    notifier.setMaxConcurrentPages(v.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const Divider(height: 1),
          // Download path section — only on Android / HarmonyOS
          if (!Platform.isIOS) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '下载路径',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ListTile(
              title: const Text('当前路径'),
              subtitle: Text(
                settings.customDownloadPath.isNotEmpty
                    ? settings.customDownloadPath
                    : Global.downloadsPath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  if (settings.customDownloadPath.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        notifier.setCustomDownloadPath('');
                      },
                      child: const Text('重置为默认'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
