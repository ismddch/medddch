// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  // ── iOS ──────────────────────────────────────────────────────────────────
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'AIzaSyAvQQHGiopuO5a6viYmKYwI-InXCjuWCbA',
    appId:             '1:1021639563963:ios:6716932c5dd6498749a79e',
    messagingSenderId: '1021639563963',
    projectId:         'hallaqak',
    storageBucket:     'hallaqak.firebasestorage.app',
    iosBundleId:       'com.hallaqak.app',
  );

  // ── macOS ─────────────────────────────────────────────────────────────────
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey:            'AIzaSyAvQQHGiopuO5a6viYmKYwI-InXCjuWCbA',
    appId:             '1:1021639563963:ios:6716932c5dd6498749a79e',
    messagingSenderId: '1021639563963',
    projectId:         'hallaqak',
    storageBucket:     'hallaqak.firebasestorage.app',
    iosBundleId:       'com.hallaqak.app',
  );

  // ── Android ──────────────────────────────────────────────────────────────
  // To get real Android values:
  //   1. Firebase Console → Project Settings → Add app → Android
  //   2. Package name: com.hallaqak.app
  //   3. Download google-services.json → place in android/app/
  //   4. Copy GOOGLE_APP_ID from that file here.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAvQQHGiopuO5a6viYmKYwI-InXCjuWCbA',
    appId:             '1:1021639563963:android:REPLACE_WITH_ANDROID_APP_ID',
    messagingSenderId: '1021639563963',
    projectId:         'hallaqak',
    storageBucket:     'hallaqak.firebasestorage.app',
  );

  // ── Web ───────────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'AIzaSyAvQQHGiopuO5a6viYmKYwI-InXCjuWCbA',
    appId:             '1:1021639563963:web:REPLACE_WITH_WEB_APP_ID',
    messagingSenderId: '1021639563963',
    projectId:         'hallaqak',
    storageBucket:     'hallaqak.firebasestorage.app',
    authDomain:        'hallaqak.firebaseapp.com',
  );

  // ── Windows ───────────────────────────────────────────────────────────────
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey:            'AIzaSyAvQQHGiopuO5a6viYmKYwI-InXCjuWCbA',
    appId:             '1:1021639563963:web:REPLACE_WITH_WEB_APP_ID',
    messagingSenderId: '1021639563963',
    projectId:         'hallaqak',
    storageBucket:     'hallaqak.firebasestorage.app',
    authDomain:        'hallaqak.firebaseapp.com',
  );
}
