import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  // Current app version se compare karne wala minimum version.
  // Apne next APK ke version ke hisaab se change karein.
  static const String minimumVersion = '1.2.0';

  static const String installDateKey = 'first_install_date';

  // App ki first launch date save karein.
  static Future<void> saveInstallDate() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(installDateKey)) {
      await prefs.setString(installDateKey, DateTime.now().toIso8601String());
    }
  }

  // Calendar ke 2 months baad ki date calculate karein.
  static DateTime addTwoMonths(DateTime date) {
    final monthIndex = date.month - 1 + 2;
    final year = date.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;

    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;

    return DateTime(year, month, day, date.hour, date.minute, date.second);
  }

  // App version aur expiry date check karein.
  static Future<bool> isUpdateRequired() async {
    final prefs = await SharedPreferences.getInstance();

    final savedDate = prefs.getString(installDateKey);
    if (savedDate == null) return false;

    final installDate = DateTime.parse(savedDate);
    final expiryDate = addTwoMonths(installDate);

    if (DateTime.now().isBefore(expiryDate)) {
      return false;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    return compareVersions(currentVersion, minimumVersion) < 0;
  }

  // GitHub Releases: publish a release tagged like v1.1.0 with the APK
  // attached as an asset. That is what "Update Now" downloads.
  static const String _latestReleaseApi =
      'https://api.github.com/repos/Mohdrizwan329/Video-Editor/releases/latest';

  /// The APK of a release newer than the installed app, or null when there is
  /// no newer build (no release yet, no APK attached, same or older version).
  /// Throws on network failure so the caller can tell "offline" apart.
  static Future<Uri?> findNewerApk() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseApi));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 404) return null; // no release published
      if (response.statusCode != 200) {
        throw HttpException('Release lookup failed (${response.statusCode})');
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tag = (json['tag_name'] as String? ?? '').replaceFirst(
        RegExp('^[vV]'),
        '',
      );
      final latest = tag.split('+').first;
      if (!RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(latest)) return null;

      final current = (await PackageInfo.fromPlatform()).version;
      if (compareVersions(latest, current) <= 0) return null;

      // Releases carry one APK per CPU type; take the one this phone runs,
      // else any APK (a universal build) rather than none.
      final abiTag = _abiTag();
      Uri? fallback;
      for (final asset in (json['assets'] as List?) ?? const []) {
        final a = asset as Map<String, dynamic>;
        final name = (a['name'] as String? ?? '').toLowerCase();
        final url = a['browser_download_url'] as String?;
        if (url == null || !name.endsWith('.apk')) continue;
        if (abiTag != null && name.contains(abiTag)) return Uri.parse(url);
        if (!RegExp('arm64-v8a|armeabi-v7a|x86_64|x86').hasMatch(name)) {
          fallback ??= Uri.parse(url);
        }
      }
      return fallback;
    } finally {
      client.close();
    }
  }

  /// The ABI name used in split APK file names, for the CPU this app runs on.
  static String? _abiTag() {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'arm64-v8a';
    if (abi == Abi.androidArm) return 'armeabi-v7a';
    if (abi == Abi.androidX64) return 'x86_64';
    return null;
  }

  // Example: 1.0.0 < 1.1.0
  static int compareVersions(String a, String b) {
    final first = a.split('.').map(int.parse).toList();
    final second = b.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final x = i < first.length ? first[i] : 0;
      final y = i < second.length ? second[i] : 0;

      if (x < y) return -1;
      if (x > y) return 1;
    }

    return 0;
  }
}
