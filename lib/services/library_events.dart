import 'package:flutter/foundation.dart';

class LibraryChangeNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// App-wide change signals for the user's saved library (bookmarks and
/// highlights). The tab screens in MainScreen live inside an
/// IndexedStack and are never rebuilt from scratch when the user
/// switches tabs, so they cannot rely on initState to pick up entries
/// added elsewhere (e.g. from the reader's options sheet). Services
/// ping these after every mutation; the list screens listen and reload.
class LibraryEvents {
  static final LibraryChangeNotifier bookmarks = LibraryChangeNotifier();
  static final LibraryChangeNotifier highlights = LibraryChangeNotifier();

  /// Pinged when khatma progress changes outside the khatma screen
  /// (auto-completion of a juz while reading).
  static final LibraryChangeNotifier khatma = LibraryChangeNotifier();

  /// Pinged when the prayer-times configuration (city/method) changes.
  static final LibraryChangeNotifier prayer = LibraryChangeNotifier();
}
