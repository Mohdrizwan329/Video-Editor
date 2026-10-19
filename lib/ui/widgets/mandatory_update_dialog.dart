import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_editor/data/services/update_service.dart';

class MandatoryUpdateDialog {
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          const PopScope(canPop: false, child: _UpdateDialog()),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _checking = false;
  String? _message;

  /// Opens the download only when a newer build is actually published;
  /// otherwise says why nothing happened and leaves the user here.
  Future<void> _update() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    String? message;
    try {
      final apk = await UpdateService.findNewerApk();
      if (apk == null) {
        message = 'No new version is available yet. Please try again later.';
      } else if (!await launchUrl(apk, mode: LaunchMode.externalApplication)) {
        message = 'Could not open the download. Please try again.';
      }
    } catch (_) {
      message =
          'Could not check for updates. Check your internet connection '
          'and try again.';
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A new version of this app is available. '
            'Please update the app to continue.',
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: _checking ? null : _update,
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Now'),
        ),
      ],
    );
  }
}
