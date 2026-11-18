import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A bare app with named page routes and a dialog-like popup route.
Widget app(FicturaNavigatorObserver observer, GlobalKey<NavigatorState> nav) =>
    WidgetsApp(
      navigatorKey: nav,
      color: const Color(0xFFFFFFFF),
      navigatorObservers: [observer],
      initialRoute: 'Home',
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        pageBuilder: (_, _, _) =>
            Text(settings.name ?? '', textDirection: TextDirection.ltr),
      ),
    );

class _Popup extends PopupRoute<void> {
  _Popup() : super(settings: const RouteSettings(name: 'Sheet'));
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
  ) => const SizedBox();
}

void main() {
  late FakeHost host;
  List<String> screens() => [
    for (final a in host.argsOf('screen')) a[0] as String,
  ];

  setUp(() async {
    host = FakeHost();
    Fictura.debugReset(host: host);
    await Fictura.configure(
      apiKey: 'gk_test',
      options: const FicturaOptions(captureDartErrors: false),
    );
  });

  tearDown(() => Fictura.debugReset());

  testWidgets('records named pages as they come to the front, once each time', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(FicturaNavigatorObserver(), nav));
    nav.currentState!.pushNamed('Cart');
    await tester.pumpAndSettle();
    nav.currentState!.pushNamed('Checkout');
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    nav.currentState!.pushReplacementNamed('Receipt');
    await tester.pumpAndSettle();
    expect(screens(), ['Home', 'Cart', 'Checkout', 'Cart', 'Receipt']);
  });

  testWidgets(
    'dialogs and sheets are not screens, and closing one does not repeat the page',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(FicturaNavigatorObserver(), nav));
      nav.currentState!.push(_Popup());
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(screens(), ['Home']);
    },
  );

  testWidgets('a name extractor can rename or skip routes', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    final observer = FicturaNavigatorObserver(
      nameExtractor: (s) => s.name == 'Cart' ? null : 'screen:${s.name}',
    );
    await tester.pumpWidget(app(observer, nav));
    nav.currentState!.pushNamed('Cart');
    await tester.pumpAndSettle();
    nav.currentState!.pushNamed('Checkout');
    await tester.pumpAndSettle();
    expect(screens(), ['screen:Home', 'screen:Checkout']);
  });
}
