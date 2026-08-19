/// Which build of the app this is.
///
/// 1.7.2 was the first version submitted, and Apple approved it — which
/// is also why it can never be built again: App Store Connect closes a
/// version train to new build submissions once it reaches that state
/// ("Invalid Pre-Release Train... is closed for new build submissions").
/// So a marketing bump is no longer optional the way "1.7.x was frozen
/// to keep it meaningful" once meant; it is required every time a
/// version has gone out for review, approved or not.
///
/// Keep [kBuildNumber] equal to the `+N` in pubspec.yaml, and keep BOTH
/// climbing across a marketing bump rather than restarting at 1 — Apple
/// requires the real build number to keep increasing across every
/// version for this bundle ID, so a local counter that resets on every
/// 1.7.x → 1.7.y is misleading about where the count actually is.
///
/// It is still only a LOCAL record, and can still read low: codemagic
/// .yaml's iOS workflow overrides the number actually uploaded with
/// TestFlight's own latest + 1 at build time, which is the one Apple's
/// rule is really about. This constant just tries to track it, for the
/// About screen and bug reports.
const String kAppVersion = '1.7.3';
const int kBuildNumber = 93;

/// "1.7.3 (80)" — what to show the reader and what to quote in a bug
/// report. May read a lower build number than what is actually live on
/// TestFlight/the App Store; see the class doc.
String get kVersionLabel => '$kAppVersion ($kBuildNumber)';
