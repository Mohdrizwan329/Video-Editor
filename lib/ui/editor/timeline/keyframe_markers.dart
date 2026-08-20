import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/keyframe.dart';

/// The row of diamonds drawn under a selected clip or layer, one per
/// keyframe offset. Tapping one seeks to it.
class KeyframeMarkers extends StatelessWidget {
  const KeyframeMarkers({
    super.key,
    required this.owner,
    required this.pixelsPerSecond,
    required this.width,
    required this.onSeek,
    this.height = 12,
  });

  final Keyframable owner;
  final double pixelsPerSecond;
  final double width;

  /// Called with the offset inside the owner, not absolute timeline time.
  final void Function(Duration local) onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    final times = owner.keyframeTimes;
    if (times.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final t in times)
            Positioned(
              left: t.inMicroseconds / 1e6 * pixelsPerSecond - height / 2,
              top: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSeek(t),
                child: SizedBox(
                  width: height,
                  height: height,
                  child: Center(
                    child: Transform.rotate(
                      angle: 0.785,
                      child: Container(
                        width: height * 0.55,
                        height: height * 0.55,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          border: Border.all(
                              color: AppColors.background, width: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
