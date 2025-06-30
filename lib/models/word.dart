class Word {
  final String id;
  final String englishTerm;
  final String primaryArabicScript;
  final String partOfSpeech;
  final String? englishDefinition;
  final List<WordForm> wordForms;

  Word({
    required this.id,
    required this.englishTerm,
    required this.primaryArabicScript,
    required this.partOfSpeech,
    this.englishDefinition,
    this.wordForms = const [],
  });

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      id: json['id'] as String,
      englishTerm: json['english_term'] as String,
      primaryArabicScript: json['primary_arabic_script'] as String,
      partOfSpeech: json['part_of_speech'] as String,
      englishDefinition: json['english_definition'] as String?,
      wordForms:
          (json['word_forms'] as List<dynamic>?)
              ?.map((e) => WordForm.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class WordForm {
  final String id;
  final String? arabicScriptVariant;
  final String transliteration;
  final String conjugationDetails;
  final String? audioUrl;

  WordForm({
    required this.id,
    this.arabicScriptVariant,
    required this.transliteration,
    required this.conjugationDetails,
    this.audioUrl,
  });

  factory WordForm.fromJson(Map<String, dynamic> json) {
    return WordForm(
      id: json['id'] as String,
      arabicScriptVariant: json['arabic_script_variant'] as String?,
      transliteration: json['transliteration'] as String,
      conjugationDetails: json['conjugation_details'] as String,
      audioUrl: json['audio_url'] as String?,
    );
  }
}
