import 'package:flutter/material.dart';

/// Overlay geometry (font sizes, sticker sizes) is authored against a virtual
/// canvas of this height. The preview scales by `previewHeight / this`, the
/// renderer by `outputHeight / this` — so the export matches the preview
/// pixel for pixel at any resolution.
const double kCanvasReferenceHeight = 1000.0;

/// Timeline zoom bounds, in pixels per second.
const double kMinPixelsPerSecond = 12.0;
const double kMaxPixelsPerSecond = 320.0;
const double kDefaultPixelsPerSecond = 60.0;

/// Height of each timeline lane.
const double kVideoTrackHeight = 56.0;
const double kLaneHeight = 26.0;
const double kLaneGap = 4.0;

/// Nothing on the timeline may become shorter than this.
const Duration kMinClipDuration = Duration(milliseconds: 200);

/// Autosave debounce after an edit.
const Duration kAutosaveDelay = Duration(milliseconds: 900);

/// Every screen's top bar is this tall — the Material default — so the header
/// never shifts height as you move between home, editor, picker and export.
const double kAppBarHeight = kToolbarHeight;
