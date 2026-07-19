class Surah {
  final int number;
  final String name;
  final String englishName;
  final String englishNameTranslation;
  final int numberOfAyahs;
  final String revelationType;

  Surah({
    required this.number,
    required this.name,
    required this.englishName,
    required this.englishNameTranslation,
    required this.numberOfAyahs,
    required this.revelationType,
  });

  factory Surah.fromJson(Map<String, dynamic> json) {
    return Surah(
      number: json['number'],
      name: json['name'],
      englishName: json['englishName'],
      englishNameTranslation: json['englishNameTranslation'],
      numberOfAyahs: json['numberOfAyahs'],
      revelationType: json['revelationType'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'name': name,
      'englishName': englishName,
      'englishNameTranslation': englishNameTranslation,
      'numberOfAyahs': numberOfAyahs,
      'revelationType': revelationType,
    };
  }
}

class Ayah {
  final int number;
  final String text;
  final int numberInSurah;
  final int juz;
  final int page;
  final int hizb;
  final int rub;

  /// Optional translation text in the user's chosen edition — null when
  /// translation display is off.
  final String? translation;

  Ayah({
    required this.number,
    required this.text,
    required this.numberInSurah,
    required this.juz,
    required this.page,
    required this.hizb,
    required this.rub,
    this.translation,
  });

  factory Ayah.fromJson(Map<String, dynamic> json) {
    // api.alquran.cloud exposes hizb data only as 'hizbQuarter' (1-240,
    // the rub' index). Derive the hizb number (1-60) from it. Older
    // locally-cached data may still carry plain 'hizb'/'rub' keys, so
    // those are accepted first.
    final int hizbQuarter = json['hizbQuarter'] ?? json['rub'] ?? 1;
    return Ayah(
      number: json['number'],
      text: json['text'],
      numberInSurah: json['numberInSurah'],
      juz: json['juz'],
      page: json['page'],
      hizb: json['hizb'] ?? ((hizbQuarter - 1) ~/ 4) + 1,
      rub: json['rub'] ?? hizbQuarter,
      translation: json['translation'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'text': text,
      'numberInSurah': numberInSurah,
      'juz': juz,
      'page': page,
      'hizb': hizb,
      'rub': rub,
    };
  }
}
