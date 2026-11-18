import 'package:fictura_flutter/src/messages.g.dart';

/// The native side, recorded: every call Dart makes, with its arguments.
class FakeHost extends FicturaHostApi {
  final List<(String, List<Object?>)> calls = [];
  ConfigureMessage? configured;
  final List<ErrorMessage> errors = [];
  PlacementResultMessage registerAnswer = PlacementResultMessage(
    featureUnlocked: true,
    outcome: 'skipped',
    skipReason: 'no_audience_match',
  );
  bool throwOnTrack = false;

  List<List<Object?>> argsOf(String name) => [
    for (final c in calls)
      if (c.$1 == name) c.$2,
  ];

  @override
  Future<void> configure(ConfigureMessage message) async {
    configured = message;
    calls.add(('configure', [message]));
  }

  @override
  Future<void> track(String event, Map<String, Object?> properties) async {
    if (throwOnTrack) throw StateError('channel down');
    calls.add(('track', [event, properties]));
  }

  @override
  Future<void> screen(String name, Map<String, Object?> properties) async =>
      calls.add(('screen', [name, properties]));

  @override
  Future<void> identify(
    String userId,
    Map<String, Object?>? attributes,
  ) async => calls.add(('identify', [userId, attributes]));

  @override
  Future<void> reset() async => calls.add(('reset', []));

  @override
  Future<void> setAttributes(Map<String, Object?> attributes) async =>
      calls.add(('setAttributes', [attributes]));

  @override
  Future<void> setOnce(Map<String, Object?> attributes) async =>
      calls.add(('setOnce', [attributes]));

  @override
  Future<void> unsetAttribute(String key) async =>
      calls.add(('unsetAttribute', [key]));

  @override
  Future<void> registerSuperProperties(Map<String, Object?> properties) async =>
      calls.add(('registerSuperProperties', [properties]));

  @override
  Future<void> optOut() async => calls.add(('optOut', []));

  @override
  Future<void> optIn() async => calls.add(('optIn', []));

  @override
  Future<void> flush() async => calls.add(('flush', []));

  @override
  Future<String?> deviceId() async => 'ios-test-device';

  @override
  Future<void> setRevenueCatUserId(String? id) async =>
      calls.add(('setRevenueCatUserId', [id]));

  @override
  Future<void> setLegalUrls(String? terms, String? privacy) async =>
      calls.add(('setLegalUrls', [terms, privacy]));

  @override
  Future<void> setPurchaseHandlerEnabled(bool enabled) async =>
      calls.add(('setPurchaseHandlerEnabled', [enabled]));

  @override
  Future<PlacementResultMessage> register(
    String placement,
    Map<String, Object?> params,
  ) async {
    calls.add(('register', [placement, params]));
    return registerAnswer;
  }

  @override
  Future<bool> handleUrl(String url) async {
    calls.add(('handleUrl', [url]));
    return url.contains('growth_click');
  }

  @override
  Future<void> captureError(ErrorMessage error) async => errors.add(error);

  @override
  Future<void> captureMessage(String message, String level) async =>
      calls.add(('captureMessage', [message, level]));
}
