import 'head_gestures.dart';

/// Off the web there's no [WebHeadTracker]: Android and iOS use ML Kit
/// ([HeadTracker]).
HeadTracking? webHeadTracking(void Function(HeadGesture) onGesture) => null;
