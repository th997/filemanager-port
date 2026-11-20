import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'global_playback_service.dart';

/// Global RouteObserver for observing route changes across the app.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();

/// NavigatorObserver that monitors modal routes (dialogs, bottom sheets, popup menus)
/// to inform [GlobalPlaybackService] so the floating mini player bar can temporarily
/// hide and not obstruct modal sheets/dialogs.
class AppModalObserver extends NavigatorObserver {
  int _popupCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute) {
      _popupCount++;
      GlobalPlaybackService.instance.setModalActive(true);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PopupRoute) {
      _popupCount = math.max(0, _popupCount - 1);
      GlobalPlaybackService.instance.setModalActive(_popupCount > 0);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PopupRoute) {
      _popupCount = math.max(0, _popupCount - 1);
      GlobalPlaybackService.instance.setModalActive(_popupCount > 0);
    }
  }
}

final AppModalObserver appModalObserver = AppModalObserver();
