import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' show SocketException;
import '../models/word.dart';
import 'access_manager.dart';
import 'offline_storage_service.dart';
import 'download_service.dart';
import 'error_handler.dart';
import 'package:flutter/foundation.dart';

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
  final SupabaseClient? _supabase;
  final AccessManager _accessManager;
  final OfflineStorageService _offlineStorage;
  final ContentDownloadService _downloadService;
  void Function(String)? onNotification;
  bool _isDownloading = false;

  WordsService({SupabaseClient? supabase, this.onNotification})
    : _supabase = supabase,
      _accessManager = AccessManager(),
      _offlineStorage = OfflineStorageService(),
      _downloadService = ContentDownloadService();

  bool get isOnline => _supabase != null;

  Future<bool> isDictionaryDownloaded() async {
    try {
      return await _offlineStorage.isDatabaseValid();
    } catch (e) {
      return false;
    }
  }

  Future<void> downloadDictionary({
    Function(double)? onProgress,
    bool force = false,
  }) async {
    if (_isDownloading) {
      return;
    }

    try {
      _isDownloading = true;
      final isPremium = await _accessManager.verifyPremiumAccess();
      if (!isPremium) {
        throw Exception('Premium access required for dictionary download');
      }

      final isDownloaded = !force && await isDictionaryDownloaded();
      if (isDownloaded) {
        return;
      }

      if (_supabase == null) {
        throw Exception('Cannot download dictionary: No internet connection');
      }

      await _downloadService.downloadDictionary(onProgress: onProgress);
      await _offlineStorage.initializeDatabase();

      // Cache premium status for offline use
      await _accessManager.cachePremiumStatus(true);

      if (onNotification != null) {
        onNotification!('Dictionary downloaded successfully');
      }
    } catch (e) {
      if (onNotification != null) {
        onNotification!('Failed to download dictionary: $e');
      }
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  Future<WordsResponse> getWords({
    required int page,
    required int pageSize,
    String? searchTerm,
    List<String>? dialectIds,
    String? partOfSpeech,
  }) async {
    try {
      final isPremium = await _accessManager.verifyPremiumAccess();
      final isDownloaded = await isDictionaryDownloaded();

      // For premium users with downloaded dictionary, use offline search
      if (isPremium && isDownloaded) {
        final List<Word> words = await _offlineStorage.searchWords(
          searchTerm ?? '',
        );

        // Calculate pagination
        final start = (page - 1) * pageSize;
        final end = start + pageSize;
        final paginatedWords = words.sublist(
          start < words.length ? start : words.length,
          end < words.length ? end : words.length,
        );

        return WordsResponse(
          data: paginatedWords
              .map(
                (w) => WordDTO(
                  id: w.id,
                  englishTerm: w.englishTerm,
                  primaryArabicScript: w.primaryArabicScript,
                  partOfSpeech: w.partOfSpeech,
                  dialects: [],
                ),
              )
              .toList(),
          pagination: PaginationDTO(
            page: page,
            limit: pageSize,
            total: words.length,
          ),
        );
      } else if (isPremium && !isDownloaded) {
        onNotification?.call(
          'For faster searches, download the dictionary from your profile.',
        );
      }

      // Check if we can do online search
      if (_supabase == null) {
        throw NetworkException(
          'No internet connection available. Please check your connection or download the dictionary for offline use.',
        );
      }

      // For non-premium users or if dictionary not downloaded, use online search
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
      if (error is SocketException ||
          error.toString().contains('ClientException')) {
        throw NetworkException(
          'No internet connection available. Please check your connection or download the dictionary for offline use.',
        );
      }
      throw Exception('Failed to fetch words: $error');
    }
  }

  Future<Word> getWordDetails(String wordId) async {
    try {
      final isPremium = await _accessManager.verifyPremiumAccess();
      final isDownloaded = await isDictionaryDownloaded();

      // For premium users with downloaded dictionary, use offline search
      if (isPremium && isDownloaded) {
        final word = await _offlineStorage.getWord(wordId);
        if (word != null) {
          return word;
        }
        // If word not found in offline storage, throw error since we're offline
        throw Exception('Word not found in offline dictionary');
      } else if (isPremium && !isDownloaded) {
        onNotification?.call(
          'For offline access, download the dictionary from your profile.',
        );
      }

      // Check if we can do online search
      if (_supabase == null) {
        throw NetworkException(
          'Cannot fetch word details: No internet connection and no offline dictionary available',
        );
      }

      // Try online access
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
    } catch (error) {
      if (error is SocketException ||
          error.toString().contains('ClientException')) {
        throw NetworkException(
          'No internet connection available. Please check your connection or download the dictionary for offline use.',
        );
      }
      throw Exception('Failed to fetch word details: $error');
    }
  }

  // Fetch user's favorite words
  Future<List<Word>> getFavoriteWords() async {
    try {
      final isPremium = await _accessManager.verifyPremiumAccess();
      final isDownloaded = await isDictionaryDownloaded();

      // For premium users with downloaded dictionary, use offline storage
      if (isPremium && isDownloaded) {
        return await _offlineStorage.getFavoriteWords();
      }

      // Check if we can do online search
      if (_supabase == null) {
        throw Exception(
          'Cannot fetch favorites: No internet connection and no offline dictionary available',
        );
      }

      final user = _supabase?.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final response = await _supabase
          ?.from('user_favorite_words')
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
    } catch (error) {
      throw Exception('Failed to fetch favorite words: $error');
    }
  }

  // Add word to favorites
  Future<void> addToFavorites(String wordId) async {
    try {
      final isPremium = await _accessManager.verifyPremiumAccess();
      final isDownloaded = await isDictionaryDownloaded();

      // For premium users with downloaded dictionary, update offline storage
      if (isPremium && isDownloaded) {
        await _offlineStorage.toggleFavorite(wordId, true);
      }

      // If online, also update remote database
      if (_supabase != null) {
        final user = _supabase?.auth.currentUser;
        if (user == null) throw Exception('User not authenticated');

        // Check if already favorited
        final existing = await _supabase
            ?.from('user_favorite_words')
            .select()
            .match({'user_id': user.id, 'word_id': wordId});

        if (existing == null || (existing as List).isEmpty) {
          // Only insert if not already favorited
          await _supabase?.from('user_favorite_words').insert({
            'user_id': user.id,
            'word_id': wordId,
          });
        }
      }
    } catch (error) {
      if (kDebugMode) print('Error adding to favorites: $error');
      throw Exception('Failed to add to favorites: $error');
    }
  }

  // Remove word from favorites
  Future<void> removeFromFavorites(String wordId) async {
    try {
      final isPremium = await _accessManager.verifyPremiumAccess();
      final isDownloaded = await isDictionaryDownloaded();

      // For premium users with downloaded dictionary, update offline storage
      if (isPremium && isDownloaded) {
        await _offlineStorage.toggleFavorite(wordId, false);
      }

      // If online, also update remote database
      if (_supabase != null) {
        final user = _supabase?.auth.currentUser;
        if (user == null) throw Exception('User not authenticated');

        await _supabase?.from('user_favorite_words').delete().match({
          'user_id': user.id,
          'word_id': wordId,
        });
      }
    } catch (error) {
      throw Exception('Failed to remove from favorites: $error');
    }
  }

  // Check if a word is favorited
  Future<bool> isFavorited(String wordId) async {
    try {
      if (kDebugMode) print('isFavorited: Starting check for wordId: $wordId');

      final isPremium = await _accessManager.verifyPremiumAccess();
      final isDownloaded = await isDictionaryDownloaded();

      if (kDebugMode)
        print(
          'isFavorited: isPremium: $isPremium, isDownloaded: $isDownloaded',
        );

      // For premium users with downloaded dictionary, check offline storage
      if (isPremium && isDownloaded) {
        if (kDebugMode) print('isFavorited: Checking offline storage');
        final word = await _offlineStorage.getWord(wordId);
        if (kDebugMode)
          print(
            'isFavorited: Word from offline storage: ${word?.id}, isFavorite: ${word?.isFavorite}',
          );
        return word?.isFavorite ?? false;
      }

      // If online, check remote database
      if (_supabase != null) {
        if (kDebugMode) print('isFavorited: Checking online database');
        final user = _supabase?.auth.currentUser;
        if (user == null) throw Exception('User not authenticated');

        final response = await _supabase
            ?.from('user_favorite_words')
            .select()
            .match({'user_id': user.id, 'word_id': wordId});

        if (kDebugMode) print('isFavorited: Online response: $response');
        return (response as List).isNotEmpty;
      }

      throw Exception(
        'Cannot check favorites: No internet connection and no offline dictionary available',
      );
    } catch (error) {
      if (kDebugMode) print('isFavorited ERROR: $error');
      throw Exception('Failed to check if word is favorited: $error');
    }
  }
}
