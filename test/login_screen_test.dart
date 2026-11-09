import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biometric_mobile/features/auth/login_screen.dart';

void main() {
  testWidgets('login shows the tinted campus photo behind the form card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pump();

    // The bundled campus photo fills the screen, cropped to cover.
    final photo = tester.widget<Image>(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/campus.jpg',
      ),
    );
    expect(photo.fit, BoxFit.cover);

    // Purple wash over it: top-left → bottom-right, matching the web portal.
    final wash = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .singleWhere((g) => g.colors.first == const Color(0xC73B1678));
    expect(wash.colors.last, const Color(0x6B6D28D9));
    expect(wash.begin, Alignment.topLeft);
    expect(wash.end, Alignment.bottomRight);

    // The form is still there, on top, and nothing overflows on a phone.
    expect(find.text('Colegio de Kidapawan'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
