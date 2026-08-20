import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/duration_ext.dart';
import '../../data/models/enums.dart';
import '../../data/models/project.dart';
import '../../data/services/ai_video_service.dart';
import '../widgets/app_slider.dart';

/// Describe a shot, get real AI footage back.
///
/// The prompt goes to Google's Veo through the Gemini API, the finished MP4
/// is downloaded into the app's media folder, and the result lands on the
/// timeline as an ordinary clip — so everything the editor does (trim, text,
/// music, export) works on it afterwards.
///
/// Pops the finished [Project] so the caller can open it in the editor.
class TextToVideoScreen extends StatefulWidget {
  const TextToVideoScreen({super.key});

  @override
  State<TextToVideoScreen> createState() => _TextToVideoScreenState();
}

class _TextToVideoScreenState extends State<TextToVideoScreen> {
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _negative = TextEditingController();

  // Veo renders portrait and landscape only, so those are the two offered.
  static const List<CanvasRatio> _ratios = [
    CanvasRatio.r9x16,
    CanvasRatio.r16x9,
  ];

  AiSettings? _settings;
  CanvasRatio _ratio = CanvasRatio.r9x16;
  double _seconds = 5;
  bool _showNegative = false;

  bool _working = false;
  AiJobUpdate? _update;
  AiCancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _negative.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await AiSettingsStore.instance.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _ratio = _ratios.firstWhere(
        (r) => AiVideoService.aspectFor(r) == settings.aspectRatio,
        orElse: () => CanvasRatio.r9x16,
      );
      _seconds = settings.durationSeconds.toDouble();
    });
  }

  int get _shotCount => AiVideoService.splitShots(_prompt.text).length;

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final res = context.r;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Text to Video'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (settings == null)
              const Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent),
              )
            else
              ContentBox(
                maxWidth: 640,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    res.gutter,
                    res.vp(12),
                    res.gutter,
                    res.vp(26) + res.viewInsets.bottom,
                  ),
                  children: [
                    _headerCard(),
                    SizedBox(height: res.vp(14)),
                    _promptCard(),
                    SizedBox(height: res.vp(10)),
                    _summaryRow(),
                    SizedBox(height: res.vp(16)),
                    _sectionLabel('Frame'),
                    _ratioRow(),
                    SizedBox(height: res.vp(12)),
                    _lengthCard(settings),
                    SizedBox(height: res.vp(18)),
                    _generateButton(),
                  ],
                ),
              ),
            if (_working) _progressOverlay(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- pieces

  /// Names the feature above the prompt box, in the same violet the home
  /// screen's card uses, so arriving here reads as the card that was tapped.
  Widget _headerCard() {
    final res = context.r;
    return Container(
      padding: EdgeInsets.symmetric(vertical: res.vp(16)),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.glow(AppColors.violet, opacity: 0.3),
      ),
      child: Row(
        children: [
          SizedBox(width: res.dp(18)),
          Container(
            width: res.dp(46),
            height: res.dp(46),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Icon(Icons.movie_filter,
                color: Colors.white, size: res.ic(24)),
          ),
          SizedBox(width: res.dp(14)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generate Text to AI Video',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: res.sp(15.5),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: res.vp(3)),
                Text(
                  'Describe a shot — Veo films it',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: res.sp(11.5), color: const Color(0xCCFFFFFF)),
                ),
              ],
            ),
          ),
          SizedBox(width: res.dp(16)),
        ],
      ),
    );
  }

  Widget _promptCard() {
    final res = context.r;
    return _card(
      padding: EdgeInsets.symmetric(
          horizontal: res.dp(14), vertical: res.vp(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _prompt,
            // A short window shows fewer lines rather than pushing the
            // Generate button off the bottom.
            minLines: res.isShort ? 3 : 5,
            maxLines: res.isShort ? 6 : 10,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: res.sp(13.5), height: 1.45),
            decoration: _fieldDecoration(
              'A cinematic drone shot flying over a misty mountain lake at '
              'sunrise, golden light, slow forward motion.\n\n'
              'Leave a blank line to start a second shot.',
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: res.vp(6)),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.appBarMuted,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
            ),
            icon: Icon(
                _showNegative ? Icons.expand_less : Icons.expand_more,
                size: res.ic(17)),
            label: Text('Things to avoid (optional)',
                style: TextStyle(fontSize: res.sp(11.5))),
            onPressed: () => setState(() => _showNegative = !_showNegative),
          ),
          if (_showNegative)
            TextField(
              controller: _negative,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 12.5),
              decoration:
                  _fieldDecoration('blurry, text, watermark, distorted hands'),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow() {
    final shots = _shotCount;
    final perShot = _settings?.takesDuration ?? false ? _seconds.round() : 8;
    final total = Duration(seconds: perShot * shots);
    // Three pills of unpredictable width: they wrap rather than overflow when
    // the window is narrow or the system font is large.
    return Wrap(
      spacing: context.r.dp(8),
      runSpacing: context.r.vp(8),
      children: [
        _pill(Icons.videocam_outlined, '$shots shot${shots == 1 ? '' : 's'}'),
        _pill(Icons.schedule, '≈ ${total.mmss} of video'),
        if (shots > 1)
          _pill(Icons.payments_outlined, '$shots billed runs'),
      ],
    );
  }

  /// Veo 3 films a fixed eight seconds, so there is nothing to choose — the
  /// slider only appears for the Veo 2 models that really take a length.
  Widget _lengthCard(AiSettings settings) {
    if (!settings.takesDuration) {
      final res = context.r;
      return _card(
        padding: EdgeInsets.all(res.dp(13)),
        child: Row(
          children: [
            Icon(Icons.timer_outlined,
                size: res.ic(17), color: AppColors.appBarMuted),
            SizedBox(width: res.dp(12)),
            Expanded(
              child: Text(
                'This model films 8 seconds per shot, with sound.',
                style: TextStyle(
                    fontSize: res.sp(12), color: AppColors.textDim),
              ),
            ),
          ],
        ),
      );
    }
    return _card(
      child: AppSlider(
        label: 'Clip length',
        icon: Icons.timer_outlined,
        value: _seconds,
        min: 5,
        max: 8,
        divisions: 3,
        defaultValue: 8,
        format: (v) => '${v.round()}s',
        onChanged: (v) => setState(() => _seconds = v),
      ),
    );
  }

  Widget _ratioRow() {
    final res = context.r;
    return Wrap(
      spacing: res.dp(8),
      runSpacing: res.vp(8),
      children: _ratios.map((r) {
        final selected = r == _ratio;
        return InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() => _ratio = r),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: res.dp(13), vertical: res.vp(9)),
            decoration: BoxDecoration(
              color: selected ? AppColors.appBar : AppColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                  color: selected ? AppColors.appBar : AppColors.stroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(r.icon,
                    size: res.ic(15),
                    color: selected ? AppColors.onAppBar : AppColors.textDim),
                SizedBox(width: res.dp(7)),
                Text(
                  AiVideoService.aspectFor(r),
                  style: TextStyle(
                    fontSize: res.sp(12),
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.onAppBar : AppColors.text,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _generateButton() {
    final ready = _shotCount > 0 && !_working;
    final res = context.r;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        minimumSize: Size.fromHeight(res.tap(50)),
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.textFaint,
      ),
      icon: Icon(Icons.auto_awesome, size: res.ic(19)),
      label: Text(
        _shotCount == 0 ? 'Describe your video first' : 'Generate with AI',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: res.sp(14), fontWeight: FontWeight.w700),
      ),
      onPressed: ready ? _generate : null,
    );
  }

  Widget _progressOverlay() {
    final update = _update;
    final shots = update?.shots ?? 1;
    final res = context.r;
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background.withValues(alpha: 0.94),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: res.gutter + res.dp(14),
              vertical: res.vp(20),
            ),
            child: ContentBox(
              maxWidth: 480,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: res.dp(36),
                  height: res.dp(36),
                  child: const CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.accent),
                ),
                SizedBox(height: res.vp(18)),
                Text(
                  update?.message ?? 'Starting',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: res.sp(14), fontWeight: FontWeight.w700),
                ),
                SizedBox(height: res.vp(6)),
                Text(
                  shots > 1
                      ? 'Shot ${update?.shot ?? 1} of $shots · '
                          '${(update?.elapsed ?? Duration.zero).mmss} elapsed'
                      : '${(update?.elapsed ?? Duration.zero).mmss} elapsed',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: res.sp(11.5), color: AppColors.textDim),
                ),
                SizedBox(height: res.vp(14)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: update?.fraction,
                    minHeight: 5,
                  ),
                ),
                SizedBox(height: res.vp(14)),
                Text(
                  'Veo takes a few minutes per shot. Keep the app open — '
                  'the clip downloads as soon as it is ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: res.sp(11), color: AppColors.textFaint),
                ),
                SizedBox(height: res.vp(18)),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.5)),
                    minimumSize: Size(0, res.tap(40)),
                  ),
                  icon:
                      Icon(Icons.stop_circle_outlined, size: res.ic(17)),
                  label: const Text('Cancel'),
                  onPressed: () => _cancel?.cancel(),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: EdgeInsets.only(left: 4, bottom: context.r.vp(8)),
        child: Text(text,
            style: TextStyle(
                fontSize: context.r.sp(12.5), fontWeight: FontWeight.w700)),
      );

  Widget _pill(IconData icon, String label) {
    final res = context.r;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: res.dp(10), vertical: res.vp(6)),
      decoration: BoxDecoration(
        color: AppColors.appBar.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: res.ic(13), color: AppColors.appBarMuted),
          SizedBox(width: res.dp(6)),
          Text(label,
              style: TextStyle(
                  fontSize: res.sp(11),
                  fontWeight: FontWeight.w600,
                  color: AppColors.appBarMuted)),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: child,
      );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  // ------------------------------------------------------------- actions

  Future<void> _generate() async {
    final settings = _settings;
    if (settings == null) return;
    final shots = AiVideoService.splitShots(_prompt.text);
    if (shots.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    // Remember the setup, so the next run starts where this one left off.
    settings
      ..aspectRatio = AiVideoService.aspectFor(_ratio)
      ..durationSeconds = _seconds.round();
    await AiSettingsStore.instance.save(settings);

    final cancel = AiCancelToken();
    setState(() {
      _working = true;
      _update = null;
      _cancel = cancel;
    });

    final paths = <String>[];
    String? failure;

    for (var i = 0; i < shots.length; i++) {
      try {
        final path = await AiVideoService.instance.generateShot(
          prompt: shots[i],
          settings: settings,
          negativePrompt: _negative.text,
          cancelToken: cancel,
          shot: i + 1,
          shots: shots.length,
          onUpdate: (u) {
            if (mounted) setState(() => _update = u);
          },
        );
        paths.add(path);
      } on AiVideoException catch (e) {
        failure = e.message;
        break;
      } catch (e) {
        failure = 'Generation failed: $e';
        break;
      }
    }

    if (!mounted) return;

    // Anything already generated was paid for, so it is kept even when a
    // later shot fails or the run is cancelled.
    if (paths.isNotEmpty) {
      try {
        final project = await AiVideoService.instance.assembleProject(
          paths: paths,
          ratio: _ratio,
          name: _projectName(shots.first),
        );
        if (!mounted) return;
        if (failure != null) {
          messenger.showSnackBar(SnackBar(
            content: Text('$failure Kept ${paths.length} of '
                '${shots.length} shots.'),
          ));
        }
        Navigator.pop<Project>(context, project);
        return;
      } catch (e) {
        failure = 'Could not build the project: $e';
      }
    }

    setState(() {
      _working = false;
      _cancel = null;
    });
    messenger.showSnackBar(
        SnackBar(content: Text(failure ?? 'Nothing was generated.')));
  }

  String _projectName(String prompt) {
    final flat = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return 'AI video';
    return flat.length <= 28 ? flat : '${flat.substring(0, 28).trim()}…';
  }
}
