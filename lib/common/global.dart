import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:eros_n/common/const/const.dart';
import 'package:eros_n/network/app_dio/app_dio.dart';
import 'package:eros_n/routes/routes.dart';
import 'package:eros_n/store/db/db_store.dart';
import 'package:eros_n/store/db/sqlite_db_store.dart';
import 'package:eros_n/store/kv/hive.dart';
import 'package:eros_n/utils/clipboard_helper.dart';
import 'package:eros_n/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as iaw;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

DioHttpConfig globalDioConfig = nhDioConfig;

final HiveHelper hiveHelper = HiveHelper();
final DbStore objectBoxHelper = SqliteDbStore();
final ClipboardHelper clipboardHelper = ClipboardHelper();
final erosRouter = AppRouter();

const DioHttpConfig nhDioConfig = DioHttpConfig(
  baseUrl: NHConst.baseUrl,
  connectTimeout: 10000,
  sendTimeout: 8000,
  receiveTimeout: 20000,
  maxConnectionsPerHost: null,
  userAgent: NHConst.userAgent,
);

class Global {
  static String appSupportPath = '';
  static String appDocPath = '';
  static String tempPath = '';
  static late String extStorePath;
  static String dbPath = '';

  static late PersistCookieJar cookieJar;

  static String? userAgent;

  static Future<void> setUserAgent(String ua) {
    userAgent = ua;
    hiveHelper.setUserAgent(ua);
    return Future.value();
  }

  static Future<void> setCookies(String url, List<Cookie> cookies) async {
    await Global.cookieJar.saveFromResponse(
      Uri.parse(NHConst.baseUrl),
      cookies,
    );
  }

  static late PackageInfo packageInfo;

  static Future<void> init() async {
    try {
      appSupportPath = (await getApplicationSupportDirectory()).path;
      appDocPath = (await getApplicationDocumentsDirectory()).path;
      tempPath = (await getTemporaryDirectory()).path;
    } catch (e) {
      debugPrint('[Global] path_provider failed: $e, using fallback paths');
      const base = '/data/storage/el2/base/haps/entry/files';
      appSupportPath = base;
      appDocPath = base;
      tempPath = base;
    }

    extStorePath = Platform.isAndroid || Platform.isFuchsia
        ? (await getExternalStorageDirectory())?.path ?? ''
        : '';

    cookieJar = PersistCookieJar(storage: FileStorage(Global.appSupportPath));

    if (!kDebugMode) {
      Logger.level = Level.info;
    } else {
      Logger.level = Level.debug;
    }
    initLogger();

    if (Platform.isAndroid) {
      await iaw.InAppWebViewController.setWebContentsDebuggingEnabled(true);

      final swAvailable = await iaw.WebViewFeature.isFeatureSupported(
        iaw.WebViewFeature.SERVICE_WORKER_BASIC_USAGE,
      );
      final swInterceptAvailable = await iaw.WebViewFeature.isFeatureSupported(
        iaw.WebViewFeature.SERVICE_WORKER_SHOULD_INTERCEPT_REQUEST,
      );

      if (swAvailable && swInterceptAvailable) {
        iaw.ServiceWorkerController.instance();

        // await serviceWorkerController
        //     .setServiceWorkerClient(iaw.AndroidServiceWorkerClient(
        //   shouldInterceptRequest: (request) async {
        //     print(request);
        //     return null;
        //   },
        // ));
      }
    }

    packageInfo = await PackageInfo.fromPlatform().catchError((e) {
      debugPrint('[Global] PackageInfo.fromPlatform failed: $e');
      return PackageInfo(
        appName: 'eros N',
        packageName: 'com.erosteam.erosn',
        version: '0.0.0',
        buildNumber: '0',
      );
    });

    try {
      await HiveHelper.init();
    } catch (e) {
      debugPrint('[Global] HiveHelper.init failed: $e');
    }

    try {
      await objectBoxHelper.init();
    } catch (e) {
      debugPrint('[Global] objectBoxHelper.init failed: $e');
    }

    userAgent = hiveHelper.getUserAgent();
    userAgent ??= NHConst.userAgent;
    globalDioConfig = nhDioConfig.copyWith(userAgent: userAgent);
  }
}
