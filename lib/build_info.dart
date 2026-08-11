/// Which build of the app this is.
///
/// The marketing version is deliberately FROZEN until there is a real
/// release. Until then every rebuild only advances [kBuildNumber], which
/// is enough to tell two sideloaded builds apart on the phone — bumping
/// 1.7.x on every small change made the version meaningless.
///
/// Keep [kBuildNumber] equal to the `+N` in pubspec.yaml: the store/OS
/// needs it there to treat a new build as an upgrade, and the About
/// screen reads it from here.
const String kAppVersion = '1.7.2';
const int kBuildNumber = 65;

/// "1.7.2 (58)" — what to show the reader and what to quote in a bug
/// report.
String get kVersionLabel => '$kAppVersion ($kBuildNumber)';
