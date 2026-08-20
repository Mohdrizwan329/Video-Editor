import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_ext.dart';
import '../../data/models/enums.dart';
import '../../data/models/project.dart';
import '../../data/services/clip_operations.dart';
import '../../data/services/export_service.dart';
import '../../data/services/export_settings.dart';

/// Render settings, live progress, and what to do with the finished file.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, required this.project});

  final Project project;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final ExportSettings _settings = ExportSettings(
    canvasAspect: widget.project.canvasAspect,
  );

  /// Video or animated GIF.
  bool _gifMode = false;
  ExportProgress? _progress;
  ExportResult? _result;
  bool _running = false;
  bool _savedToGallery = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _running) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Export'),
          leading: IconButton(
            icon: const Icon(Icons.close, size: 21),
            onPressed: () => _running ? _confirmCancel() : Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: _result != null
              ? _resultView()
              : _running
                  ? _progressView()
                  : _settingsView(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- settings

  Widget _settingsView() {
    final duration = widget.project.totalDuration;
    final (w, h) = _settings.outputSize;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _summaryCard(w, h, duration),
        const SizedBox(height: 18),
        _sectionLabel('Format'),
        _optionRow(
          const ['MP4 video', 'Animated GIF'],
          _gifMode ? 1 : 0,
          (i) => setState(() => _gifMode = i == 1),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Resolution'),
        _optionRow(
          ExportResolution.values.map((r) => r.label).toList(),
          ExportResolution.values.indexOf(_settings.resolution),
          (i) => setState(
              () => _settings.resolution = ExportResolution.values[i]),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Frame rate'),
        _optionRow(
          ExportFps.values.map((f) => f.label).toList(),
          ExportFps.values.indexOf(_settings.fps),
          (i) => setState(() => _settings.fps = ExportFps.values[i]),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Quality'),
        _optionRow(
          ExportQuality.values.map((q) => q.label).toList(),
          ExportQuality.values.indexOf(_settings.quality),
          (i) => setState(() => _settings.quality = ExportQuality.values[i]),
        ),
        const SizedBox(height: 26),
        InkWell(
          onTap: _start,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.appBarGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.glow(AppColors.appBar, opacity: 0.34),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.rocket_launch_rounded,
                    size: 19, color: AppColors.onAppBar),
                const SizedBox(width: 9),
                Text(_gifMode ? 'Export GIF' : 'Start export',
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAppBar)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Rendering runs on device with FFmpeg. Keep the app open — higher '
          'resolutions and slower presets take longer.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
      ],
    );
  }

  Widget _summaryCard(int w, int h, Duration duration) {
    final size = _settings.estimatedBytes(duration);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.tint(AppColors.appBar),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.appBar.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat('Size', '$w × $h'),
              _stat('Length', duration.pretty),
              _stat('Est. file', _bytes(size)),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'H.264 · AAC · ${_settings.videoBitrateKbps} kbps · '
                  '${_settings.preset} preset',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: AppColors.appBarMuted, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(label,
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textFaint)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.appBar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDim)),
          ],
        ),
      );

  Widget _optionRow(
      List<String> labels, int selected, ValueChanged<int> onSelected) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected
                        ? AppColors.appBar.withValues(alpha: 0.10)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: i == selected
                          ? AppColors.appBarMuted
                          : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: i == selected
                          ? AppColors.appBarMuted
                          : AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------- progress

  Widget _progressView() {
    final p = _progress;
    final value = (p?.value ?? -1);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 116,
              height: 116,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: value < 0 ? null : value,
                      strokeWidth: 5,
                      backgroundColor: AppColors.surfaceHigh,
                      color: AppColors.accent,
                    ),
                  ),
                  Text(
                    value < 0 ? '…' : '${(value * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(p?.stage ?? 'Preparing',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              p?.eta != null
                  ? 'About ${p!.eta!.pretty} left · ${p.speed.toStringAsFixed(1)}x'
                  : 'Building the render graph',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
            ),
            const SizedBox(height: 30),
            OutlinedButton(
              onPressed: _confirmCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                minimumSize: const Size(140, 42),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- result

  Widget _resultView() {
    final r = _result!;
    if (!r.success) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 46, color: AppColors.danger),
              const SizedBox(height: 14),
              Text(r.error ?? 'Export failed',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (r.log != null)
                Container(
                  constraints: const BoxConstraints(maxHeight: 190),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(r.log!,
                        style: const TextStyle(
                            fontSize: 9.5,
                            color: AppColors.textFaint,
                            fontFamily: 'monospace')),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    minimumSize: const Size(160, 44)),
                onPressed: () => setState(() {
                  _result = null;
                  _progress = null;
                }),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final file = File(r.path!);
    final size = file.existsSync() ? file.lengthSync() : 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: const BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 34, color: AppColors.onAccent),
            ),
            const SizedBox(height: 18),
            const Text('Export complete',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${_bytes(size)} · ${_settings.resolution.label} · '
                '${_settings.fps.label} fps',
                style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(r.path!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textFaint)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    _savedToGallery ? AppColors.surfaceHigh : AppColors.accent,
                foregroundColor:
                    _savedToGallery ? AppColors.textDim : AppColors.onAccent,
                minimumSize: const Size(200, 46),
              ),
              icon: Icon(_savedToGallery ? Icons.check : Icons.save_alt,
                  size: 18),
              label: Text(_savedToGallery
                  ? 'Saved to gallery'
                  : _gifMode
                      ? 'Save GIF to gallery'
                      : 'Save to gallery'),
              onPressed: _savedToGallery ? null : () => _saveToGallery(r.path!),
            ),
            const SizedBox(height: 10),
            TextButton(
              // Secondary to the filled save action, so it takes the page's
              // header tone rather than the accent.
              style: AppTheme.outlinedAction(tone: AppColors.appBarMuted),
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to editor'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- actions

  Future<void> _start() async {
    setState(() {
      _running = true;
      _progress = null;
      _result = null;
      _savedToGallery = false;
    });
    // A GIF is rendered from the finished MP4 so every effect is baked in
    // before palette generation — one code path, no second filter graph.
    final result = await ExportService.instance.export(
      widget.project,
      _settings,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (_gifMode && result.success && result.path != null) {
      if (mounted) {
        setState(() => _progress =
            const ExportProgress(stage: 'Building GIF palette', value: -1));
      }
      final gif = await ClipOperations.exportGif(
        result.path!,
        duration: widget.project.totalDuration,
        width: _settings.width >= _settings.height ? 640 : 480,
        fps: _settings.fps.value > 20 ? 15 : _settings.fps.value,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = gif == null
            ? const ExportResult(success: false, error: 'GIF encode failed')
            : ExportResult(success: true, path: gif);
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel export?'),
        actions: [
          TextButton(
              style: AppTheme.outlinedAction(),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep going')),
          TextButton(
              style: AppTheme.outlinedAction(tone: AppColors.dangerSoft),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (ok == true) {
      await ExportService.instance.cancel();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _saveToGallery(String path) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) await Gal.requestAccess(toAlbum: true);
      if (_gifMode) {
        await Gal.putImage(path, album: 'Saleem Video Editor');
      } else {
        await Gal.putVideo(path, album: 'Saleem Video Editor');
      }
      if (mounted) setState(() => _savedToGallery = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  static String _bytes(int b) {
    if (b <= 0) return '—';
    if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
