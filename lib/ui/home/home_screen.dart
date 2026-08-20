import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_backup.dart';
import '../../state/projects_controller.dart';
import '../../data/models/template.dart';
import '../editor/editor_screen.dart';
import '../templates/template_gallery_screen.dart';
import '../picker/media_picker_screen.dart';
import 'widgets/project_tile.dart';

/// Landing screen: the big "new project" action over the project library.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ProjectsController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _appBar(context),
      // Flat page fill — no ambient gradient wash behind the content.
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.appBar,
          backgroundColor: AppColors.surface,
          onRefresh: controller.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _newProjectCard(context)),
              SliverToBoxAdapter(child: _templateCard(context)),
              SliverToBoxAdapter(child: _quickTools(context)),
              SliverToBoxAdapter(child: _sectionTitle(controller)),
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
                SliverFillRemaining(hasScrollBody: false, child: _empty())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
                  sliver: SliverList.separated(
                    itemCount: controller.projects.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = controller.projects[i];
                      return ProjectTile(
                        project: p,
                        onTap: () => _open(context, p),
                        onRename: () => _rename(context, p),
                        onDuplicate: () => controller.duplicate(p),
                        onDelete: () => _confirmDelete(context, p),
                        onBackup: () => _backup(context, p),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The one top bar the home screen gets: same height and same flat fill as
  /// every other screen's app bar.
  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      titleSpacing: 0,
      leadingWidth: 52,
      title: const Text('Home Screen'),
      actions: [
        IconButton(
          tooltip: 'Restore project',
          icon: const Icon(Icons.unarchive_outlined, size: 20),
          onPressed: () => _restore(context),
        ),
        IconButton(
          tooltip: 'How it works',
          icon: const Icon(Icons.help_outline, size: 20),
          onPressed: () => _showAbout(context),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// The primary action: the app bar's own fill dropped onto the light page,
  /// so it is unmistakably the thing to tap without introducing a new hue.
  Widget _newProjectCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _startNewProject(context),
        child: Container(
          height: 98,
          decoration: BoxDecoration(
            gradient: AppColors.appBarGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppColors.glow(AppColors.appBar, opacity: 0.34),
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.onAppBar.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.onAppBar.withValues(alpha: 0.28),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.add,
                  color: AppColors.onAppBar,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'New Project',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAppBar,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Pick videos and photos to start',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.onAppBarDim,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.onAppBar,
                size: 21,
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _templateCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _startFromTemplate(context),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            gradient: AppColors.tint(AppColors.appBar),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.appBar.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppColors.appBarGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.onAppBar,
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Start from a template',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cuts, moves and titles already set up',
                      style: TextStyle(fontSize: 11, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.appBarMuted),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startFromTemplate(BuildContext context) async {
    final navigator = Navigator.of(context);
    final controller = context.read<ProjectsController>();

    final template = await navigator.push<VideoTemplate>(
      MaterialPageRoute(builder: (_) => const TemplateGalleryScreen()),
    );
    if (template == null) return;

    final paths = await navigator.push<List<String>>(
      MaterialPageRoute(
        builder: (_) => MediaPickerScreen(
          title: 'Pick ${template.slotCount} for ${template.name}',
        ),
      ),
    );
    if (paths == null || paths.isEmpty) return;

    final project = await controller.create(
      name: template.name,
      ratio: template.ratio,
    );
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          project: project,
          template: template,
          initialMedia: paths,
        ),
      ),
    );
    await controller.refresh();
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
    return SizedBox(
      // 102 = ListView vertical padding (14 + 6) + card padding (11 * 2) +
      // the 1px border on each side + the 54px the Column needs for its
      // icon, label and ratio rows. Anything tighter overflows by ~1px.
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        itemCount: tools.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final (icon, label, ratio, canvasRatio) = tools[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _startNewProject(context, ratio: canvasRatio),
            child: Container(
              width: 100,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: AppColors.tint(AppColors.appBar),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.appBar.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: AppColors.appBarMuted),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    ratio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(ProjectsController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              gradient: AppColors.appBarGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'Projects',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          if (!c.loading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: AppColors.appBar.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${c.projects.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.appBarMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              gradient: AppColors.tint(AppColors.appBar),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.appBar.withValues(alpha: 0.18),
              ),
            ),
            child: const Icon(
              Icons.movie_creation_outlined,
              size: 32,
              color: AppColors.appBarMuted,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No projects yet',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap New Project to begin',
            style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => AppTheme.onPopup(
        child: const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How it works',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onAppBar,
                ),
              ),
              SizedBox(height: 12),
              _Tip(
                icon: Icons.touch_app,
                text: 'Drag the timeline to scrub. The playhead stays centred.',
              ),
              _Tip(
                icon: Icons.pinch,
                text: 'Pinch the timeline to zoom in and out.',
              ),
              _Tip(
                icon: Icons.content_cut,
                text: 'Tap a clip, then Split to cut at the playhead.',
              ),
              _Tip(
                icon: Icons.movie_filter,
                text: 'Tap the ◇ between clips to add a transition.',
              ),
              _Tip(
                icon: Icons.file_download,
                text: 'Export renders with FFmpeg at up to 4K.',
              ),
            ],
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.onAppBar.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.onAppBar),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
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
