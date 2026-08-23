import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/ui/widgets/app_logo.dart';

/// The brand mark is one shared widget, so these checks cover every platform
/// the app builds for — the launcher icons are the platforms' own copies of
/// the same artwork.
void main() {
  testWidgets('AppLogo paints the bundled logo asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AppLogo())),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, AppLogo.asset);
  });

  testWidgets('AppLogo fills the size it is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: AppLogo(size: 120, glow: true))),
      ),
    );

    expect(tester.getSize(find.byType(AppLogo)), const Size(120, 120));
  });
}
