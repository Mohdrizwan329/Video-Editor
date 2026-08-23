import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/layers.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../data/services/clip_operations.dart';
import '../../../state/editor_controller.dart';
import '../../../state/preview_engine.dart';
import '../../widgets/panel_shell.dart';

/// Records a voice-over from the playhead, playing the timeline back while
/// it captures.
class VoiceOverPanel extends StatefulWidget {
  const VoiceOverPanel({
    super.key,
    required this.editor,
    required this.engine,
    required this.onClose,
  });

  final EditorController editor;
  final PreviewEngine engine;
  final VoidCallback onClose;

  @override
  State<VoiceOverPanel> createState() => _VoiceOverPanelState();
}

class _VoiceOverPanelState extends State<VoiceOverPanel> {
  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;
  bool _permissionDenied = false;
  Duration _startedAt = Duration.zero;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  String? _path;

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _permissionDenied = true);
      return;
    }
    final dir = await ProjectRepository.instance.mediaDir();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _startedAt = widget.editor.position.value;
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );
    // Mute playback so the microphone does not pick the timeline back up.
    widget.engine.setMuted(true);
    await widget.engine.play();
    setState(() {
      _recording = true;
      _path = path;
      _elapsed = Duration.zero;
      _permissionDenied = false;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed = widget.editor.position.value - _startedAt);
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    final path = await _recorder.stop() ?? _path;
    await widget.engine.pause();
    widget.engine.setMuted(false);
    setState(() => _recording = false);
    if (path == null || _elapsed < const Duration(milliseconds: 400)) return;

    widget.editor.seek(_startedAt);
    final layer = await widget.editor.addAudio(
      path,
      kind: AudioKind.voiceover,
      title: 'Voice-over',
    );
    if (layer != null) {
      widget.editor.updateLayer<AudioLayer>(layer, (a) {
        a.duration = _elapsed;
      }, record: false);
      final wave = await ClipOperations.waveform(path);
      if (wave.isNotEmpty && mounted) {
        widget.editor.updateLayer<AudioLayer>(
          layer,
          (a) => a.waveform = wave,
          record: false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Voice-over',
      onClose: () {
        if (_recording) _stop();
        widget.onClose();
      },
      onConfirm: () {
        if (_recording) _stop();
        widget.onClose();
      },
      child: PanelBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_permissionDenied)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Microphone access is off',
                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ),
            GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: _recording ? AppColors.danger : AppColors.surfaceHigh,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _recording ? AppColors.danger : AppColors.divider,
                    width: 2,
                  ),
                ),
                child: Icon(
                  _recording ? Icons.stop : Icons.mic,
                  size: 26,
                  color: _recording ? Colors.white : AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _recording
                  ? 'Recording · ${_elapsed.timecode}'
                  : 'Tap to record from the playhead',
              style: TextStyle(
                fontSize: 12,
                color: _recording ? AppColors.danger : AppColors.textDim,
                fontWeight: _recording ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
