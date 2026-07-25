/// Static metadata for the standard 604-page Madani Mushaf layout:
/// surah names, surah start pages, juz start pages, and hizb start pages.
///
/// This is used for page headers (surah name / juz number / hizb number)
/// because the quranpedia JSON metadata is incomplete on some pages
/// (surahNumber: 0), so header info is derived from the well-known fixed
/// layout of the standard Madani Mushaf instead.
class QuranPageMeta {
  QuranPageMeta._();

  static const List<String> surahNames = [
    'الفاتحة','البقرة','آل عمران','النساء','المائدة','الأنعام','الأعراف','الأنفال',
    'التوبة','يونس','هود','يوسف','الرعد','إبراهيم','الحجر','النحل','الإسراء',
    'الكهف','مريم','طه','الأنبياء','الحج','المؤمنون','النور','الفرقان','الشعراء',
    'النمل','القصص','العنكبوت','الروم','لقمان','السجدة','الأحزاب','سبأ','فاطر',
    'يس','الصافات','ص','الزمر','غافر','فصلت','الشورى','الزخرف','الدخان',
    'الجاثية','الأحقاف','محمد','الفتح','الحجرات','ق','الذاريات','الطور','النجم',
    'القمر','الرحمن','الواقعة','الحديد','المجادلة','الحشر','الممتحنة','الصف',
    'الجمعة','المنافقون','التغابن','الطلاق','التحريم','الملك','القلم','الحاقة',
    'المعارج','نوح','الجن','المزمل','المدثر','القيامة','الإنسان','المرسلات',
    'النبأ','النازعات','عبس','التكوير','الانفطار','المطففين','الانشقاق','البروج',
    'الطارق','الأعلى','الغاشية','الفجر','البلد','الشمس','الليل','الضحى','الشرح',
    'التين','العلق','القدر','البينة','الزلزلة','العاديات','القارعة','التكاثر',
    'العصر','الهمزة','الفيل','قريش','الماعون','الكوثر','الكافرون','النصر',
    'المسد','الإخلاص','الفلق','الناس',
  ];

  /// First page of each surah (index 0 = surah 1) in the 604-page Mushaf.
  /// FIXED: surah 90 (Al-Balad) was previously wrongly recorded as 593
  /// instead of 594, which shifted every surah after it by one page and
  /// caused surah 112 (Al-Ikhlas) to silently disappear from page 604's
  /// header. Verified against the standard King Fahd Complex layout.
  /// FIXED: surah 103 (Al-Asr) was recorded as 600; the Mushaf page data
  /// places its first ayah on 601 (page 600 ends with At-Takathur), so
  /// "go to surah" opened the wrong page and page headers were off.
  /// The whole table was cross-checked against the page metadata and
  /// this was the only remaining mismatch.
  static const List<int> surahStartPages = [
    1, 2, 50, 77, 106, 128, 151, 177, 187, 208,
    221, 235, 249, 255, 262, 267, 282, 293, 305, 312,
    322, 332, 342, 350, 359, 367, 377, 385, 396, 404,
    411, 415, 418, 428, 434, 440, 446, 453, 458, 467,
    477, 483, 489, 496, 499, 502, 507, 511, 515, 518,
    520, 523, 526, 528, 531, 534, 537, 542, 545, 549,
    551, 553, 554, 556, 558, 560, 562, 564, 566, 568,
    570, 572, 574, 575, 577, 578, 580, 582, 583, 585,
    586, 587, 587, 589, 590, 591, 591, 592, 593, 594,
    595, 595, 596, 596, 597, 597, 598, 598, 599, 599,
    600, 600, 601, 601, 601, 602, 602, 602, 603, 603,
    603, 604, 604, 604,
  ];

  /// Number of ayahs in each surah (index 0 = surah 1). Totals 6236.
  static const List<int> ayahCounts = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
    123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
    34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
    54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
    60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
    29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
    15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
    5, 4, 5, 6,
  ];

  /// Converts a (surah, ayah-in-surah) pair to the GLOBAL sequential
  /// ayah number (1-6236) used by the audio CDN and Ayah.number.
  static int globalAyahNumber(int surahNumber, int ayahInSurah) {
    var total = 0;
    for (var i = 0; i < surahNumber - 1; i++) {
      total += ayahCounts[i];
    }
    return total + ayahInSurah;
  }

  /// First page of each juz (index 0 = juz 1).
  static const List<int> juzStartPages = [
    1, 22, 42, 62, 82, 102, 121, 142, 162, 182,
    201, 222, 242, 262, 282, 302, 322, 342, 362, 382,
    402, 422, 442, 462, 482, 502, 522, 542, 562, 582,
  ];

  /// First page of each hizb (index 0 = hizb 1). 60 ahzab total.
  static const List<int> hizbStartPages = [
    1, 11, 22, 32, 42, 52, 62, 72, 82, 92,
    102, 111, 121, 132, 142, 152, 162, 172, 182, 192,
    201, 211, 222, 232, 242, 252, 262, 272, 282, 292,
    302, 312, 322, 332, 342, 352, 362, 372, 382, 392,
    402, 412, 422, 432, 442, 452, 462, 472, 482, 492,
    502, 512, 522, 532, 542, 552, 562, 572, 582, 592,
  ];

  static String surahName(int n) =>
      (n >= 1 && n <= 114) ? surahNames[n - 1] : '';

  /// The surah (1-114) shown as the "primary" surah of a page — the last
  /// surah that starts at or before this page.
  static int surahForPage(int page) {
    for (int i = surahStartPages.length - 1; i >= 0; i--) {
      if (page >= surahStartPages[i]) return i + 1;
    }
    return 1;
  }

  /// All surahs whose content appears on a given page.
  ///
  /// A surah's last page = max(its own start page, next-surah's start
  /// page minus one). Using max() here is essential: if surah N+1 starts
  /// strictly after surah N's start page, surah N is assumed to end
  /// cleanly the page before (no overlap). Only when surah N+1 starts on
  /// the SAME page as surah N (very short surahs sharing a page) does
  /// surah N's range extend to include that shared page. Without the
  /// max(), a surah that ends cleanly on its own page (e.g. Al-Masad
  /// ending exactly on page 603) would incorrectly also appear on the
  /// NEXT page's header just because the next surah starts there.
  static List<int> surahsOnPage(int page) {
    final result = <int>[];
    for (int i = 0; i < surahStartPages.length; i++) {
      final start = surahStartPages[i];
      final nextStart = (i + 1 < surahStartPages.length)
          ? surahStartPages[i + 1]
          : 605; // sentinel: one page past the last real page (604)
      final end = (nextStart - 1) < start ? start : (nextStart - 1);
      if (start <= page && page <= end) {
        result.add(i + 1);
      }
      if (start > page) break;
    }
    return result.isEmpty ? [surahForPage(page)] : result;
  }

  static int juzForPage(int page) {
    for (int i = juzStartPages.length - 1; i >= 0; i--) {
      if (page >= juzStartPages[i]) return i + 1;
    }
    return 1;
  }

  static int hizbForPage(int page) {
    for (int i = hizbStartPages.length - 1; i >= 0; i--) {
      if (page >= hizbStartPages[i]) return i + 1;
    }
    return 1;
  }

  /// Header label matching printed Mushaf convention: all surahs on the
  /// page listed side by side in plain text, no decoration.
  /// e.g. "سورة الإخلاص  سورة الفلق  سورة الناس"
  static String headerLabelForPage(int page) {
    final surahs = surahsOnPage(page);
    return surahs.map((s) => 'سورة ${surahName(s)}').join('  ');
  }
}