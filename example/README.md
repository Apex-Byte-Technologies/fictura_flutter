# fictura_flutter example

A small app that exercises every part of `fictura_flutter`: events, sign-in, a named-route screen, a placement with a paywall, a demo purchase handler, handled and uncaught Dart errors, and flush.

```bash
flutter run --dart-define=FICTURA_API_KEY=gk_... \
  --dart-define=FICTURA_API_BASE=http://localhost:4000 \
  --dart-define=FICTURA_DEMO_PLACEMENT=pro_feature
```

The Android emulator reaches the Mac at `http://10.0.2.2:4000`. `integration_test/` runs the same calls without a person; the package README's "Testing" section has the commands.
