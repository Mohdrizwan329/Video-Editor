import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../data/services/caption_service.dart';
import '../../../data/services/clip_operations.dart';
import '../../../data/services/tts_service.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';
import '../../widgets/app_slider.dart';

/// Text-to-speech: type a line, pick a device voice, drop the result on the
/// timeline as narration.
class TtsPanel extends StatefulWidget {
  const TtsPanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<TtsPanel> createState() => _TtsPanelState();
}

class _TtsPanelState extends State<TtsPanel> {
  final TextEditingController _text = TextEditingController();
  final TtsService _tts = TtsService.instance;

  List<TtsVoice> _voices = const [];
  TtsVoice? _voice;
  double _rate = 0.5;
  double _pitch = 1.0;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  @override
  void dispose() {
    _text.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    final voices = await _tts.voices();
    // Whatever the user chose last, else a voice matching the device locale.
    final chosen = await _tts.defaultVoice(voices);
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voice = chosen;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Text to speech',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      child: PanelBody(
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: TextField(
                      controller: _text,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'What should the narrator say?',
                        filled: true,
                        fillColor: AppColors.surfaceHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_voices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        'No speech voices are installed on this device. '
                        'Add one in the system settings.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.warning),
                      ),
                    )
                  else
                    _voicePicker(),
                  AppSlider(
                    label: 'Speed',
                    icon: Icons.speed,
                    value: _rate,
                    min: 0.2,
                    max: 1.0,
                    defaultValue: 0.5,
                    format: (v) => v.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _rate = v),
                  ),
                  AppSlider(
                    label: 'Pitch',
                    icon: Icons.tune,
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    defaultValue: 1.0,
                    format: (v) => v.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _pitch = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              foregroundColor: AppColors.text,
                              side: const BorderSide(
                                  color: AppColors.divider)),
                          icon: const Icon(Icons.volume_up, size: 16),
                          label: const Text('Preview'),
                          onPressed: _text.text.trim().isEmpty
                              ? null
                              : () => _tts.preview(
                                    _text.text,
                                    voice: _voice,
                                    rate: _rate,
                                    pitch: _pitch,
                                  ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.onAccent,
                              minimumSize: const Size(0, 38),
                            ),
                            icon: _working
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.8,
                                        color: Colors.black),
                                  )
                                : const Icon(Icons.add, size: 17),
                            label: Text(_working ? 'Building…' : 'Add to timeline'),
                            onPressed:
                                _working || _text.text.trim().isEmpty
                                    ? null
                                    : _generate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _voicePicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          const Text('Voice',
              style: TextStyle(fontSize: 11, color: AppColors.textDim)),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
                  // `style` paints the open menu, which now carries the bar's
                  // fill; the closed field still sits on the light panel, so
                  // it is rebuilt in the page's own ink.
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.onAppBar),
                  selectedItemBuilder: (_) => _voices
                      .map((v) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text('${v.locale} · ${v.shortLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.text)),
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
                    _tts.rememberVoice(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    setState(() => _working = true);
    final path = await _tts.synthesize(
      _text.text,
      voice: _voice,
      rate: _rate,
      pitch: _pitch,
    );
    if (!mounted) return;
    if (path == null) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The speech engine produced no audio')));
      return;
    }
    final layer = await widget.editor.addAudio(path,
        kind: AudioKind.voiceover, title: _shortTitle());
    if (layer != null) {
      final wave = await ClipOperations.waveform(path);
      if (wave.isNotEmpty && mounted) {
        widget.editor.updateLayer<AudioLayer>(layer, (a) => a.waveform = wave,
            record: false);
      }
    }
    if (mounted) setState(() => _working = false);
  }

  String _shortTitle() {
    final t = _text.text.trim().replaceAll('\n', ' ');
    return t.length <= 24 ? t : '${t.substring(0, 24)}…';
  }
}

/// Auto-captions plus SRT import and export.
class CaptionPanel extends StatefulWidget {
  const CaptionPanel({
    super.key,
    required this.editor,
    required this.onClose,
  });

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<CaptionPanel> createState() => _CaptionPanelState();
}

class _CaptionPanelState extends State<CaptionPanel> {
  CaptionModel _model = CaptionModel.base;
  CaptionProgress? _progress;
  bool _working = false;
  bool? _modelReady;

  EditorController get _e => widget.editor;

  int get _captionCount =>
      _e.project.texts.where((t) => t.isCaption).length;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final ready = await CaptionService.instance.isModelReady(_model);
    if (mounted) setState(() => _modelReady = ready);
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Captions',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      onReset: _captionCount > 0 ? _clearCaptions : null,
      child: PanelBody(
        child: _working ? _progressView() : _idleView(),
      ),
    );
  }

  Widget _progressView() {
    final p = _progress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              value: (p?.value ?? -1) < 0 ? null : p!.value,
              strokeWidth: 3,
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
          const SizedBox(height: 14),
          Text(p?.stage ?? 'Working',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Runs on device — no upload',
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
        ],
      ),
    );
  }

  Widget _idleView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Recognition model',
              style: TextStyle(fontSize: 11, color: AppColors.textDim)),
        ),
        const SizedBox(height: 6),
        ChipStrip(
          labels: CaptionModel.values
              .map((m) => '${m.label} ${m.size}')
              .toList(),
          selectedIndex: CaptionModel.values.indexOf(_model),
          onSelected: (i) {
            setState(() {
              _model = CaptionModel.values[i];
              _modelReady = null;
            });
            _checkModel();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            _modelReady == null
                ? 'Checking for the model…'
                : _modelReady!
                    ? 'Model ready on this device.'
                    : 'The ${_model.label} model (${_model.size}) will be '
                        'downloaded once before the first run.',
            style: TextStyle(
              fontSize: 10.5,
              color: _modelReady == false
                  ? AppColors.warning
                  : AppColors.textFaint,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              minimumSize: const Size.fromHeight(42),
            ),
            icon: const Icon(Icons.closed_caption, size: 18),
            label: const Text('Auto-generate captions',
                style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: _e.project.clips.isEmpty ? null : _autoCaption,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: _outlined,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Import SRT'),
                  onPressed: _importSrt,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: _outlined,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Export SRT'),
                  onPressed: _captionCount == 0 ? null : _exportSrt,
                ),
              ),
            ],
          ),
        ),
        if (_captionCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text('$_captionCount caption lines on the timeline',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textDim)),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }

  ButtonStyle get _outlined => OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.divider),
      );

  /// Transcribe the loudest source available: a voice-over lane if there is
  /// one, otherwise the first clip's own audio.
  String? _bestAudioSource() {
    final voice = _e.project.audios
        .where((a) => a.kind == AudioKind.voiceover)
        .firstOrNull;
    if (voice != null) return voice.path;
    final extracted = _e.project.audios
        .where((a) => a.kind == AudioKind.extracted)
        .firstOrNull;
    if (extracted != null) return extracted.path;
    final clip = _e.project.clips
        .where((c) => c.hasAudio && !c.isImage)
        .firstOrNull;
    return clip?.path;
  }

  Future<void> _autoCaption() async {
    final source = _bestAudioSource();
    if (source == null) {
      _toast('Nothing with audio to transcribe');
      return;
    }
    if (_modelReady == false) {
      final go = await _confirmDownload();
      if (go != true) return;
      setState(() {
        _working = true;
        _progress = const CaptionProgress(
            stage: 'Downloading model', value: -1);
      });
      final ok = await CaptionService.instance.downloadModel(_model);
      if (!mounted) return;
      if (!ok) {
        setState(() => _working = false);
        _toast('Model download failed');
        return;
      }
      setState(() => _modelReady = true);
    }

    setState(() {
      _working = true;
      _progress = const CaptionProgress(stage: 'Preparing', value: -1);
    });

    final lines = await CaptionService.instance.transcribe(
      source,
      model: _model,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() => _working = false);

    if (lines.isEmpty) {
      _toast('No speech was recognised');
      return;
    }
    _applyLines(lines);
    _toast('${lines.length} caption lines added');
  }

  Future<bool?> _confirmDownload() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Download model?'),
          content: Text(
            'The ${_model.label} speech model is about ${_model.size}. '
            'It downloads once and then works offline.',
          ),
          actions: [
            TextButton(
                style: AppTheme.outlinedAction(),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                style: AppTheme.outlinedAction(),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Download')),
          ],
        ),
      );

  void _applyLines(List<CaptionLine> lines) {
    final wrapped = CaptionService.wrap(lines);
    final layers = CaptionService.toLayers(wrapped);
    _e.replaceCaptions(layers);
    setState(() {});
  }

  Future<void> _importSrt() async {
    final raw = await _e.readSrtFile();
    if (raw == null) return;
    final lines = CaptionService.parseSrt(raw);
    if (lines.isEmpty) {
      _toast('No caption blocks found in that file');
      return;
    }
    _applyLines(lines);
    _toast('${lines.length} lines imported');
  }

  Future<void> _exportSrt() async {
    final lines = _e.project.texts
        .where((t) => t.isCaption)
        .map((t) => CaptionLine(start: t.start, end: t.end, text: t.text))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final path =
        await CaptionService.writeSrt(lines, _e.project.name);
    _toast(path == null ? 'Could not write the file' : 'Saved to $path');
  }

  void _clearCaptions() {
    _e.clearCaptions();
    setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12.5)),
      ));
  }
}
