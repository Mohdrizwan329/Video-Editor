import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/duration_ext.dart';
import '../../data/models/enums.dart';
import '../../data/models/project.dart';
import '../../data/services/text_to_video_service.dart';
import '../../data/services/tts_service.dart';
import '../widgets/app_slider.dart';

/// Offline slide video: no model, no account, no network. Type a script, pick
/// a look, and the app paints one scene per line itself, with the device voice
/// narrating them if asked.
///
/// NOT LINKED FROM ANY SCREEN. This was the fallback shown when there was no
/// API key, and it was mistaken for the AI feature — text drawn on a painted
/// background is not AI-generated footage. It is kept, unwired, because it is
/// complete and tested: give it a route again if a "text slides" tool is ever
/// wanted as its own feature, well away from [TextToVideoScreen].
/// Pops the finished [Project] so the caller can open it in the editor.
class TextSlidesScreen extends StatefulWidget {
  const TextSlidesScreen({super.key});

  @override
  State<TextSlidesScreen> createState() => _TextSlidesScreenState();
}

class _TextSlidesScreenState extends State<TextSlidesScreen> {
  final TextEditingController _script = TextEditingController();
  final TextEditingController _title = TextEditingController();

  static const List<CanvasRatio> _ratios = [
    CanvasRatio.r9x16,
    CanvasRatio.r1x1,
    CanvasRatio.r16x9,
    CanvasRatio.r4x5,
  ];

  CanvasRatio _ratio = CanvasRatio.r9x16;
  String _styleId = TextVideoStyle.all.first.id;
  double _sceneSeconds = 3.2;
  bool _kenBurns = true;
  bool _narrate = false;
  double _rate = 0.5;

  List<TtsVoice> _voices = const [];
  TtsVoice? _voice;
  bool _voicesLoaded = false;

  bool _working = false;
  TextToVideoProgress? _progress;

  @override
  void dispose() {
    _script.dispose();
    _title.dispose();
    TtsService.instance.stop();
    super.dispose();
  }

  TextToVideoRequest get _request => TextToVideoRequest(
        script: _script.text,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        ratio: _ratio,
        styleId: _styleId,
        sceneDuration:
            Duration(milliseconds: (_sceneSeconds * 1000).round()),
        narrate: _narrate,
        voice: _voice,
        speechRate: _rate,
        kenBurns: _kenBurns,
      );

  int get _sceneCount {
    final scenes = TextToVideoService.splitScenes(_script.text).length;
    return scenes + (_title.text.trim().isEmpty ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final style = TextVideoStyle.byId(_styleId);
    final res = context.r;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Text Slides'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ContentBox(
              maxWidth: 640,
              child: ListView(
              padding: EdgeInsets.fromLTRB(
                res.gutter,
                res.vp(12),
                res.gutter,
                res.vp(24) + res.viewInsets.bottom,
              ),
              children: [
                _intro(style),
                SizedBox(height: res.vp(14)),
                _scriptField(),
                SizedBox(height: res.vp(10)),
                _summary(),
                SizedBox(height: res.vp(16)),
                _sectionLabel('Look'),
                _styleRow(),
                SizedBox(height: res.vp(16)),
                _sectionLabel('Frame'),
                _ratioRow(),
                SizedBox(height: res.vp(14)),
                _card(
                  child: Column(
                    children: [
                      AppSlider(
                        label: 'Scene length',
                        icon: Icons.timer_outlined,
                        value: _sceneSeconds,
                        min: 1.5,
                        max: 8,
                        divisions: 26,
                        defaultValue: 3.2,
                        format: (v) => '${v.toStringAsFixed(1)}s',
                        onChanged: (v) => setState(() => _sceneSeconds = v),
                      ),
                      SizedBox(height: res.vp(4)),
                      _switchRow(
                        icon: Icons.zoom_out_map,
                        title: 'Slow zoom',
                        subtitle: 'Gentle push on every scene',
                        value: _kenBurns,
                        onChanged: (v) => setState(() => _kenBurns = v),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: res.vp(14)),
                _narrationCard(),
                SizedBox(height: res.vp(20)),
                _generateButton(),
                SizedBox(height: res.vp(10)),
                Text(
                  'Everything lands on the timeline as normal clips, text and '
                  'audio — edit anything before you export.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: res.sp(11), color: AppColors.textFaint),
                ),
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

  Widget _intro(TextVideoStyle style) {
    final res = context.r;
    return Container(
      constraints: BoxConstraints(minHeight: res.vp(92)),
      padding: EdgeInsets.symmetric(vertical: res.vp(10)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [style.topColor, style.bottomColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.glow(style.topColor, opacity: 0.3),
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
            child: Icon(Icons.text_fields,
                color: Colors.white, size: res.ic(24)),
          ),
          SizedBox(width: res.dp(14)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text slide video',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: res.sp(15.5),
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: res.vp(3)),
                Text(
                  'Painted on your phone, no account needed',
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

  Widget _scriptField() {
    final res = context.r;
    return _card(
      padding: EdgeInsets.symmetric(
          horizontal: res.dp(14), vertical: res.vp(13)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
                fontSize: res.sp(14), fontWeight: FontWeight.w700),
            decoration: _fieldDecoration('Title (optional)'),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: res.vp(10)),
          TextField(
            controller: _script,
            // Fewer visible lines on a short window, so the controls below
            // stay reachable without a long scroll.
            minLines: res.isShort ? 3 : 6,
            maxLines: res.isShort ? 7 : 12,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: res.sp(13.5), height: 1.45),
            decoration: _fieldDecoration(
              'Type or paste your script.\n\nEvery line and every sentence '
              'becomes one scene.',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceHigh,
        hintStyle:
            TextStyle(fontSize: context.r.sp(12.5), color: AppColors.textFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _summary() {
    final count = _sceneCount;
    final estimate = TextToVideoService.estimate(_request);
    return Wrap(
      spacing: context.r.dp(8),
      runSpacing: context.r.vp(8),
      children: [
        _pill(Icons.view_carousel_outlined,
            '$count scene${count == 1 ? '' : 's'}'),
        _pill(
          Icons.schedule,
          _narrate ? 'timed to voice' : '≈ ${estimate.mmss}',
        ),
      ],
    );
  }

  Widget _pill(IconData icon, String label) {
    final res = context.r;
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: res.dp(10), vertical: res.vp(6)),
      decoration: BoxDecoration(
        color: AppColors.appBar.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: res.ic(13), color: AppColors.appBarMuted),
          SizedBox(width: res.dp(6)),
          Text(
            label,
            style: TextStyle(
              fontSize: res.sp(11),
              fontWeight: FontWeight.w600,
              color: AppColors.appBarMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: EdgeInsets.only(left: 4, bottom: context.r.vp(8)),
        child: Text(
          text,
          style: TextStyle(
              fontSize: context.r.sp(12.5), fontWeight: FontWeight.w700),
        ),
      );

  Widget _styleRow() {
    final res = context.r;
    return SizedBox(
      height: res.vp(86),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TextVideoStyle.all.length,
        separatorBuilder: (_, _) => SizedBox(width: res.dp(10)),
        itemBuilder: (context, i) {
          final style = TextVideoStyle.all[i];
          final selected = style.id == _styleId;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _styleId = style.id),
            child: Container(
              width: res.dp(74),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [style.topColor, style.bottomColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Text(
                      style.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: res.sp(11),
                        fontWeight: FontWeight.w700,
                        color: Color(style.textColor),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Icon(Icons.check_circle,
                          size: res.ic(16), color: AppColors.accentDim),
                    ),
                ],
              ),
            ),
          );
        },
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
              color: selected
                  ? AppColors.appBar
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected ? AppColors.appBar : AppColors.stroke,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(r.icon,
                    size: res.ic(15),
                    color: selected ? AppColors.onAppBar : AppColors.textDim),
                SizedBox(width: res.dp(7)),
                Text(
                  r.label,
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

  Widget _narrationCard() {
    return _card(
      child: Column(
        children: [
          _switchRow(
            icon: Icons.record_voice_over_outlined,
            title: 'Narrate the script',
            subtitle: 'Device voice reads each scene aloud',
            value: _narrate,
            onChanged: (v) {
              setState(() => _narrate = v);
              if (v && !_voicesLoaded) _loadVoices();
            },
          ),
          if (_narrate) ...[
            const Divider(height: 18),
            if (!_voicesLoaded)
              Padding(
                padding: EdgeInsets.symmetric(vertical: context.r.vp(8)),
                child: SizedBox(
                  width: context.r.dp(18),
                  height: context.r.dp(18),
                  child: const CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              )
            else if (_voices.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
                child: Text(
                  'No speech voices are installed on this device. Add one in '
                  'the system settings, or generate without narration.',
                  style: TextStyle(
                      fontSize: context.r.sp(11), color: AppColors.warning),
                ),
              )
            else
              _voicePicker(),
            AppSlider(
              label: 'Speaking speed',
              icon: Icons.speed,
              value: _rate,
              min: 0.2,
              max: 1.0,
              defaultValue: 0.5,
              format: (v) => v.toStringAsFixed(2),
              onChanged: (v) => setState(() => _rate = v),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: context.r.dp(14), top: 4),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, context.r.tap(34)),
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.divider),
                  ),
                  icon: Icon(Icons.volume_up, size: context.r.ic(15)),
                  label: Text('Hear the voice',
                      style: TextStyle(fontSize: context.r.sp(12))),
                  onPressed: _voices.isEmpty ? null : _previewVoice,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _voicePicker() {
    final res = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(res.dp(14), 2, res.dp(14), 4),
      child: Row(
        children: [
          Text('Voice',
              style:
                  TextStyle(fontSize: res.sp(11), color: AppColors.textDim)),
          SizedBox(width: res.dp(10)),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: res.dp(10)),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<TtsVoice>(
                  value: _voice,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: AppColors.appBar,
                  style: TextStyle(
                      fontSize: res.sp(12), color: AppColors.onAppBar),
                  selectedItemBuilder: (_) => _voices
                      .map((v) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text('${v.locale} · ${v.shortLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: res.sp(12),
                                    color: AppColors.text)),
                          ))
                      .toList(),
                  items: _voices
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text('${v.locale} · ${v.shortLabel}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _voice = v);
                    // Stick with this voice for the next project too.
                    TtsService.instance.rememberVoice(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final res = context.r;
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: res.dp(14), vertical: res.vp(4)),
      child: Row(
        children: [
          Icon(icon, size: res.ic(17), color: AppColors.appBarMuted),
          SizedBox(width: res.dp(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: res.sp(13), fontWeight: FontWeight.w600)),
                SizedBox(height: res.vp(1)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: res.sp(10.5), color: AppColors.textFaint)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ??
          EdgeInsets.symmetric(vertical: context.r.vp(10)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }

  Widget _generateButton() {
    final ready = _sceneCount > 0 && !_working;
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
        ready ? 'Generate video' : 'Type a script to start',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: res.sp(14), fontWeight: FontWeight.w700),
      ),
      onPressed: ready ? _generate : null,
    );
  }

  Widget _progressOverlay() {
    final p = _progress;
    final res = context.r;
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.background.withValues(alpha: 0.92),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: res.gutter + res.dp(16),
              vertical: res.vp(20),
            ),
            child: ContentBox(
              maxWidth: 480,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: res.dp(34),
                  height: res.dp(34),
                  child: const CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.accent),
                ),
                SizedBox(height: res.vp(18)),
                Text(
                  p?.message ?? 'Building your video',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: res.sp(13.5), fontWeight: FontWeight.w600),
                ),
                SizedBox(height: res.vp(12)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p == null || p.total == 0 ? null : p.fraction,
                    minHeight: 5,
                  ),
                ),
                SizedBox(height: res.vp(10)),
                Text(
                  _narrate
                      ? 'Recording narration takes a moment per scene.'
                      : 'Painting each scene…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: res.sp(11), color: AppColors.textFaint),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- actions

  Future<void> _loadVoices() async {
    final voices = await TtsService.instance.voices();
    // The service picks up whatever the user chose last, falling back to the
    // device's own language — never just the first entry, which is how an
    // English script ended up narrated in Arabic.
    final chosen = await TtsService.instance.defaultVoice(voices);
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voice = chosen;
      _voicesLoaded = true;
    });
  }

  Future<void> _previewVoice() async {
    final sample = TextToVideoService.splitScenes(_script.text).firstOrNull;
    // Same voice and speed the render will use, or the preview would be
    // reassuring about a voice that never reaches the video.
    await TtsService.instance.preview(
      sample ?? 'This is how your narration will sound.',
      voice: _voice,
      rate: _rate,
    );
  }

  Future<void> _generate() async {
    setState(() {
      _working = true;
      _progress = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final project = await TextToVideoService.instance.generate(
        _request,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      // A voice with no data on the device synthesises nothing, and a silent
      // video is not something to discover after exporting it.
      if (_narrate && project.audios.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              'Narration could not be recorded with this voice. Pick another '
              'voice, or install its voice data in Android settings.'),
          duration: Duration(seconds: 6),
        ));
      }
      Navigator.pop<Project>(context, project);
    } on TextToVideoException catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    }
  }
}
