import 'package:supabase_flutter/supabase_flutter.dart' hide StorageException;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/word.dart';
import '../services/error_handler.dart';

class ContentDownloadService {
  static final ContentDownloadService _instance =
      ContentDownloadService._internal();
  final SupabaseClient _supabase = Supabase.instance.client;

  factory ContentDownloadService() {
    return _instance;
  }

  ContentDownloadService._internal();

  Future<void> downloadDictionary({Function(double)? onProgress}) async {
    Database? db;
    try {
      // Check authentication
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Check if user has offline dictionary access
      final userProfile = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user.id)
          .single();

      if (userProfile == null ||
          userProfile['has_offline_dictionary_access'] != true) {
        throw Exception('User does not have offline dictionary access');
      }

      // Initialize database
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, 'arwords.db');

      // Ensure the directory exists
      final targetDir = Directory(dirname(path));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _createTables(db);
        },
      );

      try {
        // Fetch all words from Supabase
        final words = await _supabase.from('words').select('''
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
        ''');

        if (words == null || words.isEmpty) {
          throw NetworkException('No words available in the dictionary');
        }

        // Fetch user's favorite words
        final favoriteWords = await _supabase
            .from('user_favorite_words')
            .select('word_id')
            .eq('user_id', user.id);

        // Create a set of favorite word IDs for faster lookup
        final favoriteWordIds = Set<String>.from(
          favoriteWords?.map((fw) => fw['word_id'] as String) ?? [],
        );

        final totalWords = words.length;

        // Process words in batches
        const batchSize = 100;
        for (var i = 0; i < words.length; i += batchSize) {
          final end = (i + batchSize < words.length)
              ? i + batchSize
              : words.length;
          final batch = words.sublist(i, end);

          await db.transaction((txn) async {
            for (final wordData in batch) {
              try {
                final word = Word.fromJson(wordData);
                final isFavorite = favoriteWordIds.contains(word.id);

                await txn.rawInsert(
                  '''
                  INSERT OR REPLACE INTO words 
                  (id, english_term, primary_arabic_script, part_of_speech, english_definition, is_favorite) 
                  VALUES (?, ?, ?, ?, ?, ?)
                ''',
                  [
                    word.id,
                    word.englishTerm,
                    word.primaryArabicScript,
                    word.partOfSpeech,
                    word.englishDefinition,
                    isFavorite ? 1 : 0,
                  ],
                );

                // Delete existing word forms before inserting new ones
                await txn.delete(
                  'word_forms',
                  where: 'word_id = ?',
                  whereArgs: [word.id],
                );

                for (final form in word.wordForms) {
                  await txn.rawInsert(
                    '''
                    INSERT OR REPLACE INTO word_forms 
                    (id, word_id, arabic_script_variant, transliteration, conjugation_details, audio_url) 
                    VALUES (?, ?, ?, ?, ?, ?)
                  ''',
                    [
                      form.id,
                      word.id,
                      form.arabicScriptVariant,
                      form.transliteration,
                      form.conjugationDetails,
                      form.audioUrl,
                    ],
                  );
                }
              } catch (e) {
                throw StorageException(
                  'Failed to store word in local database: $e',
                );
              }
            }
          });

          if (onProgress != null) {
            onProgress(end / totalWords);
          }
        }

        // Verify the download by counting records
        final wordCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM words'),
        );

        if (wordCount != totalWords) {
          throw StorageException(
            'Data verification failed: Expected $totalWords words, but found $wordCount',
          );
        }
      } catch (e) {
        if (e is PostgrestException) {
          throw NetworkException('Database error: ${e.message}');
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    } finally {
      if (db != null) {
        await db.close();
      }
    }
  }

  Future<void> _createTables(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS words (
          id TEXT PRIMARY KEY,
          english_term TEXT NOT NULL,
          primary_arabic_script TEXT NOT NULL,
          part_of_speech TEXT NOT NULL,
          english_definition TEXT,
          is_favorite INTEGER DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS word_forms (
          id TEXT PRIMARY KEY,
          word_id TEXT NOT NULL,
          arabic_script_variant TEXT,
          transliteration TEXT NOT NULL,
          conjugation_details TEXT NOT NULL,
          audio_url TEXT,
          FOREIGN KEY (word_id) REFERENCES words (id)
        )
      ''');

      // Create indexes for better query performance
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_words_english_term ON words(english_term)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_words_primary_arabic_script ON words (primary_arabic_script)',
      );
    } catch (e) {
      throw StorageException('Failed to create local database: $e');
    }
  }
}
