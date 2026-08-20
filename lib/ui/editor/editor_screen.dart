import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/enums.dart';
import '../../data/models/layers.dart';
import '../../data/services/clip_operations.dart';
import '../../data/services/media_library.dart';
import '../../data/models/project.dart';
import '../../data/models/template.dart';
import '../../state/editor_controller.dart';
import '../../state/preview_engine.dart';
import '../export/export_screen.dart';
import '../picker/media_picker_screen.dart';
import 'panels/animation_panel.dart';
import 'panels/audio_panel.dart';
import 'panels/canvas_panels.dart';
import 'panels/clip_panels.dart';
import 'panels/color_panels.dart';
import 'panels/effect_panels.dart';
import 'panels/keyframe_panel.dart';
import 'panels/sound_panel.dart';
import 'panels/speech_panels.dart';
import 'panels/sticker_panel.dart';
import 'panels/text_panel.dart';
import 'panels/voiceover_panel.dart';
import 'panels/watermark_panel.dart';
import 'preview/preview_stage.dart';
import 'timeline/timeline_view.dart';
import 'toolbar/editor_toolbar.dart';
import '../widgets/panel_shell.dart';

/// Which property sheet is currently docked above the toolbar.
enum _Panel {
  none,
  speed,
  volume,
  filter,
  adjust,
  crop,
  duration,
  transition,
  ratio,
  background,
  watermark,
  text,
  stickerPicker,
  stickerStyle,
  overlay,
  audio,
  masterVolume,
  animation,
  voiceOver,
  mask,
  chroma,
  keyframe,
  blend,
  soundLibrary,
  textToSpeech,
  captions,
}

/// The editing surface: preview on top, timeline in the middle, contextual
/// tools at the bottom.
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.project,
    this.initialMedia,
    this.template,
  });

  final Project project;
  final List<String>? initialMedia;

  /// When set, the initial media is laid out by this template instead of
  /// being appended to the timeline.
  final VideoTemplate? template;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController _editor = EditorController(widget.project);
  late final PreviewEngine _engine = PreviewEngine(_editor);

  _Panel _panel = _Panel.none;
  int _transitionIndex = 0;

  @override
  void initState() {
    super.initState();
    final media = widget.initialMedia;
    if (media != null && media.isNotEmpty) {
      final template = widget.template;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (template != null) {
          _editor.applyTemplate(template, media);
        } else {
          _import(media);
        }
      });
    }
  }

  @override
  void dispose() {
    _editor.saveNow();
    _engine.dispose();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _import(List<String> paths) async {
    await _editor.addMedia(paths);
    await _editor.saveNow();
  }

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _editor),
        ChangeNotifierProvider.value(value: _engine),
      ],
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          await _engine.pause();
          await _editor.saveNow();
          navigator.pop();
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          // Pre-Android-15 devices still paint the navigation bar themselves;
          // this screen ends in the toolbar/panel, so it takes their fill.
          value: const SystemUiOverlayStyle(
            systemNavigationBarColor: AppColors.surface,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: AppColors.surface,
            appBar: _topBar(),
            // bottom: false — EditorToolbar and PanelShell each carry their own
            // SafeArea(top: false), so their fill runs under the nav bar.
            body: SafeArea(
              bottom: false,
              child: AnimatedBuilder(
                animation: _editor,
                // Every strip below is measured against the room actually
                // left, so the editor fits a 320pt phone, a phone turned on
                // its side, a tablet and a resizable desktop window without a
                // single overflow stripe.
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) =>
                      _layout(context, constraints),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// True once the window is wide enough to put the tools beside the preview
  /// instead of under it — desktop, web, and landscape tablets.
  bool _isWideLayout(BoxConstraints c) =>
      c.maxWidth >= 1000 && c.maxWidth > c.maxHeight;

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final r = context.r;
    final wide = _isWideLayout(constraints);
    final timelineHeight = _timelineHeight();
    final tools = _panel == _Panel.none
        ? EditorToolbar(
            editor: _editor,
            onAction: _handle,
            axis: wide ? Axis.vertical : Axis.horizontal,
          )
        : _buildPanel();

    final preview = Padding(
      padding: EdgeInsets.symmetric(horizontal: r.dp(12), vertical: r.vp(6)),
      child: PreviewStage(watermarkFocus: _panel == _Panel.watermark),
    );

    final timeline = Container(
      color: AppColors.timelineBg,
      child: TimelineView(
        editor: _editor,
        onAddMedia: _pickMoreMedia,
        onTransitionTap: (i) {
          _editor.selectClip(i);
          setState(() {
            _transitionIndex = i;
            _panel = _Panel.transition;
          });
        },
      ),
    );

    final header = TimelineHeader(
      editor: _editor,
      onPlayPause: _engine.toggle,
      onUndo: _editor.undo,
      onRedo: _editor.redo,
      onFullscreen: _openFullscreen,
      onSnapToBeat: () {
        if (!_editor.snapToNearestBeat()) _toast('No beat nearby');
      },
      onAddKeyframe: () {
        if (_editor.hasKeyframeAtPlayhead) {
          _editor.removeKeyframeAtPlayhead();
        } else if (!_editor.addKeyframeAtPlayhead()) {
          _toast('Select a clip or layer first');
        }
      },
    );

    // What the strips below the preview will take, so the preview knows what
    // is left and the whole column knows whether it still fits.
    final headerHeight = math.max(r.vp(34), 32);
    final toolsHeight = _panel == _Panel.none
        ? EditorToolbar.heightFor(context, selected: !_editor.selection.isEmpty)
        : r.height * (r.isShort ? 0.42 : 0.5);

    if (wide) {
      // The rail holds two or three columns of tools on a laptop and more on
      // a large monitor, while the timeline keeps the full width underneath.
      // Its floor is a phone's width, because that is what the panels were
      // drawn for — squeezing it is what clipped their control rows.
      final rail = (constraints.maxWidth * 0.28).clamp(320.0, 420.0);
      return _fit(
        constraints,
        headerHeight + timelineHeight + _kMinPreviewHeight,
        Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: preview),
                  SizedBox(
                    width: rail,
                    child: _panel == _Panel.none
                        ? tools
                        : SingleChildScrollView(
                            // A panel keeps the height it was drawn for; the
                            // rail scrolls if the window cannot show all of it.
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight,
                              ),
                              child: tools,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            header,
            SizedBox(height: timelineHeight, child: timeline),
            if (_editor.isBusy) _busyBar(),
          ],
        ),
      );
    }

    return _fit(
      constraints,
      headerHeight + timelineHeight + toolsHeight + _kMinPreviewHeight,
      Column(
        children: [
          Expanded(child: preview),
          header,
          SizedBox(height: timelineHeight, child: timeline),
          tools,
          if (_editor.isBusy) _busyBar(),
        ],
      ),
    );
  }

  /// The preview may be squeezed, but not to nothing.
  static const double _kMinPreviewHeight = 88;

  /// Hands the column the room it needs. When the window genuinely cannot
  /// give it — a browser window dragged down to a sliver, a phone in
  /// landscape with a tall panel open — the editor scrolls instead of
  /// painting an overflow stripe over the timeline.
  Widget _fit(BoxConstraints constraints, double needed, Widget column) {
    if (!constraints.maxHeight.isFinite || constraints.maxHeight >= needed) {
      return column;
    }
    return SingleChildScrollView(
      child: SizedBox(height: needed, child: column),
    );
  }

  /// How tall the timeline has to be for the lanes it is showing. Its rows
  /// are a fixed density — a ruler, a 56pt video track, 26pt lanes — so this
  /// is not scaled to the window: shrinking the box would only clip a lane.
  /// When the window cannot spare the room, [_fit] scrolls instead.
  double _timelineHeight() {
    final p = _editor.project;
    var h = 118.0;
    if (_editor.keyframeTarget?.$1.hasKeyframes ?? false) h += 16;
    if (p.overlays.isNotEmpty) h += 30;
    if (p.texts.isNotEmpty) h += 30;
    if (p.stickers.isNotEmpty) h += 30;
    if (p.audios.isNotEmpty) h += 30;
    return h.clamp(118.0, 240.0);
  }

  /// The bar rebuilds with the editor so a rename or ratio change shows up
  /// immediately — it now sits outside the body's [AnimatedBuilder].
  PreferredSizeWidget _topBar() {
    // A phone on its side has little height to spare; the bar gives some of
    // it back rather than eating the preview.
    final height = context.r.isShort ? 46.0 : kAppBarHeight;
    return PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: AnimatedBuilder(
        animation: _editor,
        builder: (context, _) => _appBarContent(height),
      ),
    );
  }

  AppBar _appBarContent(double height) {
    final r = context.r;
    return AppBar(
      toolbarHeight: height,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: r.ic(21)),
        onPressed: () async {
          final navigator = Navigator.of(context);
          await _engine.pause();
          await _editor.saveNow();
          navigator.pop();
        },
      ),
      title: GestureDetector(
        onTap: _renameProject,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _editor.project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(13.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: r.dp(5)),
            Icon(Icons.edit, size: r.ic(12), color: AppColors.onAppBarDim),
          ],
        ),
      ),
      actions: [
        _ratioBadge(),
        SizedBox(width: r.dp(6)),
        Padding(
          padding: EdgeInsets.only(right: r.dp(10)),
          child: InkWell(
            onTap: _export,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              height: math.min(r.dp(33), height - 12),
              padding: EdgeInsets.symmetric(horizontal: r.dp(13)),
              alignment: Alignment.center,
              // The button sits inside the dark bar, so it inverts the pair
              // the rest of the app uses rather than repeating the bar fill.
              decoration: BoxDecoration(
                color: AppColors.onAppBar,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_upload_outlined,
                    size: r.ic(15),
                    color: AppColors.appBar,
                  ),
                  SizedBox(width: r.dp(6)),
                  Text(
                    'Export',
                    style: TextStyle(
                      fontSize: r.sp(12),
                      fontWeight: FontWeight.w800,
                      color: AppColors.appBar,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ratioBadge() {
    final r = context.r;
    return GestureDetector(
      onTap: () => setState(() => _panel = _Panel.ratio),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: r.dp(9), vertical: r.dp(4)),
        // Tinted off the bar's own foreground, not off a hue — the hues are
        // tuned for the light page and go muddy on the dark bar.
        decoration: BoxDecoration(
          color: AppColors.onAppBar.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.onAppBar.withValues(alpha: 0.24)),
        ),
        child: Text(
          _editor.project.ratio.label,
          style: TextStyle(
            fontSize: r.sp(10.5),
            fontWeight: FontWeight.w700,
            color: AppColors.onAppBar,
          ),
        ),
      ),
    );
  }

  Widget _busyBar() {
    final r = context.r;
    return Container(
      color: AppColors.surfaceHigh,
      // Sits below the toolbar when it shows, so it is the strip that meets
      // the navigation bar and has to carry the inset.
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: math.max(r.vp(30), 26),
          child: Row(
            children: [
              SizedBox(width: r.dp(14)),
              SizedBox(
                width: r.dp(13),
                height: r.dp(13),
                child: const CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: AppColors.accent,
                ),
              ),
              SizedBox(width: r.dp(10)),
              Expanded(
                child: Text(
                  _editor.busyMessage ?? 'Working…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: r.sp(11.5),
                    color: AppColors.textDim,
                  ),
                ),
              ),
              SizedBox(width: r.dp(10)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- panels

  void _closePanel() => setState(() => _panel = _Panel.none);

  Widget _buildPanel() {
    final index = _editor.selectedClipIndex;
    switch (_panel) {
      case _Panel.speed:
        return _clipPanel(
          index,
          (i) => SpeedPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.volume:
        return _clipPanel(
          index,
          (i) => VolumePanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.filter:
        return _clipPanel(
          index,
          (i) => FilterPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.adjust:
        return _clipPanel(
          index,
          (i) => AdjustPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.crop:
        return _clipPanel(
          index,
          (i) => CropPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.duration:
        return _clipPanel(
          index,
          (i) => DurationPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.transition:
        final i = _transitionIndex.clamp(0, _editor.project.clips.length - 2);
        if (_editor.project.clips.length < 2) {
          return _emptyPanel('Add a second clip first');
        }
        return TransitionPanel(editor: _editor, index: i, onClose: _closePanel);
      case _Panel.ratio:
        return RatioPanel(editor: _editor, onClose: _closePanel);
      case _Panel.background:
        return BackgroundPanel(editor: _editor, onClose: _closePanel);
      case _Panel.watermark:
        return WatermarkPanel(editor: _editor, onClose: _closePanel);
      case _Panel.masterVolume:
        return MasterVolumePanel(editor: _editor, onClose: _closePanel);
      case _Panel.voiceOver:
        return VoiceOverPanel(
          editor: _editor,
          engine: _engine,
          onClose: _closePanel,
        );
      case _Panel.keyframe:
        return KeyframePanel(editor: _editor, onClose: _closePanel);
      case _Panel.soundLibrary:
        return SoundPanel(editor: _editor, onClose: _closePanel);
      case _Panel.textToSpeech:
        return TtsPanel(editor: _editor, onClose: _closePanel);
      case _Panel.captions:
        return CaptionPanel(editor: _editor, onClose: _closePanel);
      case _Panel.mask:
        final overlay = _editor.selectedOverlay;
        if (overlay == null && index < 0) return _emptyPanel('Select a clip');
        return MaskPanel(
          editor: _editor,
          onClose: _closePanel,
          clipIndex: overlay == null ? index : null,
          overlay: overlay,
        );
      case _Panel.chroma:
        final overlay = _editor.selectedOverlay;
        if (overlay == null && index < 0) return _emptyPanel('Select a clip');
        return ChromaPanel(
          editor: _editor,
          onClose: _closePanel,
          clipIndex: overlay == null ? index : null,
          overlay: overlay,
        );
      case _Panel.blend:
        final overlay = _editor.selectedOverlay;
        if (overlay == null) return _emptyPanel('Select an overlay');
        return BlendPanel(
          editor: _editor,
          layer: overlay,
          onClose: _closePanel,
        );
      case _Panel.stickerPicker:
        return StickerPickerPanel(editor: _editor, onClose: _closePanel);
      case _Panel.text:
        final layer = _editor.selectedText;
        if (layer == null) return _emptyPanel('Select a text layer');
        return TextPanel(editor: _editor, layer: layer, onClose: _closePanel);
      case _Panel.stickerStyle:
        final layer = _editor.selectedSticker;
        if (layer == null) return _emptyPanel('Select a sticker');
        return StickerPropertiesPanel(
          editor: _editor,
          layer: layer,
          onClose: _closePanel,
        );
      case _Panel.overlay:
        final layer = _editor.selectedOverlay;
        if (layer == null) return _emptyPanel('Select an overlay');
        return OverlayPanel(
          editor: _editor,
          layer: layer,
          onClose: _closePanel,
        );
      case _Panel.audio:
        final layer = _editor.selectedAudio;
        if (layer == null) return _emptyPanel('Select an audio clip');
        return AudioPanel(editor: _editor, layer: layer, onClose: _closePanel);
      case _Panel.animation:
        return _animationPanel();
      case _Panel.none:
        return const SizedBox.shrink();
    }
  }

  Widget _clipPanel(int index, Widget Function(int) build) {
    if (index < 0 || index >= _editor.project.clips.length) {
      return _emptyPanel('Select a clip');
    }
    return build(index);
  }

  Widget _emptyPanel(String message) {
    return PanelShell(
      title: 'Nothing selected',
      onClose: _closePanel,
      onConfirm: _closePanel,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.r.dp(16),
          vertical: context.r.vp(26),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: context.r.sp(12),
            color: AppColors.textDim,
          ),
        ),
      ),
    );
  }

  Widget _animationPanel() {
    final text = _editor.selectedText;
    final sticker = _editor.selectedSticker;
    final overlay = _editor.selectedOverlay;

    LayerAnimation animIn;
    LayerAnimation animOut;
    Duration duration;
    void Function(LayerAnimation) onIn;
    void Function(LayerAnimation) onOut;
    void Function(Duration) onDuration;

    if (text != null) {
      animIn = text.animationIn;
      animOut = text.animationOut;
      duration = text.animationDuration;
      onIn = (a) =>
          _editor.updateLayer<TextLayer>(text, (l) => l.animationIn = a);
      onOut = (a) =>
          _editor.updateLayer<TextLayer>(text, (l) => l.animationOut = a);
      onDuration = (d) =>
          _editor.updateLayer<TextLayer>(text, (l) => l.animationDuration = d);
    } else if (sticker != null) {
      animIn = sticker.animationIn;
      animOut = sticker.animationOut;
      duration = sticker.animationDuration;
      onIn = (a) =>
          _editor.updateLayer<StickerLayer>(sticker, (l) => l.animationIn = a);
      onOut = (a) =>
          _editor.updateLayer<StickerLayer>(sticker, (l) => l.animationOut = a);
      onDuration = (d) => _editor.updateLayer<StickerLayer>(
        sticker,
        (l) => l.animationDuration = d,
      );
    } else if (overlay != null) {
      animIn = overlay.animationIn;
      animOut = overlay.animationOut;
      duration = overlay.animationDuration;
      onIn = (a) =>
          _editor.updateLayer<OverlayLayer>(overlay, (l) => l.animationIn = a);
      onOut = (a) =>
          _editor.updateLayer<OverlayLayer>(overlay, (l) => l.animationOut = a);
      onDuration = (d) => _editor.updateLayer<OverlayLayer>(
        overlay,
        (l) => l.animationDuration = d,
      );
    } else {
      return _emptyPanel('Select a layer to animate');
    }

    return PanelShell(
      title: 'Animation',
      onClose: _closePanel,
      onConfirm: _closePanel,
      child: SizedBox(
        height: 180,
        child: AnimationPicker(
          animationIn: animIn,
          animationOut: animOut,
          duration: duration,
          onIn: onIn,
          onOut: onOut,
          onDuration: onDuration,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- actions

  Future<void> _handle(ToolAction action) async {
    await _engine.pause();
    final index = _editor.selectedClipIndex;
    final layer = _editor.selectedLayer;

    switch (action) {
      case ToolAction.addMedia:
        await _pickMoreMedia();
      case ToolAction.audio:
        await _addAudio();
      case ToolAction.soundLibrary:
        setState(() => _panel = _Panel.soundLibrary);
      case ToolAction.textToSpeech:
        setState(() => _panel = _Panel.textToSpeech);
      case ToolAction.captions:
        setState(() => _panel = _Panel.captions);
      case ToolAction.text:
        _editor.addText();
        setState(() => _panel = _Panel.text);
      case ToolAction.sticker:
        setState(() => _panel = _Panel.stickerPicker);
      case ToolAction.overlay:
        await _addOverlay();
      case ToolAction.ratio:
        setState(() => _panel = _Panel.ratio);
      case ToolAction.background:
        setState(() => _panel = _Panel.background);
      case ToolAction.watermark:
        setState(() => _panel = _Panel.watermark);
      case ToolAction.masterVolume:
        setState(() => _panel = _Panel.masterVolume);
      case ToolAction.voiceOver:
        setState(() => _panel = _Panel.voiceOver);
      case ToolAction.keyframe:
        setState(() => _panel = _Panel.keyframe);
      case ToolAction.mask:
        setState(() => _panel = _Panel.mask);
      case ToolAction.chroma:
        setState(() => _panel = _Panel.chroma);
      case ToolAction.blend:
        setState(() => _panel = _Panel.blend);
      case ToolAction.stabilize:
        if (index >= 0) {
          _editor.updateClip(index, (c) => c.stabilize = !c.stabilize);
          _toast(
            _editor.project.clips[index].stabilize
                ? 'Stabilization on — applied at export'
                : 'Stabilization off',
          );
        }

      case ToolAction.split:
        if (!_editor.splitAtPlayhead()) {
          _toast('Move the playhead inside a clip to split');
        }
      case ToolAction.speed:
        setState(() => _panel = _Panel.speed);
      case ToolAction.volume:
        setState(() => _panel = _Panel.volume);
      case ToolAction.filter:
        setState(() => _panel = _Panel.filter);
      case ToolAction.adjust:
        setState(() => _panel = _Panel.adjust);
      case ToolAction.crop:
        setState(() => _panel = _Panel.crop);
      case ToolAction.duration:
        setState(() => _panel = _Panel.duration);
      case ToolAction.transition:
        if (index < 0 || index >= _editor.project.clips.length - 1) {
          _toast('Pick a clip that has one after it');
        } else {
          setState(() {
            _transitionIndex = index;
            _panel = _Panel.transition;
          });
        }
      case ToolAction.rotate:
        if (index >= 0) {
          _editor.updateClip(
            index,
            (c) => c.rotation = (c.rotation + 90) % 360,
          );
        }
      case ToolAction.mirror:
        if (index >= 0) {
          _editor.updateClip(index, (c) => c.mirrored = !c.mirrored);
        }
      case ToolAction.reverse:
        await _reverseClip(index);
      case ToolAction.freeze:
        await _freezeFrame(index);
      case ToolAction.extractAudio:
        await _extractAudio(index);
      case ToolAction.replace:
        await _replaceClip(index);
      case ToolAction.duplicate:
        _editor.duplicateClip(index);
      case ToolAction.delete:
        _editor.deleteClip(index);
        _closePanel();

      case ToolAction.editText:
        setState(() => _panel = _Panel.text);
      case ToolAction.editSticker:
        setState(() => _panel = _Panel.stickerStyle);
      case ToolAction.editOverlay:
        setState(() => _panel = _Panel.overlay);
      case ToolAction.editAudio:
        setState(() => _panel = _Panel.audio);
      case ToolAction.animation:
        setState(() => _panel = _Panel.animation);
      case ToolAction.splitLayer:
        if (layer == null || !_editor.splitLayerAtPlayhead(layer)) {
          _toast('Put the playhead inside the layer to split it');
        }
      case ToolAction.duplicateLayer:
        if (layer != null) _editor.duplicateLayer(layer);
      case ToolAction.deleteLayer:
        if (layer != null) _editor.deleteLayer(layer);
        _closePanel();
    }
  }

  Future<void> _pickMoreMedia() async {
    final navigator = Navigator.of(context);
    await _engine.pause();
    final paths = await navigator.push<List<String>>(
      MaterialPageRoute(builder: (_) => const MediaPickerScreen()),
    );
    if (paths == null || paths.isEmpty) return;
    await _import(paths);
  }

  Future<void> _addOverlay() async {
    final navigator = Navigator.of(context);
    await _engine.pause();
    final paths = await navigator.push<List<String>>(
      MaterialPageRoute(
        builder: (_) =>
            const MediaPickerScreen(title: 'Overlay', maxSelection: 1),
      ),
    );
    if (paths == null || paths.isEmpty) return;
    await _editor.addOverlay(paths.first);
    if (mounted) setState(() => _panel = _Panel.overlay);
  }

  Future<void> _addAudio() async {
    final picked = await MediaLibrary.instance.pickAudio();
    if (picked.isEmpty) return;
    final path = picked.first.filePath;
    if (path == null) return;
    final layer = await _editor.addAudio(path, title: picked.first.title);
    if (layer != null) {
      _editor.setBusy('Analysing track');
      final wave = await ClipOperations.waveform(path);
      if (wave.isNotEmpty) {
        _editor.updateLayer<AudioLayer>(
          layer,
          (a) => a.waveform = wave,
          record: false,
        );
      }
      final beats = await ClipOperations.detectBeats(path);
      if (beats.isNotEmpty) {
        _editor.updateLayer<AudioLayer>(
          layer,
          (a) => a.beats = beats,
          record: false,
        );
      }
      _editor.setBusy(null);
      if (beats.isNotEmpty) _toast('${beats.length} beats detected');
    }
    if (mounted) setState(() => _panel = _Panel.audio);
  }

  Future<void> _reverseClip(int index) async {
    if (index < 0) return;
    final clip = _editor.project.clips[index];
    if (clip.isImage) {
      _toast('Images cannot be reversed');
      return;
    }
    _editor.setBusy('Reversing clip…');
    final path = await ClipOperations.reverse(clip);
    _editor.setBusy(null);
    if (path == null) {
      _toast('Reverse failed');
      return;
    }
    _editor.updateClip(index, (c) {
      c.path = path;
      c.trimStart = Duration.zero;
      c.trimEnd = c.trimmedDuration;
      c.sourceDuration = c.trimEnd;
      c.reversed = !c.reversed;
    });
  }

  Future<void> _freezeFrame(int index) async {
    if (index < 0) return;
    final clip = _editor.project.clips[index];
    final local = _editor.position.value - _editor.project.clipStart(index);
    _editor.setBusy('Freezing frame…');
    final path = await ClipOperations.freezeFrame(
      clip,
      clip.sourcePositionFor(local),
    );
    _editor.setBusy(null);
    if (path == null) {
      _toast('Could not capture the frame');
      return;
    }
    await _editor.freezeFrame(index, path);
  }

  Future<void> _extractAudio(int index) async {
    if (index < 0) return;
    final clip = _editor.project.clips[index];
    if (!clip.hasAudio || clip.isImage) {
      _toast('This clip has no audio');
      return;
    }
    _editor.setBusy('Extracting audio…');
    final path = await ClipOperations.extractAudio(clip);
    _editor.setBusy(null);
    if (path == null) {
      _toast('Extract failed');
      return;
    }
    final start = _editor.project.clipStart(index);
    _editor.seek(start);
    final layer = await _editor.addAudio(
      path,
      kind: AudioKind.extracted,
      title: 'Clip ${index + 1} audio',
    );
    if (layer != null) {
      _editor.updateClip(index, (c) => c.volume = 0);
    }
  }

  Future<void> _replaceClip(int index) async {
    if (index < 0) return;
    final paths = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const MediaPickerScreen(title: 'Replace clip', maxSelection: 1),
      ),
    );
    if (paths == null || paths.isEmpty) return;
    final at = _editor.project.clipStart(index);
    _editor.deleteClip(index);
    _editor.seek(at);
    await _editor.addMedia([paths.first], at: index);
  }

  Future<void> _export() async {
    if (_editor.project.clips.isEmpty) {
      _toast('Add at least one clip first');
      return;
    }
    final navigator = Navigator.of(context);
    await _engine.pause();
    await _editor.saveNow();
    await navigator.push(
      MaterialPageRoute(builder: (_) => ExportScreen(project: _editor.project)),
    );
  }

  void _openFullscreen() {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _editor),
          ChangeNotifierProvider.value(value: _engine),
        ],
        child: _FullscreenPreview(engine: _engine, editor: _editor),
      ),
    );
  }

  Future<void> _renameProject() async {
    final controller = TextEditingController(text: _editor.project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Project name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.onAppBar),
          decoration: AppTheme.dialogField(null),
        ),
        actions: [
          TextButton(
            style: AppTheme.outlinedAction(),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: AppTheme.outlinedAction(),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) _editor.rename(name);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 12.5)),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}

/// Distraction-free playback with a scrub bar.
class _FullscreenPreview extends StatelessWidget {
  const _FullscreenPreview({required this.engine, required this.editor});

  final PreviewEngine engine;
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Distraction-free playback runs on black, bars included.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: r.isShort ? 42 : kAppBarHeight,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: r.ic(24),
                    ),
                    onPressed: () {
                      engine.pause();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
              const Expanded(child: PreviewStage(interactive: false)),
              ValueListenableBuilder<Duration>(
                valueListenable: editor.position,
                builder: (context, t, _) {
                  final total = editor.totalDuration.inMilliseconds.toDouble();
                  return Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: editor.isPlaying,
                        builder: (context, playing, _) => IconButton(
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: r.ic(24),
                          ),
                          onPressed: engine.toggle,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: t.inMilliseconds
                              .clamp(0, total.toInt())
                              .toDouble(),
                          max: total <= 0 ? 1 : total,
                          onChanged: (v) =>
                              engine.seek(Duration(milliseconds: v.round())),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(right: r.dp(14)),
                        child: Text(
                          '${t.inSeconds}s',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: r.sp(11),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: r.vp(8)),
            ],
          ),
        ),
      ),
    );
  }
}
