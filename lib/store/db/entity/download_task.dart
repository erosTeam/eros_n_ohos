import 'dart:convert';

enum DownloadStatus { pending, downloading, paused, completed, failed }

class DownloadTask {
  DownloadTask({
    required this.gid,
    required this.title,
    required this.thumbUrl,
    required this.mediaId,
    required this.totalPages,
    required this.savedDir,
    this.downloadedPages = 0,
    this.status = DownloadStatus.pending,
    List<String>? pageExts,
    int? createdAt,
  }) : pageExts = pageExts ?? [],
       createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory DownloadTask.fromMap(Map<String, dynamic> m) => DownloadTask(
    gid: (m['gid'] as num).toInt(),
    title: m['title'] as String? ?? '',
    thumbUrl: m['thumbUrl'] as String? ?? '',
    mediaId: m['mediaId'] as String? ?? '',
    totalPages: (m['totalPages'] as num?)?.toInt() ?? 0,
    downloadedPages: (m['downloadedPages'] as num?)?.toInt() ?? 0,
    status: DownloadStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => DownloadStatus.pending,
    ),
    savedDir: m['savedDir'] as String? ?? '',
    pageExts: List<String>.from(
      jsonDecode(m['pageExts'] as String? ?? '[]') as List,
    ),
    createdAt: (m['createdAt'] as num?)?.toInt(),
  );

  final int gid;
  final String title;
  final String thumbUrl;
  final String mediaId;
  final int totalPages;
  final String savedDir;
  final int createdAt;
  int downloadedPages;
  DownloadStatus status;
  List<String> pageExts;

  DownloadTask copyWith({
    int? downloadedPages,
    DownloadStatus? status,
    List<String>? pageExts,
  }) {
    return DownloadTask(
      gid: gid,
      title: title,
      thumbUrl: thumbUrl,
      mediaId: mediaId,
      totalPages: totalPages,
      savedDir: savedDir,
      downloadedPages: downloadedPages ?? this.downloadedPages,
      status: status ?? this.status,
      pageExts: pageExts ?? List.from(this.pageExts),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'gid': gid,
    'title': title,
    'thumbUrl': thumbUrl,
    'mediaId': mediaId,
    'totalPages': totalPages,
    'downloadedPages': downloadedPages,
    'status': status.name,
    'savedDir': savedDir,
    'pageExts': jsonEncode(pageExts),
    'createdAt': createdAt,
  };
}
