import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/duration_ext.dart';
import '../../core/utils/responsive.dart';
import '../../data/services/media_library.dart';
import 'widgets/asset_thumb.dart';

/// Gallery picker with ordered multi-select, an album switcher and a
/// selection strip — the entry flow for starting a project.
class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({
    super.key,
    this.title = 'Select media',
    this.filter = RequestType.common,
    this.maxSelection,
  });

  final String title;
  final RequestType filter;
  final int? maxSelection;

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  final MediaLibrary _library = MediaLibrary.instance;
  final ScrollController _scroll = ScrollController();

  List<GalleryAlbum> _albums = [];
  GalleryAlbum? _album;
  final List<GalleryItem> _items = [];
  final List<GalleryItem> _selected = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _permissionDenied = false;
  int _page = 0;
  int _tab = 0;

  static const List<(String, RequestType)> _tabs = [
    ('All', RequestType.common),
    ('Video', RequestType.video),
    ('Photo', RequestType.image),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    if (!_library.supportsGallery) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }
    final granted = await _library.ensurePermission();
    if (!granted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }
    final albums = await _library.albums(type: _tabs[_tab].$2);
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _album = albums.isNotEmpty ? albums.first : null;
      _loading = false;
    });
    await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _exhausted = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || _loadingMore || _exhausted) return;
    setState(() => _loadingMore = true);
    final batch = await _library.assets(album, page: _page);
    if (!mounted) return;
    setState(() {
      _items.addAll(batch);
      _page++;
      _exhausted = batch.isEmpty;
      _loadingMore = false;
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  void _toggle(GalleryItem item) {
    setState(() {
      final i = _selected.indexWhere((e) => e.id == item.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        if (widget.maxSelection != null &&
            _selected.length >= widget.maxSelection!) {
          return;
        }
        _selected.add(item);
      }
    });
  }

  Future<void> _browseFiles() async {
    final picked = await _library.pickFiles(
      kind: switch (_tabs[_tab].$2) {
        RequestType.video => PickKind.video,
        RequestType.image => PickKind.image,
        _ => PickKind.media,
      },
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _selected.addAll(picked));
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      ),
    );
    final paths = <String>[];
    for (final item in _selected) {
      final p = await item.resolvePath();
      if (p != null && await File(p).exists()) paths.add(p);
    }
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.pop(context, paths);
  }

  @override
  Widget build(BuildContext context) {
    // The bottom of this screen changes with the selection: the white strip
    // when something is picked, the page fill when nothing is.
    final strip = _selected.isNotEmpty;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: strip
            ? AppColors.surface
            : AppColors.background,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.close, size: context.r.ic(22)),
            onPressed: () => Navigator.pop(context),
          ),
          title: _albumSelector(),
          actions: [
            IconButton(
              tooltip: 'Browse files',
              icon: Icon(Icons.folder_open, size: context.r.ic(20)),
              onPressed: _browseFiles,
            ),
          ],
        ),
        body: Column(
          children: [
            _tabBar(),
            Expanded(child: _grid()),
            if (strip) _selectionStrip(),
          ],
        ),
      ),
    );
  }

  Widget _albumSelector() {
    if (_albums.isEmpty) {
      return Text(widget.title, style: const TextStyle(fontSize: 15));
    }
    return PopupMenuButton<GalleryAlbum>(
      onSelected: (a) {
        setState(() => _album = a);
        _reload();
      },
      itemBuilder: (_) => _albums
          .map(
            (a) => PopupMenuItem(
              value: a,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${a.count}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onAppBarDim,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _album?.name ?? widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }

  Widget _tabBar() {
    final r = context.r;
    return SizedBox(
      height: r.vp(40),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(width: r.dp(12)),
          for (var i = 0; i < _tabs.length; i++) ...[
            GestureDetector(
              onTap: () {
                setState(() => _tab = i);
                _bootstrap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(
                  horizontal: r.dp(16),
                  vertical: r.vp(7),
                ),
                decoration: BoxDecoration(
                  gradient: _tab == i ? AppColors.appBarGradient : null,
                  color: _tab == i ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  _tabs[i].$1,
                  style: TextStyle(
                    fontSize: r.sp(12.5),
                    fontWeight: FontWeight.w700,
                    color: _tab == i ? AppColors.onAppBar : AppColors.textDim,
                  ),
                ),
              ),
            ),
            SizedBox(width: r.dp(8)),
          ],
        ],
      ),
    );
  }

  Widget _grid() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 2,
        ),
      );
    }
    if (_permissionDenied && _items.isEmpty) {
      return _permissionFallback();
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Nothing here',
          style: TextStyle(color: AppColors.textFaint, fontSize: 13),
        ),
      );
    }
    // Four thumbnails across a phone; on a tablet, a desktop window or a
    // browser the same thumbnail size simply yields more columns, instead of
    // four enormous tiles.
    final r = context.r;
    final target = r.pick<double>(
      compact: r.width / 4,
      medium: 150,
      expanded: 170,
      large: 190,
    );
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(2),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: target,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        final order = _selected.indexWhere((e) => e.id == item.id);
        return AssetThumb(
          item: item,
          orderIndex: order,
          onTap: () => _toggle(item),
        );
      },
    );
  }

  Widget _permissionFallback() {
    final r = context.r;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: r.gutter + r.dp(14),
          vertical: r.vp(24),
        ),
        child: ContentBox(
          maxWidth: 420,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: r.dp(72),
              height: r.dp(72),
              decoration: BoxDecoration(
                gradient: AppColors.tint(AppColors.appBar),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.appBar.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: r.ic(30),
                color: AppColors.appBarMuted,
              ),
            ),
            SizedBox(height: r.vp(14)),
            Text(
              'Gallery access is off',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: r.sp(14), fontWeight: FontWeight.w600),
            ),
            SizedBox(height: r.vp(6)),
            Text(
              'Grant photo access, or pick files directly from storage.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: r.sp(12), color: AppColors.textDim),
            ),
            SizedBox(height: r.vp(18)),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  // The bare button inherits the accent, which only clears
                  // 2.7:1 on the light page.
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.appBarMuted,
                    side: BorderSide(
                        color: AppColors.appBar.withValues(alpha: 0.35)),
                  ),
                  onPressed: () => PhotoManager.openSetting(),
                  child: const Text('Open settings'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                  ),
                  onPressed: _browseFiles,
                  child: const Text('Browse files'),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _selectionStrip() {
    final totalDuration = _selected.fold<Duration>(
      Duration.zero,
      (sum, e) => sum + e.duration,
    );
    final r = context.r;
    final thumb = r.dp(52);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: r.dp(10),
        vertical: r.vp(8),
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: ContentBox(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: thumb + 4,
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                itemCount: _selected.length,
                onReorder: (from, to) {
                  setState(() {
                    if (to > from) to--;
                    _selected.insert(to, _selected.removeAt(from));
                  });
                },
                itemBuilder: (context, i) {
                  final item = _selected[i];
                  return ReorderableDragStartListener(
                    key: ValueKey('sel_${item.id}_$i'),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: thumb,
                              height: thumb,
                              child: AssetThumb(
                                item: item,
                                orderIndex: -1,
                                compact: true,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: GestureDetector(
                              onTap: () => _toggle(item),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black87,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: r.vp(8)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selected.length} selected · ${totalDuration.pretty}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: r.sp(11.5),
                      color: AppColors.textDim,
                    ),
                  ),
                ),
                SizedBox(width: r.dp(10)),
                InkWell(
                  onTap: _confirm,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: r.dp(104),
                    height: r.tap(40),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.appBarGradient,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow:
                          AppColors.glow(AppColors.appBar, opacity: 0.34),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Next',
                          style: TextStyle(
                            fontSize: r.sp(14),
                            fontWeight: FontWeight.w800,
                            color: AppColors.onAppBar,
                          ),
                        ),
                        SizedBox(width: r.dp(4)),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: r.ic(16),
                          color: AppColors.onAppBar,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}
