import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/duration_ext.dart';
import '../../core/utils/responsive.dart';
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
            icon: Icon(Icons.close, size: context.r.ic(21)),
            onPressed: () =>
                _running ? _confirmCancel() : Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          // One readable column whatever the window: a phone fills it, a
          // desktop centres it instead of stretching the option rows.
          child: ContentBox(
            maxWidth: 640,
            child: _result != null
                ? _resultView()
                : _running
                ? _progressView()
                : _settingsView(),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- settings

  Widget _settingsView() {
    final duration = widget.project.totalDuration;
    final (w, h) = _settings.outputSize;
    final r = context.r;
    // Nothing here scrolls. What the screen is for is picking a format and
    // pressing the button, and a settings page that slides takes the button
    // off the bottom of it — the user then hunts for the thing they opened
    // the screen to do.
    //
    // So the button, and the way to the rest of the dials, are pinned; the
    // part above them shows what the window has room for and clips the rest.
    // Nothing is lost by that: the sheet behind 'More settings' carries
    // every dial, the two up here included.
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, r.vp(12), r.gutter, r.vp(12)),
      child: Column(
        children: [
          // Expanded, not Flexible: the dials sit at the top and the button
          // at the bottom of the screen, rather than the two of them bunched
          // under the summary with the rest of the window left blank.
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                children: [
                  _summaryCard(w, h, duration),
                  SizedBox(height: r.vp(16)),
                  _sectionLabel('Format'),
                  _formatRow(),
                  SizedBox(height: r.vp(14)),
                  _sectionLabel('Resolution'),
                  _resolutionRow(),
                  SizedBox(height: r.vp(12)),
                ],
              ),
            ),
          ),
          _moreSettingsButton(r),
          SizedBox(height: r.vp(12)),
          _startButton(r),
          SizedBox(height: r.vp(10)),
          Text(
            'Rendering runs on device with FFmpeg. Keep the app open — higher '
            'resolutions and slower presets take longer.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(11), color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _formatRow() => _optionRow(
    const ['MP4 video', 'Animated GIF'],
    _gifMode ? 1 : 0,
    (i) => setState(() => _gifMode = i == 1),
  );

  Widget _resolutionRow() => _optionRow(
    ExportResolution.values.map((r) => r.label).toList(),
    ExportResolution.values.indexOf(_settings.resolution),
    (i) => setState(() => _settings.resolution = ExportResolution.values[i]),
  );

  /// The way to the dials the screen does not show: frame rate and quality,
  /// which most exports never touch and which are the first thing to push
  /// the button off a small screen.
  Widget _moreSettingsButton(Responsive r) {
    return InkWell(
      onTap: _openMoreSettings,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: r.tap(46),
        padding: EdgeInsets.symmetric(horizontal: r.dp(14)),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.tune, size: r.ic(17), color: AppColors.appBarMuted),
            SizedBox(width: r.dp(10)),
            Expanded(
              child: Text(
                'More settings',
                style: TextStyle(
                  fontSize: r.sp(12.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // The current values, so the button says what is behind it
            // rather than only that something is.
            Text(
              '${_settings.fps.label} fps · ${_settings.quality.label}',
              style: TextStyle(fontSize: r.sp(11), color: AppColors.textFaint),
            ),
            SizedBox(width: r.dp(6)),
            Icon(
              Icons.chevron_right,
              size: r.ic(18),
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMoreSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: context.r.height * 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        // Its own state, so a tap on a chip repaints the sheet as well as
        // the screen behind it.
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void choose(VoidCallback change) {
              setSheetState(change);
              setState(() {});
            }

            final r = sheetContext.r;
            return SafeArea(
              top: false,
              child: ContentBox(
                maxWidth: 640,
                hugHeight: true,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    r.gutter,
                    r.vp(14),
                    r.gutter,
                    r.vp(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(width: r.ic(20) + r.dp(16)),
                          Expanded(
                            child: Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.divider,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          // Top right, where every sheet in the app puts the
                          // way out.
                          IconButton(
                            tooltip: 'Close',
                            icon: Icon(Icons.close, size: r.ic(20)),
                            color: AppColors.textFaint,
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      SizedBox(height: r.vp(6)),
                      // Format and Resolution are on the screen as well.
                      // They are here too because on a short window the
                      // screen clips them, and a dial the user cannot reach
                      // is worse than one shown twice.
                      _sectionLabel('Format'),
                      _optionRow(
                        const ['MP4 video', 'Animated GIF'],
                        _gifMode ? 1 : 0,
                        (i) => choose(() => _gifMode = i == 1),
                      ),
                      SizedBox(height: r.vp(16)),
                      _sectionLabel('Resolution'),
                      _optionRow(
                        ExportResolution.values.map((r) => r.label).toList(),
                        ExportResolution.values.indexOf(_settings.resolution),
                        (i) => choose(
                          () =>
                              _settings.resolution = ExportResolution.values[i],
                        ),
                      ),
                      SizedBox(height: r.vp(16)),
                      _sectionLabel('Frame rate'),
                      _optionRow(
                        ExportFps.values.map((f) => f.label).toList(),
                        ExportFps.values.indexOf(_settings.fps),
                        (i) =>
                            choose(() => _settings.fps = ExportFps.values[i]),
                      ),
                      SizedBox(height: r.vp(16)),
                      _sectionLabel('Quality'),
                      _optionRow(
                        ExportQuality.values.map((q) => q.label).toList(),
                        ExportQuality.values.indexOf(_settings.quality),
                        (i) => choose(
                          () => _settings.quality = ExportQuality.values[i],
                        ),
                      ),
                      SizedBox(height: r.vp(10)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _startButton(Responsive r) {
    return InkWell(
      onTap: _start,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: r.tap(52),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppColors.appBarGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.glow(AppColors.appBar, opacity: 0.34),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rocket_launch_rounded,
              size: r.ic(19),
              color: AppColors.onAppBar,
            ),
            SizedBox(width: r.dp(9)),
            Text(
              _gifMode ? 'Export GIF' : 'Start export',
              style: TextStyle(
                fontSize: r.sp(15.5),
                fontWeight: FontWeight.w800,
                color: AppColors.onAppBar,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(int w, int h, Duration duration) {
    final size = _settings.estimatedBytes(duration);
    final r = context.r;
    return Container(
      padding: EdgeInsets.all(r.dp(16)),
      decoration: BoxDecoration(
        gradient: AppColors.tint(AppColors.appBar),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.appBar.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _stat('Size', '$w × $h')),
              Expanded(child: _stat('Length', duration.pretty)),
              Expanded(child: _stat('Est. file', _bytes(size))),
            ],
          ),
          Divider(height: r.vp(22)),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: r.ic(14),
                color: AppColors.textFaint,
              ),
              SizedBox(width: r.dp(8)),
              Expanded(
                child: Text(
                  'H.264 · AAC · ${_settings.videoBitrateKbps} kbps · '
                  '${_settings.preset} preset',
                  style: TextStyle(
                    fontSize: r.sp(11),
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    final r = context.r;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.appBarMuted,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: r.dp(5)),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(10),
                  color: AppColors.textFaint,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: r.vp(4)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: r.sp(13.5), fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.vp(8), left: 2),
      child: Row(
        children: [
          Container(
            width: 3,
            height: r.sp(12),
            decoration: BoxDecoration(
              color: AppColors.appBar,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: r.dp(7)),
          Text(
            text,
            style: TextStyle(
              fontSize: r.sp(12),
              fontWeight: FontWeight.w700,
              color: AppColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  /// The options share one row while they each still have room for their
  /// label; below that they wrap onto a second line rather than squeezing
  /// "Balanced" into 50 points on a small phone.
  Widget _optionRow(
    List<String> labels,
    int selected,
    ValueChanged<int> onSelected,
  ) {
    final r = context.r;
    const gap = 6.0;
    const minTile = 78.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final perRow = (available / minTile).floor().clamp(2, labels.length);
        final tile = (available - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < labels.length; i++)
              SizedBox(
                width: tile,
                child: GestureDetector(
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: r.tap(44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: r.sp(12),
                        fontWeight: FontWeight.w700,
                        color: i == selected
                            ? AppColors.appBarMuted
                            : AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------- progress

  Widget _progressView() {
    final p = _progress;
    final value = (p?.value ?? -1);
    final r = context.r;
    // The dial is a share of the window, so it stays a dial on a small phone
    // and does not become a postage stamp on a desktop monitor.
    final dial = (r.shortestSide * 0.3).clamp(88.0, 168.0);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: r.gutter + r.dp(12),
          vertical: r.vp(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: dial,
              height: dial,
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
                    style: TextStyle(
                      fontSize: r.sp(21),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: r.vp(22)),
            Text(
              p?.stage ?? 'Preparing',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: r.sp(14), fontWeight: FontWeight.w600),
            ),
            SizedBox(height: r.vp(6)),
            Text(
              p?.eta != null
                  ? 'About ${p!.eta!.pretty} left · ${p.speed.toStringAsFixed(1)}x'
                  : 'Building the render graph',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: r.sp(11.5), color: AppColors.textDim),
            ),
            SizedBox(height: r.vp(30)),
            OutlinedButton(
              onPressed: _confirmCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                minimumSize: Size(r.dp(140), r.tap(42)),
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
    final result = _result!;
    final r = context.r;
    if (!result.success) {
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: r.gutter + r.dp(8),
            vertical: r.vp(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: r.ic(46),
                color: AppColors.danger,
              ),
              SizedBox(height: r.vp(14)),
              Text(
                result.error ?? 'Export failed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: r.sp(14.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: r.vp(10)),
              if (result.log != null)
                Container(
                  constraints: BoxConstraints(
                    maxHeight: math.min(r.vp(190), r.height * 0.34),
                  ),
                  padding: EdgeInsets.all(r.dp(10)),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(
                      result.log!,
                      style: TextStyle(
                        fontSize: r.sp(9.5),
                        color: AppColors.textFaint,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              SizedBox(height: r.vp(18)),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  minimumSize: Size(r.dp(160), r.tap(44)),
                ),
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

    final file = File(result.path!);
    final size = file.existsSync() ? file.lengthSync() : 0;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: r.gutter + r.dp(8),
          vertical: r.vp(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: r.dp(66),
              height: r.dp(66),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                size: r.ic(34),
                color: AppColors.onAccent,
              ),
            ),
            SizedBox(height: r.vp(18)),
            Text(
              'Export complete',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: r.sp(16), fontWeight: FontWeight.w700),
            ),
            SizedBox(height: r.vp(6)),
            Text(
              '${_bytes(size)} · ${_settings.resolution.label} · '
              '${_settings.fps.label} fps',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: r.sp(12), color: AppColors.textDim),
            ),
            SizedBox(height: r.vp(8)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.dp(12)),
              child: Text(
                result.path!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: r.sp(10),
                  color: AppColors.textFaint,
                ),
              ),
            ),
            SizedBox(height: r.vp(24)),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _savedToGallery
                    ? AppColors.surfaceHigh
                    : AppColors.accent,
                foregroundColor: _savedToGallery
                    ? AppColors.textDim
                    : AppColors.onAccent,
                minimumSize: Size(r.dp(200), r.tap(46)),
              ),
              icon: Icon(
                _savedToGallery ? Icons.check : Icons.save_alt,
                size: r.ic(18),
              ),
              label: Text(
                _savedToGallery
                    ? 'Saved to gallery'
                    : _gifMode
                    ? 'Save GIF to gallery'
                    : 'Save to gallery',
              ),
              onPressed: _savedToGallery
                  ? null
                  : () => _saveToGallery(result.path!),
            ),
            SizedBox(height: r.vp(10)),
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
        setState(
          () => _progress = const ExportProgress(
            stage: 'Building GIF palette',
            value: -1,
          ),
        );
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
            child: const Text('Keep going'),
          ),
          TextButton(
            style: AppTheme.outlinedAction(tone: AppColors.dangerSoft),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel'),
          ),
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
        await Gal.putImage(path, album: 'Video Editor');
      } else {
        await Gal.putVideo(path, album: 'Video Editor');
      }
      if (mounted) setState(() => _savedToGallery = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
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
