import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/models/enums.dart';
import '../../../data/repositories/music_store.dart';
import '../../../data/services/clip_operations.dart';
import '../../../data/services/media_library.dart';
import '../../../data/services/sound_library.dart';
import '../../../data/models/layers.dart';
import '../../../state/editor_controller.dart';
import '../../widgets/panel_shell.dart';

/// Audio browser: generated beds and effects, plus tracks the user has
/// imported before.
class SoundPanel extends StatefulWidget {
  const SoundPanel({super.key, required this.editor, required this.onClose});

  final EditorController editor;
  final VoidCallback onClose;

  @override
  State<SoundPanel> createState() => _SoundPanelState();
}

class _SoundPanelState extends State<SoundPanel> {
  /// 0 is "My music", the rest map onto the library categories.
  int _tab = 0;
  String? _working;
  List<SavedTrack> _saved = const [];

  List<String> get _tabs => ['My music', ...SoundLibrary.categories];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final tracks = await MusicStore.instance.tracks();
    if (mounted) setState(() => _saved = tracks);
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Audio',
      onClose: widget.onClose,
      onConfirm: widget.onClose,
      trailing: IconButton(
        tooltip: 'Import from device',
        icon: const Icon(Icons.folder_open, size: 19),
        color: AppColors.textDim,
        onPressed: _import,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ChipStrip(
            labels: _tabs,
            selectedIndex: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 8),
          _tab == 0 ? _savedList() : _libraryList(),
        ],
      ),
    );
  }

  Widget _savedList() {
    if (_saved.isEmpty) {
      // Nothing scrolls here either: on a window too short for the whole
      // placeholder, what is cut off is what 'More options' then offers.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 32,
              color: AppColors.textFaint,
            ),
            const SizedBox(height: 10),
            const Text(
              'No imported tracks yet',
              style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tracks you import are remembered here for next time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                minimumSize: const Size(0, 36),
              ),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Import a track'),
              onPressed: _import,
            ),
          ],
        ),
      );
    }
    // A column, not a list: the tracks that do not fit are reached through
    // 'More options', where they are all laid out at once, rather than under
    // a scroll the sheet gives no sign of.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in _saved) ...[
          const SizedBox(height: 6),
          _row(
            leading: const Text('🎵', style: TextStyle(fontSize: 18)),
            title: t.title,
            subtitle: t.duration > Duration.zero ? t.duration.pretty : 'Track',
            busy: _working == t.path,
            onTap: () => _addTrack(t.path, t.title),
            onRemove: () async {
              await MusicStore.instance.forget(t.path);
              await _loadSaved();
            },
          ),
        ],
      ],
    );
  }

  Widget _libraryList() {
    final category = SoundLibrary.categories[_tab - 1];
    final items = SoundLibrary.byCategory(category);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final def in items) ...[
          const SizedBox(height: 6),
          _row(
            leading: Text(
              def.icon.isEmpty ? '🔈' : def.icon,
              style: const TextStyle(fontSize: 18),
            ),
            title: def.name,
            subtitle: def.kind == SoundKind.bed
                ? '${def.duration.inSeconds}s loop · generated'
                : '${def.duration.inMilliseconds} ms · generated',
            busy: _working == def.id,
            onTap: () => _addGenerated(def),
          ),
        ],
      ],
    );
  }

  Widget _row({
    required Widget leading,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
    VoidCallback? onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              SizedBox(width: 26, child: Center(child: leading)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 15),
                  color: AppColors.textFaint,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.accent,
                  ),
                )
              else
                const Icon(
                  Icons.add_circle_outline,
                  size: 19,
                  color: AppColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addGenerated(SoundDef def) async {
    setState(() => _working = def.id);
    final path = await SoundLibrary.instance.resolve(def);
    if (!mounted) return;
    setState(() => _working = null);
    if (path == null) {
      _toast('Could not build ${def.name}');
      return;
    }
    await _addTrack(
      path,
      def.name,
      kind: def.kind == SoundKind.bed ? AudioKind.music : AudioKind.sfx,
      remember: false,
    );
  }

  Future<void> _import() async {
    final picked = await MediaLibrary.instance.pickAudio();
    if (picked.isEmpty) return;
    final path = picked.first.filePath;
    if (path == null) return;
    await _addTrack(path, picked.first.title ?? 'Track');
  }

  Future<void> _addTrack(
    String path,
    String title, {
    AudioKind kind = AudioKind.music,
    bool remember = true,
  }) async {
    setState(() => _working = path);
    final layer = await widget.editor.addAudio(path, kind: kind, title: title);
    if (layer == null) {
      if (mounted) setState(() => _working = null);
      return;
    }
    if (remember) {
      await MusicStore.instance.remember(path, title, layer.sourceDuration);
      await _loadSaved();
    }

    // Waveform and beats only pay off for real music, not a 90 ms click.
    if (layer.sourceDuration > const Duration(seconds: 2)) {
      final wave = await ClipOperations.waveform(path);
      if (wave.isNotEmpty && mounted) {
        widget.editor.updateLayer<AudioLayer>(
          layer,
          (a) => a.waveform = wave,
          record: false,
        );
      }
      if (kind == AudioKind.music) {
        final beats = await ClipOperations.detectBeats(path);
        if (beats.isNotEmpty && mounted) {
          widget.editor.updateLayer<AudioLayer>(
            layer,
            (a) => a.beats = beats,
            record: false,
          );
        }
      }
    }
    if (mounted) setState(() => _working = null);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
