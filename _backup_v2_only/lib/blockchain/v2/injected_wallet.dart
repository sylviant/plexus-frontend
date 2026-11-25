// Picks the real browser-wallet code on web and a harmless stand-in everywhere else.
export 'injected_wallet_stub.dart' if (dart.library.js_interop) 'injected_wallet_web.dart';
