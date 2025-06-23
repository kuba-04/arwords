import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer';


class WordDTO {
  final String id;
  final String englishTerm;
  final String primaryArabicScript;
  final String? partOfSpeech;
  final List<DialectDTO> dialects;

  WordDTO({
    required this.id,
    required this.englishTerm,
    required this.primaryArabicScript,
    this.partOfSpeech,
    required this.dialects,
  });

  factory WordDTO.fromJson(Map<String, dynamic> json) {
    return WordDTO(
      id: json['id'],
      englishTerm: json['english_term'],
      primaryArabicScript: json['primary_arabic_script'],
      partOfSpeech: json['part_of_speech'],
      dialects: [],  // Temporarily return empty list until we fix the dialect query
    );
  }
}

class DialectDTO {
  final String id;
  final String countryCode;
  final String name;

  DialectDTO({
    required this.id,
    required this.countryCode,
    required this.name,
  });

  factory DialectDTO.fromJson(Map<String, dynamic> json) {
    return DialectDTO(
      id: json['id'],
      countryCode: json['country_code'],
      name: json['name'],
    );
  }
}

class WordsResponse {
  final List<WordDTO> data;
  final PaginationDTO pagination;

  WordsResponse({required this.data, required this.pagination});

  factory WordsResponse.fromJson(Map<String, dynamic> json) {
    var list = json['data'] as List;
    List<WordDTO> wordsList = list.map((i) => WordDTO.fromJson(i as Map<String, dynamic>)).toList();
    return WordsResponse(
      data: wordsList,
      pagination: PaginationDTO.fromJson(json['pagination'] as Map<String, dynamic>),
    );
  }
}

class PaginationDTO {
  final int page;
  final int limit;
  final int total;

  PaginationDTO({
    required this.page,
    required this.limit,
    required this.total,
  });

  factory PaginationDTO.fromJson(Map<String, dynamic> json) {
    return PaginationDTO(
      page: json['page'] as int,
      limit: json['limit'] as int,
      total: json['total'] as int,
    );
  }
}

class WordDefinition {
  final String definition;
  final String? example;
  final String? usageNotes;

  WordDefinition({
    required this.definition,
    this.example,
    this.usageNotes,
  });
}

class WordForm {
  final String arabicScript;
  final String transliteration;
  final String conjugationDetails;
  final String? audioUrl;
  final String dialect;

  WordForm({
    required this.arabicScript,
    required this.transliteration,
    required this.conjugationDetails,
    this.audioUrl,
    required this.dialect,
  });
}

class DetailedWordDTO {
  final String id;
  final String englishTerm;
  final String primaryArabicScript;
  final String partOfSpeech;
  final String? englishDefinition;
  final String frequencyTag;
  final List<String> usageRegions;
  final List<WordForm> forms;
  final List<String> educationalNotes;

  DetailedWordDTO({
    required this.id,
    required this.englishTerm,
    required this.primaryArabicScript,
    required this.partOfSpeech,
    this.englishDefinition,
    required this.frequencyTag,
    required this.usageRegions,
    required this.forms,
    required this.educationalNotes,
  });
}

class WordsService {
  static final supabase = Supabase.instance.client;

  static Future<WordsResponse> getWords({
    String? english,
    String? arabic,
    String? partOfSpeech,
    String? frequency,
    int page = 1,
    int limit = 10,
    String sortBy = 'english_term',
  }) async {
    try {
      // Calculate pagination
      final from = (page - 1) * limit;
      final to = from + limit - 1;
      
      // Start with the base query
      var query = supabase
          .from('words')
          .select('''
            *,
            word_forms!inner (
              *,
              word_form_dialects!inner (
                dialects!inner (
                  id,
                  name,
                  country_code
                )
              )
            )
          ''');

      // Apply filters
      if (english != null && english.isNotEmpty) {
        query = query.ilike('english_term', '%$english%');
      }
      if (arabic != null && arabic.isNotEmpty) {
        query = query.ilike('primary_arabic_script', '%$arabic%');
      }
      if (partOfSpeech != null && partOfSpeech.isNotEmpty) {
        query = query.eq('part_of_speech', partOfSpeech);
      }
      
      // Execute the query with ordering and pagination
      final response = await query
          .order(sortBy)
          .range(from, to);

      if (response == null || response.isEmpty) {
        return WordsResponse(
          data: [],
          pagination: PaginationDTO(page: page, limit: limit, total: 0),
        );
      }

      // Transform the data to include unique dialects from word forms
      final words = response.map((word) {
        // Extract all dialects from word forms
        final allDialects = (word['word_forms'] as List<dynamic>).expand((form) {
          return ((form['word_form_dialects'] ?? []) as List<dynamic>).map((wfd) {
            final dialect = wfd['dialects'];
            return DialectDTO(
              id: dialect['id'],
              countryCode: dialect['country_code'],
              name: dialect['name'],
            );
          });
        }).toList();

        // Remove duplicates based on country_code
        final uniqueDialects = <String, DialectDTO>{};
        for (var dialect in allDialects) {
          uniqueDialects[dialect.countryCode] = dialect;
        }

        return WordDTO(
          id: word['id'],
          englishTerm: word['english_term'],
          primaryArabicScript: word['primary_arabic_script'],
          partOfSpeech: word['part_of_speech'],
          dialects: uniqueDialects.values.toList(),
        );
      }).toList();

      // Get total count for pagination
      final countQuery = supabase
          .from('words')
          .select('''
            *,
            word_forms!inner (
              *,
              word_form_dialects!inner (
                dialects!inner (
                  id,
                  name,
                  country_code
                )
              )
            )
          ''');
      
      if (english != null && english.isNotEmpty) {
        countQuery.ilike('english_term', '%$english%');
      }
      if (arabic != null && arabic.isNotEmpty) {
        countQuery.ilike('primary_arabic_script', '%$arabic%');
      }
      if (partOfSpeech != null && partOfSpeech.isNotEmpty) {
        countQuery.eq('part_of_speech', partOfSpeech);
      }

      final countResponse = await countQuery;
      final total = countResponse.length ?? 0;

      return WordsResponse(
        data: words,
        pagination: PaginationDTO(
          page: page,
          limit: limit,
          total: total,
        ),
      );

    } catch (error) {
      log('Error fetching words', error: error, stackTrace: StackTrace.current);
      throw Exception('Failed to fetch words: $error');
    }
  }

  static Future<DetailedWordDTO> getWordDetails(String wordId) async {
    try {
      log('Fetching word details for ID: $wordId');
      
      final response = await supabase
          .from('words')
          .select('''
            *,
            word_forms (
              id,
              arabic_script_variant,
              transliteration,
              conjugation_details,
              audio_url,
              word_form_dialects (
                dialects (
                  id,
                  name,
                  country_code
                )
              )
            )
          ''')
          .eq('id', wordId)
          .single();

      log('Response received: ${response.toString()}');

      if (response == null) {
        throw Exception('Word not found');
      }

      final wordForms = (response['word_forms'] as List<dynamic>? ?? [])
          .map((form) {
            final dialectsList = form['word_form_dialects'] as List<dynamic>? ?? [];
            String dialectName = 'Unknown';
            if (dialectsList.isNotEmpty) {
              final dialect = dialectsList.first['dialects'] as Map<String, dynamic>;
              dialectName = dialect['name'] as String;
            }
            return WordForm(
              arabicScript: form['arabic_script_variant'] ?? '',
              transliteration: form['transliteration'] ?? '',
              conjugationDetails: form['conjugation_details'] ?? '',
              audioUrl: form['audio_url'],
              dialect: dialectName,
            );
          })
          .toList();

      final usageRegions = (response['word_forms'] as List<dynamic>? ?? [])
          .expand((form) {
            final dialectsList = form['word_form_dialects'] as List<dynamic>? ?? [];
            return dialectsList.map((wfd) => (wfd['dialects'] as Map<String, dynamic>)['country_code'] as String);
          })
          .toSet()
          .toList();

      final result = DetailedWordDTO(
        id: response['id'],
        englishTerm: response['english_term'],
        primaryArabicScript: response['primary_arabic_script'],
        partOfSpeech: response['part_of_speech'] ?? '',
        englishDefinition: response['english_definition'],
        frequencyTag: response['general_frequency_tag'] ?? 'NOT_DEFINED',
        usageRegions: usageRegions,
        forms: wordForms,
        educationalNotes: [], // This field might need to be added to the database if needed
      );

      log('Transformed response into DTO: ${result.toString()}');
      return result;

    } catch (error) {
      log('Error fetching word details', error: error, stackTrace: StackTrace.current);
      throw Exception('Failed to fetch word details: $error');
    }
  }
} 