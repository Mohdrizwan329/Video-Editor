import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/enums.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_backup.dart';
import '../../state/projects_controller.dart';
import '../editor/editor_screen.dart';
import '../image_editor/image_editor_screen.dart';
import '../picker/media_picker_screen.dart';
import '../text_to_video/text_to_video_screen.dart';
import 'widgets/project_tile.dart';

/// Landing screen: the big "new project" action over the project library.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Past this many projects the list stops being something you can scan, so
  /// the filter appears. Below it the field would be one more row between the
  /// user and the two projects they have.
  static const int _searchThreshold = 6;

  final TextEditingController _search = TextEditingController();

  /// What the field currently holds, lower-cased once rather than per row.
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Project> _visible(ProjectsController c) {
    if (_query.isEmpty) return c.projects;
    return [
      for (final p in c.projects)
        if (p.name.toLowerCase().contains(_query)) p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProjectsController>();
    final r = context.r;
    final visible = _visible(controller);
    final searchable = controller.projects.length >= _searchThreshold;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _appBar(context),
      // Flat page fill — no ambient gradient wash behind the content.
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.appBar,
          backgroundColor: AppColors.surface,
          onRefresh: controller.refresh,
          // On a tablet or a desktop window the page stops widening and
          // centres instead, so a project row never stretches to a metre.
          child: ContentBox(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _newProjectCard(context)),
                SliverToBoxAdapter(child: _textToVideoCard(context)),
                SliverToBoxAdapter(child: _imageEditCard(context)),
                SliverToBoxAdapter(child: _quickTools(context)),
                SliverToBoxAdapter(
                  child: _sectionTitle(context, controller, visible.length),
                ),
                if (searchable)
                  SliverToBoxAdapter(child: _searchField(context)),
                if (controller.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.appBar,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (controller.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _empty(context),
                  )
                else if (visible.isEmpty)
                  SliverToBoxAdapter(child: _noMatches(context))
                else
                  _projectSliver(context, visible, r),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One column of rows on a phone; on anything wider the same rows tile into
  /// a grid so the extra width becomes more projects on screen, not longer
  /// rows.
  Widget _projectSliver(
    BuildContext context,
    List<Project> projects,
    Responsive r,
  ) {
    final controller = context.read<ProjectsController>();
    final padding = EdgeInsets.fromLTRB(r.gutter, r.vp(4), r.gutter, r.vp(40));

    Widget tileAt(int i) {
      final p = projects[i];
      return ProjectTile(
        project: p,
        onTap: () => _open(context, p),
        onRename: () => _rename(context, p),
        onDuplicate: () => controller.duplicate(p),
        onDelete: () => _confirmDelete(context, p),
        onBackup: () => _backup(context, p),
      );
    }

    if (r.isCompact) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.separated(
          itemCount: projects.length,
          separatorBuilder: (_, _) => SizedBox(height: r.vp(10)),
          itemBuilder: (context, i) => tileAt(i),
        ),
      );
    }
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 460,
          crossAxisSpacing: r.dp(12),
          mainAxisSpacing: r.dp(12),
          // The row is as tall as its cover plus the card's padding; fixing
          // the extent keeps every tile aligned whatever the name length.
          mainAxisExtent: ProjectTile.extentFor(context),
        ),
        itemCount: projects.length,
        itemBuilder: (context, i) => tileAt(i),
      ),
    );
  }

  /// The one top bar the home screen gets: same height and same flat fill as
  /// every other screen's app bar.
  PreferredSizeWidget _appBar(BuildContext context) {
    final r = context.r;
    return AppBar(
      titleSpacing: 0,
      leadingWidth: 52,
      title: const Text('Video Editor'),
      actions: [
        IconButton(
          tooltip: 'Restore project',
          icon: Icon(Icons.unarchive_outlined, size: r.ic(20)),
          onPressed: () => _restore(context),
        ),
        IconButton(
          tooltip: 'How it works',
          icon: Icon(Icons.help_outline, size: r.ic(20)),
          onPressed: () => _showAbout(context),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// The primary action: the app bar's own fill dropped onto the light page,
  /// so it is unmistakably the thing to tap without introducing a new hue.
  Widget _newProjectCard(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, r.vp(10), r.gutter, r.vp(4)),
      child: _HeroCard(
        icon: Icons.add,
        iconSize: r.ic(28),
        title: 'New Project',
        subtitle: 'Pick videos and photos to start',
        subtitleColor: AppColors.onAppBarDim,
        gradient: AppColors.appBarGradient,
        glow: AppColors.glow(AppColors.appBar, opacity: 0.34),
        onTap: () => _startNewProject(context),
      ),
    );
  }

  /// The second way in: no footage at all, just a prompt. It carries the same
  /// weight as [_newProjectCard] because it is an equal starting point, and
  /// takes the hue wheel's violet so the two are never mistaken for each other.
  Widget _textToVideoCard(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, r.vp(12), r.gutter, 0),
      child: _HeroCard(
        icon: Icons.text_fields,
        iconSize: r.ic(26),
        title: 'Generate Text to Video',
        badge: 'Coming soon',
        subtitle: 'Describe a shot, AI films it',
        subtitleColor: const Color(0xE6FFFFFF),
        gradient: AppColors.heroGradient,
        glow: AppColors.glow(AppColors.violet, opacity: 0.34),
        onTap: () => _startTextToVideo(context),
      ),
    );
  }

  /// Builds the project on the generator screen, then drops straight into the
  /// editor with it — the same landing point every other entry point uses.
  Future<void> _startTextToVideo(BuildContext context) async {
    final navigator = Navigator.of(context);
    final controller = context.read<ProjectsController>();

    final project = await navigator.push<Project>(
      MaterialPageRoute(builder: (_) => const TextToVideoScreen()),
    );
    if (project == null) return;

    await controller.refresh();
    await navigator.push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project)),
    );
    await controller.refresh();
  }

  /// The third way in, and the only one that ends in a photo rather than a
  /// video: the same grades, sliders, textures and frames the timeline uses,
  /// pointed at a single still. It takes the ocean gradient so it is never
  /// mistaken for the violet generator above it.
  Widget _imageEditCard(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, r.vp(12), r.gutter, 0),
      child: _HeroCard(
        icon: Icons.photo_filter,
        iconSize: r.ic(26),
        title: 'Image Edit',
        subtitle: 'Crop, retouch, mark up and caption a photo',
        subtitleColor: const Color(0xE6FFFFFF),
        gradient: AppColors.oceanGradient,
        glow: AppColors.glow(AppColors.sky, opacity: 0.34),
        onTap: () => _startImageEdit(context),
      ),
    );
  }

  /// One photo in, the editor on top of it. The picker is the same one the
  /// timeline uses, held to a single image.
  Future<void> _startImageEdit(BuildContext context) async {
    final navigator = Navigator.of(context);
    final paths = await navigator.push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const MediaPickerScreen(
          title: 'Pick a photo',
          filter: RequestType.image,
          maxSelection: 1,
        ),
      ),
    );
    if (paths == null || paths.isEmpty) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => ImageEditorScreen(path: paths.first)),
    );
  }

  Widget _quickTools(BuildContext context) {
    // The four tiles share the header tone rather than one hue each: they are
    // the same action at four ratios, so they should read as one row.
    final tools = <(IconData, String, String, CanvasRatio)>[
      (Icons.stay_current_portrait, 'Reels', '9:16', CanvasRatio.r9x16),
      (Icons.crop_square, 'Post', '1:1', CanvasRatio.r1x1),
      (Icons.stay_current_landscape, 'YouTube', '16:9', CanvasRatio.r16x9),
      (Icons.panorama_wide_angle, 'Cine', '2.35:1', CanvasRatio.r235x1),
    ];
    final r = context.r;
    final ts = MediaQuery.textScalerOf(context);
    // The strip is measured, not guessed: the icon, both labels at whatever
    // the system font scale is, the card's padding and border, and the list's
    // own padding. Guessing is what used to clip the ratio line on a 320pt
    // phone and at large text sizes.
    double line(double size) => ts.scale(r.sp(size)) * 1.5;
    final tileWidth = r.dp(100);
    final tileHeight =
        r.dp(11) * 2 + 2 + r.ic(20) + line(12.5) + r.vp(1) + line(10);
    final stripHeight = tileHeight + r.vp(14) + r.vp(6);
    final gap = r.dp(10);

    Widget tile(int i, {double? width}) {
      final (icon, label, ratio, canvasRatio) = tools[i];
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _startNewProject(context, ratio: canvasRatio),
        child: Container(
          width: width,
          padding: EdgeInsets.all(r.dp(11)),
          decoration: BoxDecoration(
            gradient: AppColors.tint(AppColors.appBar),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.appBar.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: r.ic(20), color: AppColors.appBarMuted),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(12.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: r.vp(1)),
              Text(
                ratio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: r.sp(10),
                  fontWeight: FontWeight.w600,
                  color: AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: stripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needed =
              tools.length * tileWidth +
              (tools.length - 1) * gap +
              r.gutter * 2;
          // Once all four fit, they share the row evenly instead of leaving a
          // ragged scrollable strip on a wide window.
          if (needed <= constraints.maxWidth) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                r.gutter,
                r.vp(14),
                r.gutter,
                r.vp(6),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tools.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(child: tile(i)),
                  ],
                ],
              ),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(r.gutter, r.vp(14), r.gutter, r.vp(6)),
            itemCount: tools.length,
            separatorBuilder: (_, _) => SizedBox(width: gap),
            itemBuilder: (context, i) => tile(i, width: tileWidth),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, ProjectsController c, int shown) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        r.gutter + r.dp(4),
        r.vp(16),
        r.gutter + r.dp(4),
        r.vp(10),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: r.sp(15),
            decoration: BoxDecoration(
              gradient: AppColors.appBarGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: r.dp(9)),
          Text(
            'Projects',
            style: TextStyle(fontSize: r.sp(14.5), fontWeight: FontWeight.w700),
          ),
          SizedBox(width: r.dp(8)),
          if (!c.loading)
            Container(
              padding: EdgeInsets.symmetric(horizontal: r.dp(7), vertical: 1.5),
              decoration: BoxDecoration(
                color: AppColors.appBar.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                shown == c.projects.length
                    ? '$shown'
                    : '$shown of ${c.projects.length}',
                style: TextStyle(
                  fontSize: r.sp(10.5),
                  fontWeight: FontWeight.w700,
                  color: AppColors.appBarMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Filters the library by name. It appears only once the list is long
  /// enough to be worth filtering — see [_searchThreshold].
  Widget _searchField(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, 0, r.gutter, r.vp(8)),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        style: TextStyle(fontSize: r.sp(12.5)),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search projects',
          prefixIcon: Icon(
            Icons.search,
            size: r.ic(18),
            color: AppColors.textFaint,
          ),
          prefixIconConstraints: BoxConstraints(minWidth: r.dp(38)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.close, size: r.ic(16)),
                  color: AppColors.textFaint,
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          contentPadding: EdgeInsets.symmetric(vertical: r.vp(11)),
        ),
      ),
    );
  }

  /// The library is not empty — the filter is just too narrow. Saying which
  /// of the two it is, and offering the way back, is the whole point.
  Widget _noMatches(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, r.vp(30), r.gutter, r.vp(30)),
      child: Column(
        children: [
          Icon(Icons.search_off, size: r.ic(30), color: AppColors.appBarMuted),
          SizedBox(height: r.vp(10)),
          Text(
            'No project matches "${_search.text.trim()}"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(12.5), color: AppColors.textDim),
          ),
          SizedBox(height: r.vp(10)),
          TextButton(
            style: AppTheme.outlinedAction(tone: AppColors.appBarMuted),
            onPressed: () {
              _search.clear();
              setState(() => _query = '');
            },
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.fromLTRB(r.gutter, r.vp(44), r.gutter, r.vp(24)),
      child: Column(
        children: [
          Container(
            width: r.dp(74),
            height: r.dp(74),
            decoration: BoxDecoration(
              gradient: AppColors.tint(AppColors.appBar),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.appBar.withValues(alpha: 0.18),
              ),
            ),
            child: Icon(
              Icons.movie_creation_outlined,
              size: r.ic(32),
              color: AppColors.appBarMuted,
            ),
          ),
          SizedBox(height: r.vp(14)),
          Text(
            'No projects yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(14), fontWeight: FontWeight.w600),
          ),
          SizedBox(height: r.vp(4)),
          Text(
            'Tap New Project to begin',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: r.sp(11.5), color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  Future<void> _startNewProject(
    BuildContext context, {
    CanvasRatio ratio = CanvasRatio.r9x16,
  }) async {
    final paths = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const MediaPickerScreen()),
    );
    if (paths == null || paths.isEmpty || !context.mounted) return;
    final controller = context.read<ProjectsController>();
    final project = await controller.create(ratio: ratio);
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(project: project, initialMedia: paths),
      ),
    );
    if (context.mounted) await controller.refresh();
  }

  Future<void> _open(BuildContext context, Project p) async {
    final controller = context.read<ProjectsController>();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(project: p)),
    );
    if (context.mounted) await controller.refresh();
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = context.read<ProjectsController>();
    final restored = await ProjectBackup.import();
    if (restored == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Nothing restored')));
      return;
    }
    await controller.refresh();
    messenger.showSnackBar(
      SnackBar(content: Text('Restored "${restored.name}"')),
    );
  }

  Future<void> _backup(BuildContext context, Project p) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Packing project…')));
    final path = await ProjectBackup.export(p);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(path == null ? 'Backup failed' : 'Saved to $path'),
        ),
      );
  }

  Future<void> _rename(BuildContext context, Project p) async {
    final controller = context.read<ProjectsController>();
    final text = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename project'),
        content: TextField(
          controller: text,
          autofocus: true,
          style: const TextStyle(color: AppColors.onAppBar),
          decoration: AppTheme.dialogField('Project name'),
        ),
        actions: [
          TextButton(
            style: AppTheme.outlinedAction(),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: AppTheme.outlinedAction(),
            onPressed: () => Navigator.pop(context, text.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await controller.rename(p, name);
  }

  Future<void> _confirmDelete(BuildContext context, Project p) async {
    final controller = context.read<ProjectsController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text('"${p.name}" will be removed. Imported media stays.'),
        actions: [
          TextButton(
            style: AppTheme.outlinedAction(),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: AppTheme.outlinedAction(tone: AppColors.dangerSoft),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.delete(p);
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // On a wide window the sheet stops at a readable column rather than
      // running the full width of a desktop monitor.
      constraints: BoxConstraints(
        maxWidth: context.r.maxDialogWidth,
        maxHeight: context.r.height * 0.85,
      ),
      // The same corner every sheet in the app turns, and an outline in the
      // app bar's colour like the editor's sheets carry. This one is already
      // filled in that colour, so the edge reads as a hairline against the
      // dimmed page behind it rather than as a border on the fill.
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.appBar, width: 1.2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final r = sheetContext.r;
        return AppTheme.onPopup(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              r.dp(20),
              r.vp(18),
              r.dp(20),
              r.vp(30),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How it works',
                  style: TextStyle(
                    fontSize: r.sp(15),
                    fontWeight: FontWeight.w700,
                    color: AppColors.onAppBar,
                  ),
                ),
                SizedBox(height: r.vp(12)),
                const _Tip(
                  icon: Icons.touch_app,
                  text:
                      'Drag the timeline to scrub. The playhead stays centred.',
                ),
                const _Tip(
                  icon: Icons.pinch,
                  text: 'Pinch the timeline to zoom in and out.',
                ),
                const _Tip(
                  icon: Icons.content_cut,
                  text: 'Tap a clip, then Split to cut at the playhead.',
                ),
                const _Tip(
                  icon: Icons.movie_filter,
                  text: 'Tap the ◇ between clips to add a transition.',
                ),
                const _Tip(
                  icon: Icons.file_download,
                  text: 'Export renders with FFmpeg at up to 4K.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The two full-width entry points at the top of the page. They differ only in
/// their fill and their words, so they are one widget sized from the window
/// rather than two copies of the same fixed-height row.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.icon,
    required this.iconSize,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.gradient,
    required this.glow,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final double iconSize;
  final String title;

  /// A word beside the title — 'Coming soon' on a way in that is not
  /// finished yet. Null on the ones that are.
  final String? badge;
  final String subtitle;
  final Color subtitleColor;
  final Gradient gradient;
  final List<BoxShadow> glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Stack(
        children: [
          _card(context, r),
          // Bottom right, where nothing else is: the title needs the width
          // it has and the subtitle ends well short of that corner.
          if (badge != null)
            Positioned(
              right: r.dp(14),
              bottom: r.vp(10),
              // Solid, not a tint: a translucent pill on a gradient reads
              // as part of the gradient, and this is the one thing on the
              // card the user has to notice.
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: r.dp(10),
                  vertical: r.vp(4),
                ),
                decoration: BoxDecoration(
                  color: AppColors.onAppBar,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: r.sp(10),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: AppColors.appBar,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Responsive r) {
    return Container(
      // A minimum rather than a fixed height: at the largest text scale the
      // two lines grow the card instead of overflowing it.
      constraints: BoxConstraints(minHeight: r.vp(98)),
      padding: EdgeInsets.symmetric(vertical: r.vp(10)),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: glow,
      ),
      child: Row(
        children: [
          SizedBox(width: r.dp(18)),
          Container(
            width: r.dp(50),
            height: r.dp(50),
            decoration: BoxDecoration(
              color: AppColors.onAppBar.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.onAppBar.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
            child: Icon(icon, color: AppColors.onAppBar, size: iconSize),
          ),
          SizedBox(width: r.dp(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: r.sp(17),
                    fontWeight: FontWeight.w800,
                    color: AppColors.onAppBar,
                  ),
                ),
                SizedBox(height: r.vp(3)),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: r.sp(11.5), color: subtitleColor),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            color: AppColors.onAppBar,
            size: r.ic(21),
          ),
          SizedBox(width: r.dp(16)),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: EdgeInsets.only(bottom: r.vp(13)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: r.dp(28),
            height: r.dp(28),
            decoration: BoxDecoration(
              color: AppColors.onAppBar.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: r.ic(15), color: AppColors.onAppBar),
          ),
          SizedBox(width: r.dp(12)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: r.vp(5)),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: r.sp(12.5),
                  color: AppColors.onAppBarDim,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
