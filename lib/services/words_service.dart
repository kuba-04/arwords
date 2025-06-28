import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer';
import '../models/word.dart';

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
      dialects:
          [], // Temporarily return empty list until we fix the dialect query
    );
  }
}

class DialectDTO {
  final String id;
  final String countryCode;
  final String name;

  DialectDTO({required this.id, required this.countryCode, required this.name});

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
    List<WordDTO> wordsList = list
        .map((i) => WordDTO.fromJson(i as Map<String, dynamic>))
        .toList();
    return WordsResponse(
      data: wordsList,
      pagination: PaginationDTO.fromJson(
        json['pagination'] as Map<String, dynamic>,
      ),
    );
  }
}

class PaginationDTO {
  final int page;
  final int limit;
  final int total;

  PaginationDTO({required this.page, required this.limit, required this.total});

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

  WordDefinition({required this.definition, this.example, this.usageNotes});
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
  final SupabaseClient _supabase;

  WordsService(this._supabase);

  Future<WordsResponse> getWords({
    required int page,
    required int pageSize,
    String? searchTerm,
    List<String>? dialectIds,
    String? partOfSpeech,
  }) async {
    try {
      // Calculate offset
      final offset = (page - 1) * pageSize;

      // Start with the base query
      final query = _supabase.from('words').select('''
          *,
          word_forms (
            id,
            arabic_script_variant,
            transliteration,
            conjugation_details,
            audio_url,
            word_form_dialects (
              dialect_id
            )
          )
        ''');

      // Apply filters if provided
      var filteredQuery = query;
      if (searchTerm != null && searchTerm.isNotEmpty) {
        filteredQuery = filteredQuery.ilike('english_term', '%$searchTerm%');
      }

      if (partOfSpeech != null && partOfSpeech.isNotEmpty) {
        filteredQuery = filteredQuery.eq('part_of_speech', partOfSpeech);
      }

      // Apply pagination
      final paginatedQuery = filteredQuery.range(offset, offset + pageSize - 1);

      // Execute the query
      final List<dynamic> words = await paginatedQuery;

      // Get total count
      final count = await _supabase.from('words').select().count();

      return WordsResponse(
        data: words.map((w) => WordDTO.fromJson(w)).toList(),
        pagination: PaginationDTO(
          page: page,
          limit: pageSize,
          total: count.count ?? 0,
        ),
      );
    } catch (error) {
      log('Error fetching words', error: error, stackTrace: StackTrace.current);
      throw Exception('Failed to fetch words: $error');
    }
  }

  Future<Word> getWordDetails(String wordId) async {
    final response = await _supabase
        .from('words')
        .select('''
        *,
        word_forms (
          id,
          arabic_script_variant,
          transliteration,
          conjugation_details,
          audio_url
        )
      ''')
        .eq('id', wordId)
        .single();

    return Word.fromJson(response);
  }

  // Fetch user's favorite words
  Future<List<Word>> getFavoriteWords() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final response = await _supabase
        .from('user_favorite_words')
        .select('''
        words!inner (
          id,
          english_term,
          primary_arabic_script,
          part_of_speech,
          english_definition,
          word_forms (
            id,
            arabic_script_variant,
            transliteration,
            conjugation_details,
            audio_url
          )
        )
      ''')
        .eq('user_id', user.id);

    return (response as List)
        .map((item) => Word.fromJson(item['words']))
        .toList();
  }

  // Add word to favorites
  Future<void> addToFavorites(String wordId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _supabase.from('user_favorite_words').insert({
      'user_id': user.id,
      'word_id': wordId,
    });
  }

  // Remove word from favorites
  Future<void> removeFromFavorites(String wordId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _supabase.from('user_favorite_words').delete().match({
      'user_id': user.id,
      'word_id': wordId,
    });
  }

  // Check if a word is favorited
  Future<bool> isFavorited(String wordId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final response = await _supabase.from('user_favorite_words').select().match(
      {'user_id': user.id, 'word_id': wordId},
    );

    return (response as List).isNotEmpty;
  }
}
