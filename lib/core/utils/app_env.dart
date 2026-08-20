import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration the app is built with rather than typed into it.
///
/// The Gemini key lives in a `.env` file at the project root, which is bundled
/// as an asset. That keeps the key out of the source and out of the UI — but
/// not out of the APK: anything shipped as an asset can be read by anyone who
/// unpacks the build, so this is a convenience for a private build, not a
/// secret store.
///
/// `--dart-define=GEMINI_API_KEY=…` is honoured as well, for builds that would
/// rather not carry the file at all.
class AppEnv {
  AppEnv._();

  static const String _keyName = 'GEMINI_API_KEY';
  static const String _defined = String.fromEnvironment(_keyName);

  /// Test seam: stands in for the file so tests never depend on a real key.
  @visibleForTesting
  static String? overrideKey;

  /// Reads `.env` if it is there. A missing or malformed file is not fatal —
  /// the app still runs, and generation reports the missing key when tried.
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      debugPrint('no .env loaded: $e');
    }
  }

  /// The Google AI Studio key, or an empty string when none is configured.
  static String get geminiKey {
    final override = overrideKey;
    if (override != null) return override.trim();
    final fromFile = dotenv.isInitialized
        ? (dotenv.maybeGet(_keyName) ?? '').trim()
        : '';
    return fromFile.isNotEmpty ? fromFile : _defined.trim();
  }

  static bool get hasGeminiKey => geminiKey.isNotEmpty;

  /// Shown when a generation is attempted with nothing configured.
  static const String missingKeyMessage =
      'No Google AI key is configured. Put your key in the .env file as '
      'GEMINI_API_KEY=… and rebuild the app.';
}
