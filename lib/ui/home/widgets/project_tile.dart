import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/models/project.dart';
import '../../../data/services/thumbnail_service.dart';

/// One row in the project library: cover, name, length, ratio and a menu.
class ProjectTile extends StatefulWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
    required this.onBackup,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onBackup;

  /// How tall one tile is on this window. The grid on wide screens needs the
  /// number up front; the phone list lets the tile size itself to the same
  /// value through its cover.
  static double extentFor(BuildContext context) {
    final r = context.r;
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    // The row is as tall as the cover, unless a large system font makes the
    // name/chips/date stack the taller of the two.
    final content = 62 * textScale + r.vp(10);
    return math.max(r.dp(76), content) + r.dp(20) + 2;
  }

  @override
  State<ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<ProjectTile> {
  String? _cover;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant ProjectTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.updatedAt != widget.project.updatedAt) _loadCover();
  }

  Future<void> _loadCover() async {
    final p = widget.project;
    if (p.coverPath != null && await File(p.coverPath!).exists()) {
      if (mounted) setState(() => _cover = p.coverPath);
      return;
    }
    if (p.clips.isEmpty) return;
    final first = p.clips.first;
    if (first.isImage) {
      if (mounted) setState(() => _cover = first.path);
      return;
    }
    final frame = await ThumbnailService.instance
        .cover(first.path, at: first.trimStart + const Duration(milliseconds: 300));
    if (mounted && frame != null) setState(() => _cover = frame);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final r = context.r;
    final cover = r.dp(76);
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: EdgeInsets.all(r.dp(10)),
        decoration: BoxDecoration(
          gradient: AppColors.tint(AppColors.appBar),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.appBar.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: SizedBox(
                width: cover,
                height: cover,
                child: _cover != null
                    ? Image.file(File(_cover!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(r))
                    : _placeholder(r),
              ),
            ),
            SizedBox(width: r.dp(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: r.sp(14), fontWeight: FontWeight.w600)),
                  SizedBox(height: r.vp(5)),
                  // The three chips are short, but a long duration on a narrow
                  // phone would still push them past the row; letting the strip
                  // scroll keeps them intact instead of clipping the last one.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(r, p.totalDuration.pretty, lead: true),
                        SizedBox(width: r.dp(6)),
                        _chip(r, p.ratio.label),
                        SizedBox(width: r.dp(6)),
                        _chip(r,
                            '${p.clips.length} clip${p.clips.length == 1 ? '' : 's'}'),
                      ],
                    ),
                  ),
                  SizedBox(height: r.vp(5)),
                  Text(_relative(p.updatedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: r.sp(10.5), color: AppColors.textFaint)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  size: r.ic(19), color: AppColors.textDim),
              onSelected: (v) => switch (v) {
                'rename' => widget.onRename(),
                'duplicate' => widget.onDuplicate(),
                'backup' => widget.onBackup(),
                'delete' => widget.onDelete(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                PopupMenuItem(value: 'backup', child: Text('Back up')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.dangerSoft))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Stand-in cover until the first frame is decoded: the header fill, so a
  /// tile with no thumbnail still belongs to the rest of the page.
  Widget _placeholder(Responsive r) => Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        alignment: Alignment.center,
        child: Icon(Icons.movie_outlined,
            color: AppColors.onAppBarDim, size: r.ic(24)),
      );

  /// [lead] marks the one chip that carries the header tone — the length,
  /// which is what the eye should land on first.
  Widget _chip(Responsive r, String text, {bool lead = false}) => Container(
        padding: EdgeInsets.symmetric(horizontal: r.dp(7), vertical: 2.5),
        decoration: BoxDecoration(
          color: lead
              ? AppColors.appBar.withValues(alpha: 0.12)
              : AppColors.textFaint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                fontSize: r.sp(9.5),
                fontWeight: FontWeight.w600,
                color: lead ? AppColors.appBarMuted : AppColors.textDim)),
      );

  static String _relative(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}
