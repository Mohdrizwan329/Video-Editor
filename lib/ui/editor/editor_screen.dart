import 'dart:io';
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
import '../../data/services/cutout_service.dart';
import '../../data/services/media_library.dart';
import '../../data/models/project.dart';
import '../../state/editor_controller.dart';
import '../../state/preview_engine.dart';
import '../export/export_screen.dart';
import '../picker/media_picker_screen.dart';
import 'panels/animation_panel.dart';
import 'panels/audio_panel.dart';
import 'panels/canvas_panels.dart';
import 'panels/clip_panels.dart';
import 'panels/clip_tool_panels.dart';
import 'panels/color_panels.dart';
import 'panels/color_tool_tabs.dart';
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
  opacity,
  ease,
  voiceEffect,
  cutout,
}

/// The editing surface: preview on top, timeline in the middle, contextual
/// tools at the bottom.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.project, this.initialMedia});

  final Project project;
  final List<String>? initialMedia;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController _editor = EditorController(widget.project);
  late final PreviewEngine _engine = PreviewEngine(_editor);

  _Panel _panel = _Panel.none;
  int _transitionIndex = 0;

  /// Which family of tools the bar along the bottom is pointing at.

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _import(media));
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _warnAboutMissingMedia(),
      );
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

  /// Says so when a project's media is not where it was left.
  ///
  /// Imports are copied into the app's own storage now, but a project made
  /// before that — or one whose copy was cleared with the app's data — opens
  /// on a black canvas, and then every tool looks broken rather than
  /// pointed at a file that is gone. One line explains the whole screen.
  Future<void> _warnAboutMissingMedia() async {
    final paths = <String>{
      for (final c in _editor.project.clips) c.path,
      for (final o in _editor.project.overlays) o.path,
    };
    var missing = 0;
    for (final path in paths) {
      if (!await File(path).exists()) missing++;
    }
    if (missing == 0 || !mounted) return;
    _toast(
      missing == 1
          ? "1 clip's file is missing — replace it to keep editing"
          : '$missing files are missing — replace those clips to keep editing',
    );
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
            axis: wide ? Axis.vertical : Axis.horizontal,
          )
        : KeyedSubtree(key: _panelKey, child: _buildPanel());

    /// A sheet's rounded top corners cut two notches out of it, and what
    /// belongs behind them is whatever strip the sheet is docked under —
    /// the timeline in the ordinary layout, the preview's own fill once the
    /// keyboard has taken the timeline away. Painting the wrong one is what
    /// leaves two coloured shoulders sticking out past the corners.
    Widget docked(Color behind) =>
        _panel == _Panel.none ? tools : ColoredBox(color: behind, child: tools);

    final preview = Padding(
      padding: EdgeInsets.symmetric(horizontal: r.dp(12), vertical: r.vp(6)),
      child: PreviewStage(
        watermarkFocus: _panel == _Panel.watermark,
        markKey: _watermarkKey,
        onEditWatermark: () => setState(() => _panel = _Panel.watermark),
      ),
    );

    final timeline = Container(
      color: AppColors.timelineBg,
      child: TimelineView(
        editor: _editor,
        onAddMedia: _pickMoreMedia,
        onScrubStart: _engine.pause,
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

    // The tool strip stands down while a panel is open — the panel is what
    // the bottom of the screen is for then.
    final showBars = _panel == _Panel.none;

    // What the strips below the preview will take, so the preview knows what
    // is left and the whole column knows whether it still fits.
    final headerHeight = math.max(r.vp(34), 32);
    // A sheet is one height whichever tool opened it, so this is what the
    // preview has to give up — the same amount every time, which is the point:
    // the video does not resize as the user moves along the toolbar.
    final toolsHeight = _panel == _Panel.none
        ? EditorToolbar.heightFor(context)
        : math.min(
                PanelShell.kSheetHeight,
                r.height * (r.isShort ? 0.42 : 0.5),
              ) +
              math.max(r.viewPadding.bottom, 8);

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
              // The preview sits directly above, on the page's own fill.
              child: docked(AppColors.surface),
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
                              // Nothing above it in the rail but the page.
                              child: docked(AppColors.surface),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            header,
            SizedBox(height: timelineHeight, child: timeline),
            if (_editor.isBusy) _busyBar(safeBottom: !showBars),
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
          // Tools sit above the timeline and the category bar below it, so
          // the row of actions is right next to the clip it acts on.
          if (showBars) tools,
          SizedBox(height: timelineHeight, child: timeline),
          // The timeline is what the sheet is docked under here, so that is
          // what shows through its rounded corners.
          if (!showBars) docked(AppColors.timelineBg),
          if (_editor.isBusy) _busyBar(safeBottom: !showBars),
        ],
      ),
    );
  }

  /// Raising the keyboard moves the open panel to a different place in the
  /// column. A global key carries its element — and so its state — across
  /// that move; without one the panel is rebuilt from scratch and loses the
  /// tab it was on, its scroll position and anything it had loaded.
  final GlobalKey _panelKey = GlobalKey();

  /// Rides on the watermark as it is drawn on the canvas, so a tap there can
  /// be told from a tap on the video and open the mark's own panel.
  final GlobalKey _watermarkKey = GlobalKey();

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

  /// How tall the timeline has to be for the lanes it is showing. The number
  /// belongs to the widget that draws those rows — asking it is what keeps
  /// the box from reserving room for rows that are not there.
  double _timelineHeight() => TimelineView.heightFor(_editor);

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
        tooltip: 'Back — the project saves itself',
        icon: Icon(Icons.arrow_back, size: r.ic(21)),
        onPressed: () async {
          final navigator = Navigator.of(context);
          await _engine.pause();
          await _editor.saveNow();
          navigator.pop();
        },
      ),
      title: Tooltip(
        message: 'Rename project',
        child: GestureDetector(
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
      ),
      actions: [
        _ratioBadge(),
        SizedBox(width: r.dp(6)),
        Padding(
          padding: EdgeInsets.only(right: r.dp(10)),
          child: InkWell(
            onTap: _export,
            borderRadius: BorderRadius.circular(11),
            // The row inside is a picture-and-word, not a button, until this
            // says so — a screen reader announced two loose labels.
            excludeFromSemantics: true,
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
    return Tooltip(
      message: 'Canvas size — tap to change',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _panel = _Panel.ratio),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: r.dp(9), vertical: r.dp(4)),
          // Tinted off the bar's own foreground, not off a hue — the hues are
          // tuned for the light page and go muddy on the dark bar.
          decoration: BoxDecoration(
            color: AppColors.onAppBar.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.onAppBar.withValues(alpha: 0.24),
            ),
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

  /// The three colour tools swap in place inside the open sheet rather than
  /// closing it and sending the user back to the tool strip: picking a look
  /// and then nudging its contrast is one job, not two.
  void _switchColorTool(ColorTool tool) => setState(() {
    _panel = switch (tool) {
      ColorTool.filter => _Panel.colorFilter,
      ColorTool.effect => _Panel.filter,
      ColorTool.adjust => _Panel.adjust,
    };
  });

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
      case _Panel.opacity:
        return _clipPanel(
          index,
          (i) => OpacityPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.ease:
        return _clipPanel(
          index,
          (i) => EasePanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.voiceEffect:
        return _clipPanel(
          index,
          (i) =>
              VoiceEffectPanel(editor: _editor, index: i, onClose: _closePanel),
        );
      case _Panel.cutout:
        return _clipPanel(
          index,
          (i) => CutoutPanel(
            editor: _editor,
            index: i,
            onClose: _closePanel,
            onRunCutout: () => _runCutout(i),
            onChroma: () => setState(() => _panel = _Panel.chroma),
          ),
        );
      case _Panel.colorFilter:
        return _colorPanel(
          index,
          (i, o) => FilterPanel(
            editor: _editor,
            clipIndex: i,
            overlay: o,
            onClose: _closePanel,
            onTool: _switchColorTool,
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
            onTool: _switchColorTool,
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
            onTool: _switchColorTool,
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
      // A main-track clip animates too — it has carried the fields all
      // along. Sending the user away with 'select a layer' was the panel
      // refusing the one thing the bar's Animation button selects.
      final index = _editor.selectedClipIndex >= 0
          ? _editor.selectedClipIndex
          : _editor.project.clipIndexAt(_editor.position.value);
      if (index < 0 || index >= _editor.project.clips.length) {
        return _emptyPanel('Add a clip or layer to animate');
      }
      final clip = _editor.project.clips[index];
      animIn = clip.animationIn;
      animOut = clip.animationOut;
      duration = clip.animationDuration;
      onIn = (a) => _editor.updateClip(index, (c) => c.animationIn = a);
      onOut = (a) => _editor.updateClip(index, (c) => c.animationOut = a);
      onDuration = (d) =>
          _editor.updateClip(index, (c) => c.animationDuration = d);
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
      case ToolAction.opacity:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.opacity);
      case ToolAction.ease:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.ease);
      case ToolAction.voiceEffect:
        if (_retargetToPlayheadClip()) {
          setState(() => _panel = _Panel.voiceEffect);
        }
      case ToolAction.voiceEnhance:
        final target = _targetClipIndex();
        if (target < 0) {
          _toast('Add a video or photo first');
        } else {
          _editor.updateClip(target, (c) => c.voiceEnhance = !c.voiceEnhance);
          _toast(
            _editor.project.clips[target].voiceEnhance
                ? 'Voice enhance on — applied at export'
                : 'Voice enhance off',
          );
        }
      case ToolAction.enhance:
        final target = _targetClipIndex();
        if (target < 0) {
          _toast('Add a video or photo first');
        } else {
          _editor.updateClip(target, (c) => c.enhance = !c.enhance);
          _toast(
            _editor.project.clips[target].enhance
                ? 'Enhance on — applied at export'
                : 'Enhance off',
          );
        }
      case ToolAction.cutout:
        if (_retargetToPlayheadClip()) setState(() => _panel = _Panel.cutout);
      case ToolAction.aiCut:
        await _aiCut(_targetClipIndex());
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
          _toastUndo('Clip deleted');
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
        if (layer != null) {
          _editor.deleteLayer(layer);
          _toastUndo('${_layerNoun(layer)} deleted');
        }
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
      if (!mounted) return;
      _editor.setBusy(null);
      if (beats.isNotEmpty) _toast('${beats.length} beats detected');
    }
    if (mounted) setState(() => _panel = _Panel.audio);
  }

  /// Drop the dead air out of a clip.
  ///
  /// The silences are found once, then inverted into the stretches worth
  /// keeping and applied as a single edit — one undo puts the clip back.
  Future<void> _aiCut(int index) async {
    if (index < 0) return;
    final clip = _editor.project.clips[index];
    if (clip.isImage || !clip.hasAudio) {
      _toast('AI Cut needs a clip with sound');
      return;
    }
    _editor.setBusy('Finding the quiet parts…');
    final silences = await ClipOperations.detectSilence(clip);
    // The render outlives the screen when the user walks away mid-pass, and
    // everything below here writes to a controller the screen disposed on its
    // way out. Checking first is what stops "used after being disposed".
    if (!mounted) return;
    _editor.setBusy(null);
    if (silences.isEmpty) {
      _toast('Nothing quiet enough to cut');
      return;
    }
    // Invert: everything between one silence ending and the next beginning.
    final keep = <(Duration, Duration)>[];
    var cursor = clip.trimStart;
    for (final (from, to) in silences) {
      if (from > cursor) keep.add((cursor, from));
      cursor = to;
    }
    if (clip.trimEnd > cursor) keep.add((cursor, clip.trimEnd));

    final removed =
        clip.trimmedDuration -
        keep.fold(Duration.zero, (sum, s) => sum + (s.$2 - s.$1));
    final pieces = _editor.replaceClipWithSegments(index, keep);
    if (pieces == 0) {
      _toast('The whole clip is quiet — nothing left to keep');
      return;
    }
    _toastUndo(
      'Cut ${(removed.inMilliseconds / 1000).toStringAsFixed(1)}s '
      'of silence into $pieces ${pieces == 1 ? 'clip' : 'clips'}',
    );
  }

  /// Bake — or clear — the clip's cutout matte.
  ///
  /// The pass costs seconds, so it runs behind the editor's own busy bar with
  /// a share rather than a spinner: a user who can see it moving waits, and a
  /// user who cannot assumes the app has hung.
  Future<void> _runCutout(int index) async {
    if (index < 0 || index >= _editor.project.clips.length) return;
    final clip = _editor.project.clips[index];
    if (clip.hasCutout) {
      _editor.updateClip(index, (c) => c.cutoutMattePath = null);
      _toastUndo('Background put back');
      return;
    }
    if (clip.isImage) {
      _toast('Cutout needs a video clip');
      return;
    }
    _editor.setBusy('Cutting out the subject… 0%');
    final matte = await CutoutService.bakeMatte(
      clip,
      onProgress: (p) {
        if (!mounted) return;
        _editor.setBusy('Cutting out the subject… ${(p * 100).round()}%');
      },
    );
    // The render outlives the screen when the user walks away mid-pass, and
    // everything below here writes to a controller the screen disposed on its
    // way out. Checking first is what stops "used after being disposed".
    if (!mounted) return;
    _editor.setBusy(null);
    if (matte == null) {
      _toast('No one found in this clip to cut out');
      return;
    }
    _editor.updateClip(index, (c) => c.cutoutMattePath = matte);
    _toastUndo('Background cut out');
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
    // The render outlives the screen when the user walks away mid-pass, and
    // everything below here writes to a controller the screen disposed on its
    // way out. Checking first is what stops "used after being disposed".
    if (!mounted) return;
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
    // A photo is already one frame held for a while, so there is nothing to
    // freeze out of it. Saying so is the point: the tool used to swallow the
    // tap on a photo and read as a dead button.
    if (clip.isImage) {
      _toast('A photo is already a still — use Duration to hold it longer');
      return;
    }
    final local = _editor.position.value - _editor.project.clipStart(index);
    _editor.setBusy('Freezing frame…');
    final path = await ClipOperations.freezeFrame(
      clip,
      clip.sourcePositionFor(local),
    );
    // The render outlives the screen when the user walks away mid-pass, and
    // everything below here writes to a controller the screen disposed on its
    // way out. Checking first is what stops "used after being disposed".
    if (!mounted) return;
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
    // The render outlives the screen when the user walks away mid-pass, and
    // everything below here writes to a controller the screen disposed on its
    // way out. Checking first is what stops "used after being disposed".
    if (!mounted) return;
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
    if (index < 0) {
      _toast('Add a video or photo first');
      return;
    }
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

  /// A message with the way back attached.
  ///
  /// Deleting is one tap and it takes a clip — with everything graded onto
  /// it — off the timeline. Undo has always been in the header, but a user
  /// who has just lost something is looking at the gap, not at the toolbar,
  /// so the way out is offered where the loss is announced.
  void _toastUndo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 12.5)),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.accentDim,
            onPressed: () {
              if (_editor.canUndo) _editor.undo();
            },
          ),
        ),
      );
  }

  String _layerNoun(TimelineLayer layer) => switch (layer) {
    TextLayer() => 'Text',
    StickerLayer() => 'Sticker',
    OverlayLayer() => 'Overlay',
    AudioLayer() => 'Audio',
    _ => 'Layer',
  };
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
