import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/duration_ext.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/template.dart';
import '../../data/models/template_library.dart';
import '../widgets/panel_shell.dart';

/// Template picker. Choosing one returns it so the caller can collect media
/// and hand both to [TemplateApplier].
class TemplateGalleryScreen extends StatefulWidget {
  const TemplateGalleryScreen({super.key});

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  int _category = 0;

  @override
  Widget build(BuildContext context) {
    final category = TemplateLibrary.categories[_category];
    final items = TemplateLibrary.byCategory(category);

    final r = context.r;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Templates'),
        leading: IconButton(
          icon: Icon(Icons.close, size: r.ic(21)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ContentBox(
          child: Column(
            children: [
              SizedBox(height: r.vp(6)),
              ChipStrip(
                labels: TemplateLibrary.categories,
                selectedIndex: _category,
                onSelected: (i) => setState(() => _category = i),
              ),
              SizedBox(height: r.vp(12)),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    r.gutter,
                    0,
                    r.gutter,
                    r.vp(24),
                  ),
                  // Two cards across a phone; wider windows add columns at the
                  // same card size rather than blowing each card up.
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: r.isCompact
                        ? (r.width - r.gutter * 2 - 12) / 2
                        : 240,
                    crossAxisSpacing: r.dp(12),
                    mainAxisSpacing: r.dp(12),
                    childAspectRatio: r.isShort && r.isLandscape ? 0.9 : 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _TemplateCard(
                    template: items[i],
                    index: i,
                    onTap: () => Navigator.pop(context, items[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.index,
    required this.onTap,
  });

  final VideoTemplate template;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.tint(AppColors.appBar),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: AppColors.appBar.withValues(alpha: 0.16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: _preview(r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                r.dp(10),
                r.vp(8),
                r.dp(10),
                r.vp(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: r.sp(13), fontWeight: FontWeight.w700)),
                  SizedBox(height: r.vp(3)),
                  Text(template.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: r.sp(10),
                          color: AppColors.textFaint,
                          height: 1.3)),
                  SizedBox(height: r.vp(6)),
                  // The chips are laid out by what fits: on a narrow card they
                  // drop to a second line instead of clipping the ratio.
                  Wrap(
                    spacing: r.dp(5),
                    runSpacing: r.vp(4),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _chip(r, '${template.slotCount} clips'),
                      _chip(r, template.approximateDuration.pretty),
                      Text(template.ratio.label,
                          style: TextStyle(
                              fontSize: r.sp(9), color: AppColors.textFaint)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Schematic preview: the slot layout drawn as blocks, so the card conveys
  /// the rhythm of the edit without needing a rendered sample video.
  Widget _preview(Responsive r) {
    final aspect = template.ratio.value ?? 9 / 16;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
                AppColors.appBar.withValues(alpha: 0.14),
                AppColors.surfaceHigh),
            AppColors.surfaceHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(r.dp(12)),
          child: AspectRatio(
            aspectRatio: aspect,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF262046), Color(0xFF14112A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.onAppBar.withValues(alpha: 0.22),
                    width: 0.8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (template.texts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        template.texts.first.placeholder,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: r.sp(9),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  // One bar per slot, width proportional to its duration.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        for (final slot in template.slots)
                          Expanded(
                            flex: slot.duration.inMilliseconds.clamp(1, 99999),
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 0.8),
                              decoration: BoxDecoration(
                                color: AppColors.onAppBarDim,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (template.stickers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        template.stickers.map((s) => s.$1).take(3).join(' '),
                        style: TextStyle(fontSize: r.sp(11)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(Responsive r, String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: r.dp(6), vertical: r.dp(2)),
        decoration: BoxDecoration(
          color: AppColors.appBar.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: r.sp(8.5),
                fontWeight: FontWeight.w600,
                color: AppColors.appBarMuted)),
      );
}
