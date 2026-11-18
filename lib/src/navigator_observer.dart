import 'package:flutter/widgets.dart';

import 'fictura.dart';

/// Records a `screen_viewed` each time a different page comes to the front.
///
/// ```dart
/// MaterialApp(navigatorObservers: [FicturaNavigatorObserver()], ...)
/// GoRouter(observers: [FicturaNavigatorObserver()], ...)
/// ```
///
/// Only [PageRoute]s with a name count by default, so dialogs, sheets and
/// unnamed routes don't become screens. Give routes a `name` (`RouteSettings`,
/// or `GoRoute(name: ...)`), or pass [nameExtractor] to name them yourself.
class FicturaNavigatorObserver extends NavigatorObserver {
  FicturaNavigatorObserver({
    this.nameExtractor = defaultNameExtractor,
    this.routeFilter = defaultRouteFilter,
  });

  /// The screen name for a route's settings, or null to skip it.
  final String? Function(RouteSettings settings) nameExtractor;

  /// Which routes are screens.
  final bool Function(Route<dynamic> route) routeFilter;

  static String? defaultNameExtractor(RouteSettings settings) => settings.name;

  static bool defaultRouteFilter(Route<dynamic> route) => route is PageRoute;

  String? _current;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _show(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _show(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _show(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Removing the page on screen brings the one below it to the front.
    if (route.isCurrent || _nameOf(route) == _current) _show(previousRoute);
  }

  String? _nameOf(Route<dynamic>? route) {
    if (route == null || !routeFilter(route)) return null;
    final name = nameExtractor(route.settings)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  void _show(Route<dynamic>? route) {
    final name = _nameOf(route);
    if (name == null || name == _current) return;
    _current = name;
    Fictura.screen(name);
  }
}
