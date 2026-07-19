/// Picks the correct storage backend at compile time: real files on
/// mobile/desktop, SharedPreferences (small rolling cache) on web.
/// Both implementations expose the exact same API.
library;

export 'mushaf_storage_io.dart'
    if (dart.library.html) 'mushaf_storage_web.dart';
