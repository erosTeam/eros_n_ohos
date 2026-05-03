import 'package:share_plus/share_plus.dart';

export 'package:share_plus/share_plus.dart' show XFile;

class ShareUtil {
  ShareUtil._();

  static Future<void> shareText(String text) {
    // ignore: deprecated_member_use
    return Share.share(text);
  }

  static Future<void> shareFiles(List<XFile> files) {
    return Share.shareXFiles(files);
  }
}
