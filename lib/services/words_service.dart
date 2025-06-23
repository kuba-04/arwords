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

      // Add debug log to see the response structure
      log('Response from database: ${response.toString()}');

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
} 