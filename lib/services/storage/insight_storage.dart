// Platform-conditional storage for the ayah study layers — real files
// on mobile/desktop, inert on web (same split as the tafsir store).
export 'insight_storage_io.dart'
    if (dart.library.html) 'insight_storage_web.dart';
