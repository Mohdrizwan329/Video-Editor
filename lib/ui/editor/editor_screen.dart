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
import 'panels/effects_panel.dart';
import 'panels/filter_panel.dart';
import 'panels/effect_panels.dart';
import 'panels/keyframe_panel.dart';
import 'panels/sort_panel.dart';
import 'panels/sound_panel.dart';
import 'panels/speech_panels.dart';
import 'panels/sticker_panel.dart';
import 'panels/text_panel.dart';
import 'panels/voiceover_panel.dart';
import 'panels/watermark_panel.dart';
import 'preview/preview_stage.dart';
import 'timeline/timeline_view.dart';
import 'toolbar/category_bar.dart';
import 'toolbar/editor_toolbar.dart';
import '../widgets/panel_shell.dart';

/// Which property sheet is currently docked above the toolbar.
enum _Panel {
  none,
  speed,
  volume,
  sort,
  colorFilter,
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

  /// Which family of tools the bar along the bottom is pointing at.
  ToolCategory _category = ToolCategory.trim;

  /// Panels whose every control acts on one clip or one layer. They are the
  /// ones that need the playhead kept on what they are editing — see
  /// [_revealSelection].
  static const Set<_Panel> _targetScoped = {
    _Panel.speed,
    _Panel.volume,
    _Panel.filter,
    _Panel.adjust,
    _Panel.crop,
    _Panel.duration,
    _Panel.mask,
    _Panel.chroma,
    _Panel.text,
    _Panel.stickerStyle,
    _Panel.overlay,
    _Panel.audio,
    _Panel.animation,
    _Panel.blend,
    _Panel.keyframe,
  };

  /// The selection the playhead was last brought onto. A slider notifies on
  /// every frame of a drag, so without this the reveal below would re-seek
  /// the preview out from under the user's finger.
  String? _revealedSelection;

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onSelectionChanged);
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
    _editor.removeListener(_onSelectionChanged);
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
    // Read above the Scaffold on purpose: the Scaffold zeroes `viewInsets`
    // for its own body and leaves MediaQuery reporting the whole window, so
    // this is the only place the keyboard's real height is still visible.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
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
                      _layout(context, constraints, keyboardInset),
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

  Widget _layout(
    BuildContext context,
    BoxConstraints constraints,
    double keyboardInset,
  ) {
    final r = context.r;
    final wide = _isWideLayout(constraints);
    final timelineHeight = _timelineHeight();
    final tools = _panel == _Panel.none
        ? EditorToolbar(
            editor: _editor,
            onAction: _handle,
            category: _category,
            axis: wide ? Axis.vertical : Axis.horizontal,
          )
        : KeyedSubtree(key: _panelKey, child: _buildPanel());

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

    // The bar along the very bottom: it decides which set of tools the strip
    // above the timeline is showing. It stands down while a panel is open —
    // the panel is what the bottom of the screen is for then.
    final showBars = _panel == _Panel.none;
    final categoryBar = CategoryBar(
      selected: _category,
      onSelected: (c) {
        // A selected overlay lane takes the strip over with its own tools, so
        // switching family has to let go of it — otherwise the tap looks like
        // it did nothing. A main-track clip stays selected: the categories
        // are all about the clip.
        if (!_editor.selection.isEmpty && !_editor.selection.isClip) {
          _editor.clearSelection();
        }
        setState(() => _category = c);
      },
    );
    final categoryHeight = showBars ? CategoryBar.heightFor(context) : 0.0;

    // What the strips below the preview will take, so the preview knows what
    // is left and the whole column knows whether it still fits.
    final headerHeight = math.max(r.vp(34), 32);
    // A sheet is one height whichever tool opened it, so this is what the
    // preview has to give up — the same amount every time, which is the point:
    // the video does not resize as the user moves along the toolbar.
    final toolsHeight = _panel == _Panel.none
        ? EditorToolbar.heightFor(context, selected: !_editor.selection.isEmpty)
        : math.min(PanelShell.kSheetHeight, r.height * (r.isShort ? 0.42 : 0.5))
            + math.max(r.viewPadding.bottom, 8);

    // While the keyboard is up, a panel with a field in it is the only thing
    // the user can reach. `constraints` is the honest measure of what is left
    // — MediaQuery still reports the whole window — so the panel is sized
    // against that, and the strips that the keyboard covers anyway stand down
    // rather than pushing the field off the bottom.
    if (keyboardInset > 80 && _panel != _Panel.none && !wide) {
      final available = constraints.maxHeight.isFinite
          ? constraints.maxHeight
          : r.height;
      final roomForBoth = available >= _kMinPanelHeight + _kMinPreviewHeight;
      final panelHeight = roomForBoth
          ? math.min(toolsHeight, available - _kMinPreviewHeight)
          : available;
      return _fit(
        constraints,
        roomForBoth ? panelHeight + _kMinPreviewHeight : panelHeight,
        Column(
          children: [
            if (roomForBoth) Expanded(child: preview),
            // A ceiling, not a height: the panel takes only the room its
            // controls need and the preview keeps the rest.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: panelHeight),
              child: tools,
            ),
          ],
        ),
      );
    }

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
            if (_editor.isBusy) _busyBar(safeBottom: !showBars),
            if (showBars) categoryBar,
          ],
        ),
      );
    }

    return _fit(
      constraints,
      headerHeight +
          timelineHeight +
          toolsHeight +
          categoryHeight +
          _kMinPreviewHeight,
      Column(
        children: [
          Expanded(child: preview),
          header,
          // Tools sit above the timeline and the category bar below it, so
          // the row of actions is right next to the clip it acts on.
          if (showBars) tools,
          SizedBox(height: timelineHeight, child: timeline),
          if (!showBars) tools,
          if (_editor.isBusy) _busyBar(safeBottom: !showBars),
          if (showBars) categoryBar,
        ],
      ),
    );
  }

  /// Raising the keyboard moves the open panel to a different place in the
  /// column. A global key carries its element — and so its state — across
  /// that move; without one the panel is rebuilt from scratch and loses the
  /// tab it was on, its scroll position and anything it had loaded.
  final GlobalKey _panelKey = GlobalKey();

  /// The preview may be squeezed, but not to nothing.
  static const double _kMinPreviewHeight = 88;

  /// Below this a panel shows nothing but its own title bar, so when the
  /// window cannot spare this much the preview gives way instead.
  static const double _kMinPanelHeight = 150;

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

  /// [safeBottom] is false when the category bar sits below this strip and
  /// is the one carrying the navigation bar's inset.
  Widget _busyBar({bool safeBottom = true}) {
    final r = context.r;
    return Container(
      color: AppColors.surfaceHigh,
      // Sits below the toolbar when it shows, so it is the strip that meets
      // the navigation bar and has to carry the inset.
      child: SafeArea(
        top: false,
        bottom: safeBottom,
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
      case _Panel.colorFilter:
        return _colorPanel(
          index,
          (i, o) => FilterPanel(
            editor: _editor,
            clipIndex: i,
            overlay: o,
            onClose: _closePanel,
          ),
        );
      case _Panel.filter:
        return _colorPanel(
          index,
          (i, o) => EffectsPanel(
            editor: _editor,
            clipIndex: i,
            overlay: o,
            onClose: _closePanel,
          ),
        );
      case _Panel.adjust:
        return _colorPanel(
          index,
          (i, o) => AdjustPanel(
            editor: _editor,
            clipIndex: i,
            overlay: o,
            onClose: _closePanel,
          ),
        );
      case _Panel.sort:
        return SortPanel(editor: _editor, onClose: _closePanel);
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
        // The guard comes first: with one clip the clamp below would be
        // clamp(0, -1), which is an assertion, not a panel.
        if (_editor.project.clips.length < 2) {
          return _emptyPanel('Add a second clip first');
        }
        final i = _transitionIndex.clamp(0, _editor.project.clips.length - 2);
        return TransitionPanel(
          editor: _editor,
          index: i,
          onClose: _closePanel,
          onPreview: () => _revealTransition(i),
        );
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

  /// Point a visual tool at something the preview is actually showing.
  ///
  /// The panels edit the *selected* clip or overlay while the canvas only ever
  /// renders what sits under the *playhead*. When the two drift apart every
  /// slider looks dead: the grade lands on a clip that is nowhere on screen.
  /// So we reconcile them here — pick up the playhead's clip when nothing is
  /// selected, and otherwise pull the playhead onto the selected target.
  /// Returns false only when there is nothing to edit at all.
  bool _retargetToPlayheadClip() {
    final project = _editor.project;
    if (project.clips.isEmpty && project.overlays.isEmpty) {
      _toast('Add a video or photo first');
      return false;
    }

    if (_editor.selectedOverlay != null) {
      _revealSelection();
      _revealedSelection = _editor.selection.id;
      return true;
    }

    final index = _editor.selectedClipIndex;
    if (index < 0) {
      if (project.clips.isEmpty) {
        _toast('Add a video or photo first');
        return false;
      }
      _editor.selectClip(project.clipIndexAt(_editor.position.value));
      return true;
    }

    _revealClip(index);
    _revealedSelection = _editor.selection.id;
    return true;
  }

  /// Brings the preview onto whatever the panels are about to edit, whether
  /// that is a main-track clip or one of the overlay lanes.
  void _revealSelection() {
    final layer = _editor.selectedLayer;
    if (layer != null) {
      // A layer only draws inside its own span, so a panel opened with the
      // playhead parked elsewhere would style something off screen.
      if (!layer.isVisibleAt(_editor.position.value)) _engine.seek(layer.start);
      return;
    }
    _revealClip(_editor.selectedClipIndex);
  }

  /// Parks the playhead in the middle of the transition after clip [index].
  ///
  /// The canvas only draws a transition while the playhead is inside the
  /// overlap between the two clips, and that overlap is a fraction of a
  /// second wide — and it moves every time the look or the length changes,
  /// because an overlap pulls everything after it earlier. Landing on its
  /// midpoint is what makes the tool show its own work.
  void _revealTransition(int index) {
    final project = _editor.project;
    if (index < 0 || index + 1 >= project.clips.length) return;
    final overlap = project.overlapAfter(index);
    if (overlap <= Duration.zero) {
      _engine.seek(project.clipStart(index + 1));
      return;
    }
    _engine.seek(project.clipStart(index + 1) + overlap ~/ 2);
  }

  /// Puts the playhead inside clip [index], leaving it where it is when it
  /// already sits there.
  void _revealClip(int index) {
    final project = _editor.project;
    if (index < 0 || index >= project.clips.length) return;
    if (project.clipIndexAt(_editor.position.value) == index) return;
    // A transition makes the outgoing clip overlap this one's first frames,
    // so land past the overlap or the playhead stays on the previous clip.
    var target = project.clipStart(index) + project.overlapAfter(index - 1);
    if (project.clipIndexAt(target) != index) {
      target += const Duration(milliseconds: 1);
    }
    _engine.seek(target);
  }

  /// Keeps [_retargetToPlayheadClip]'s promise for as long as the panel is
  /// open: picking another clip in the timeline while one of these tools is
  /// up brings the preview along, instead of leaving the sliders editing a
  /// clip that scrolled off the playhead.
  ///
  /// The selection is followed, never changed — a tap on a text or sticker
  /// while the panel is open belongs to the user, not to this.
  void _onSelectionChanged() {
    final id = _editor.selection.id;
    if (id == _revealedSelection) return;
    _revealedSelection = id;
    if (!_targetScoped.contains(_panel)) return;
    _revealSelection();
  }

  /// Filter and Adjust grade whichever of the two gradable things is
  /// selected — a main-track clip or an overlay.
  Widget _colorPanel(
    int index,
    Widget Function(int? clipIndex, OverlayLayer? overlay) build,
  ) {
    final overlay = _editor.selectedOverlay;
    if (overlay != null) return build(null, overlay);
    if (index < 0 || index >= _editor.project.clips.length) {
      return _emptyPanel('Select a clip');
    }
    return build(index, null);
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
      child: AnimationPicker(
        animationIn: animIn,
        animationOut: animOut,
        duration: duration,
        onIn: onIn,
        onOut: onOut,
        onDuration: onDuration,
      ),
    );
  }

  // --------------------------------------------------------------- actions

  /// The clip a one-shot action lands on.
  ///
  /// The strip offers the clip tools whether or not a clip has been tapped,
  /// so an untouched selection means "the clip the preview is showing"
  /// rather than "nothing" — and selecting it is what shows the user which
  /// clip the action just moved, replaced or deleted.
  int _targetClipIndex() {
    final project = _editor.project;
    if (project.clips.isEmpty) return -1;
    final index = _editor.selectedClipIndex;
    if (index >= 0) return index;
    // A layer is selected: leave it alone rather than swapping the user's
    // selection out from under them.
    if (!_editor.selection.isEmpty) return -1;
    final at = project.clipIndexAt(_editor.position.value);
    _editor.selectClip(at);
    return at;
  }

  Future<void> _handle(ToolAction action) async {
    await _engine.pause();
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
        _revealSelection();
        setState(() => _panel = _Panel.keyframe);
      case ToolAction.mask:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.mask);
      case ToolAction.chroma:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.chroma);
      case ToolAction.blend:
        _revealSelection();
        setState(() => _panel = _Panel.blend);
      case ToolAction.stabilize:
        final target = _targetClipIndex();
        if (target < 0) {
          _toast('Add a video or photo first');
        } else {
          _editor.updateClip(target, (c) => c.stabilize = !c.stabilize);
          _toast(
            _editor.project.clips[target].stabilize
                ? 'Stabilization on — applied at export'
                : 'Stabilization off',
          );
        }

      case ToolAction.split:
        if (!_editor.splitAtPlayhead()) {
          _toast('Move the playhead inside a clip to split');
        }
      case ToolAction.sort:
        if (_editor.project.clips.length < 2) {
          _toast('Add a second clip to re-order the track');
        } else {
          setState(() => _panel = _Panel.sort);
        }
      case ToolAction.speed:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.speed);
      case ToolAction.volume:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.volume);
      case ToolAction.colorFilter:
        if (_retargetToPlayheadClip()) {
          setState(() => _panel = _Panel.colorFilter);
        }
      case ToolAction.filter:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.filter);
      case ToolAction.adjust:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.adjust);
      case ToolAction.crop:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.crop);
      case ToolAction.duration:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.duration);
      case ToolAction.transition:
        final index = _targetClipIndex();
        if (index < 0 || index >= _editor.project.clips.length - 1) {
          _toast('Pick a clip that has one after it');
        } else {
          // Park on the junction the transition actually plays over, so the
          // preview is showing the cut being dressed.
          _revealTransition(index);
          setState(() {
            _transitionIndex = index;
            _panel = _Panel.transition;
          });
        }
      case ToolAction.rotate:
        final index = _targetClipIndex();
        if (index >= 0) {
          // One-shot actions still need the frame on screen — a quarter turn
          // applied to a clip the playhead left behind looks like a dead
          // button.
          _revealSelection();
          _editor.updateClip(
            index,
            (c) => c.rotation = (c.rotation + 90) % 360,
          );
        }
      case ToolAction.mirror:
        final index = _targetClipIndex();
        if (index >= 0) {
          _revealSelection();
          _editor.updateClip(index, (c) => c.mirrored = !c.mirrored);
        }
      case ToolAction.reverse:
        await _reverseClip(_targetClipIndex());
      case ToolAction.freeze:
        await _freezeFrame(_targetClipIndex());
      case ToolAction.extractAudio:
        await _extractAudio(_targetClipIndex());
      case ToolAction.replace:
        await _replaceClip(_targetClipIndex());
      case ToolAction.duplicate:
        _editor.duplicateClip(_targetClipIndex());
      case ToolAction.delete:
        final target = _targetClipIndex();
        if (target < 0) {
          _toast('Add a video or photo first');
        } else {
          _editor.deleteClip(target);
        }
        _closePanel();

      case ToolAction.editText:
        _revealSelection();
        setState(() => _panel = _Panel.text);
      case ToolAction.editSticker:
        _revealSelection();
        setState(() => _panel = _Panel.stickerStyle);
      case ToolAction.editOverlay:
        _revealSelection();
        setState(() => _panel = _Panel.overlay);
      case ToolAction.editAudio:
        _revealSelection();
        setState(() => _panel = _Panel.audio);
      case ToolAction.animation:
        _revealSelection();
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
