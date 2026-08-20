import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// What kind of file a browse should offer.
enum PickKind { media, video, image, audio }

/// One row in the picker grid, regardless of whether it came from the system
/// gallery or a file-system browse.
class GalleryItem {
  GalleryItem({
    required this.id,
    required this.isVideo,
    required this.duration,
    this.asset,
    this.filePath,
    this.title,
  });

  final String id;
  final bool isVideo;
  final Duration duration;

  /// Present when the item came from [PhotoManager].
  final AssetEntity? asset;

  /// Present when the item came from the file picker.
  final String? filePath;
  final String? title;

  Future<String?> resolvePath() async {
    if (filePath != null) return filePath;
    final f = await asset?.file;
    return f?.path;
  }
}

/// A gallery album/bucket.
class GalleryAlbum {
  GalleryAlbum({required this.id, required this.name, required this.count, this.path});

  final String id;
  final String name;
  final int count;
  final AssetPathEntity? path;
}

/// Gallery access. Uses [PhotoManager] where the platform has a real photo
/// library and transparently falls back to a file browse everywhere else.
class MediaLibrary {
  MediaLibrary._();

  static final MediaLibrary instance = MediaLibrary._();

  bool _permissionChecked = false;
  bool _granted = false;

  bool get supportsGallery =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<bool> ensurePermission() async {
    if (!supportsGallery) return false;
    if (_permissionChecked) return _granted;
    _permissionChecked = true;
    try {
      final state = await PhotoManager.requestPermissionExtend();
      _granted = state.isAuth || state.hasAccess;
    } catch (e) {
      debugPrint('photo permission failed: $e');
      _granted = false;
    }
    return _granted;
  }

  Future<List<GalleryAlbum>> albums({RequestType type = RequestType.common}) async {
    if (!await ensurePermission()) return const [];
    final paths = await PhotoManager.getAssetPathList(
      type: type,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    final out = <GalleryAlbum>[];
    for (final p in paths) {
      out.add(GalleryAlbum(
        id: p.id,
        name: p.isAll ? 'Recent' : p.name,
        count: await p.assetCountAsync,
        path: p,
      ));
    }
    return out;
  }

  Future<List<GalleryItem>> assets(
    GalleryAlbum album, {
    int page = 0,
    int size = 90,
  }) async {
    final p = album.path;
    if (p == null) return const [];
    final entities = await p.getAssetListPaged(page: page, size: size);
    return entities
        .map((a) => GalleryItem(
              id: a.id,
              isVideo: a.type == AssetType.video,
              duration: Duration(seconds: a.duration),
              asset: a,
              title: a.title,
            ))
        .toList();
  }

  /// Browse the file system — the only path on desktop, and a manual escape
  /// hatch on mobile when gallery permission is denied.
  Future<List<GalleryItem>> pickFiles({
    bool allowMultiple = true,
    PickKind kind = PickKind.media,
    List<String>? extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: extensions != null
          ? FileType.custom
          : switch (kind) {
              PickKind.media => FileType.media,
              PickKind.video => FileType.video,
              PickKind.image => FileType.image,
              PickKind.audio => FileType.audio,
            },
      allowedExtensions: extensions,
    );
    if (result == null) return const [];
    return result.files
        .where((f) => f.path != null)
        .map((f) => GalleryItem(
              id: f.path!,
              isVideo: !_looksLikeImage(f.path!),
              duration: Duration.zero,
              filePath: f.path,
              title: f.name,
            ))
        .toList();
  }

  Future<List<GalleryItem>> pickAudio() =>
      pickFiles(extensions: ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg']);

  static bool _looksLikeImage(String path) {
    const ext = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp', 'gif'};
    return ext.contains(path.split('.').last.toLowerCase());
  }

  /// Copy a picked file into app storage so a later gallery change or a
  /// cache eviction cannot break an open project.
  Future<String> materialise(String sourcePath, Directory into) async {
    final name = sourcePath.split(Platform.pathSeparator).last;
    final target = File('${into.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
    await File(sourcePath).copy(target.path);
    return target.path;
  }
}
