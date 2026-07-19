// Platform-conditional storage for downloaded tafsir editions —
// real files on mobile/desktop, disabled on web (browser storage is
// far too small for full tafsir texts).
export 'tafsir_storage_io.dart'
    if (dart.library.html) 'tafsir_storage_web.dart';
