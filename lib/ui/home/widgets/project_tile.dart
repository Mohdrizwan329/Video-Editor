import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
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
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(10),
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
                width: 76,
                height: 76,
                child: _cover != null
                    ? Image.file(File(_cover!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder())
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _chip(p.totalDuration.pretty, lead: true),
                      const SizedBox(width: 6),
                      _chip(p.ratio.label),
                      const SizedBox(width: 6),
                      _chip('${p.clips.length} clip${p.clips.length == 1 ? '' : 's'}'),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(_relative(p.updatedAt),
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textFaint)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  size: 19, color: AppColors.textDim),
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
  Widget _placeholder() => Container(
        decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
        alignment: Alignment.center,
        child: const Icon(Icons.movie_outlined,
            color: AppColors.onAppBarDim, size: 24),
      );

  /// [lead] marks the one chip that carries the header tone — the length,
  /// which is what the eye should land on first.
  Widget _chip(String text, {bool lead = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: lead
              ? AppColors.appBar.withValues(alpha: 0.12)
              : AppColors.textFaint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 9.5,
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
