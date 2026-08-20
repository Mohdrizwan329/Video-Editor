import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/duration_ext.dart';
import '../../../data/services/media_library.dart';
import '../../../data/services/thumbnail_service.dart';

/// A single gallery cell: thumbnail, video badge and the ordered selection
/// marker shown when an item is picked.
class AssetThumb extends StatefulWidget {
  const AssetThumb({
    super.key,
    required this.item,
    required this.orderIndex,
    this.onTap,
    this.compact = false,
  });

  final GalleryItem item;

  /// Position in the selection, or -1 when not selected.
  final int orderIndex;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<AssetThumb> {
  Uint8List? _bytes;
  String? _filePath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final item = widget.item;
    if (item.asset != null) {
      final data = await item.asset!
          .thumbnailDataWithSize(const ThumbnailSize.square(240));
      if (mounted) setState(() => _bytes = data);
      return;
    }
    final path = item.filePath;
    if (path == null) return;
    if (!item.isVideo) {
      if (mounted) setState(() => _filePath = path);
      return;
    }
    final frame = await ThumbnailService.instance
        .frame(path, const Duration(milliseconds: 500), height: 200);
    if (mounted && frame != null) setState(() => _filePath = frame);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.orderIndex >= 0;
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppColors.surfaceHigh),
          if (_bytes != null)
            Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true)
          else if (_filePath != null)
            Image.file(File(_filePath!),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox())
          else
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.4, color: AppColors.textFaint),
              ),
            ),
          if (widget.item.isVideo && !widget.compact)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.item.duration > Duration.zero
                      ? widget.item.duration.mmss
                      : 'video',
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                ),
              ),
            ),
          if (selected)
            Container(color: AppColors.accent.withValues(alpha: 0.22)),
          if (selected)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${widget.orderIndex + 1}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAccent)),
              ),
            ),
        ],
      ),
    );
  }
}
