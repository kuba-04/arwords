import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/word.dart';
import 'access_manager.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
}

class OfflineStorageService {
  static OfflineStorageService? _instance;
  static Database? _database;
  final AccessManager _accessManager;

  OfflineStorageService._() : _accessManager = AccessManager();

  factory OfflineStorageService() {
    _instance ??= OfflineStorageService._();
    return _instance!;
  }

  Future<Database> get database async {
    try {
      if (_database != null) {
        if (_database!.isOpen) {
          return _database!;
        } else {
          _database = null;
        }
      }

      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      if (kDebugMode) print('Error getting database: $e');
      _database = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, 'arwords.db');

      // Open the existing database in read-write mode
      return await openDatabase(path);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error initializing database: $e');
        print('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  Future<bool> isDatabaseValid() async {
    try {
      final db = await database;

      // Check if required tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name='words' OR name='word_forms')",
      );

      if (tables.length != 2) {
        return false;
      }

      // Check if we have actual data
      final wordCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM words WHERE english_term IS NOT NULL',
        ),
      );

      return wordCount != null && wordCount > 0;
    } catch (e) {
      if (kDebugMode) print('Database validation error: $e');
      return false;
    }
  }

  Future<void> initializeDatabase() async {
    try {
      final db = await database;

      // Verify tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND (name='words' OR name='word_forms')",
      );

      if (tables.length != 2) {
        throw Exception(
          'Database schema not initialized. Please download dictionary first.',
        );
      }
    } catch (e) {
      if (kDebugMode) print('Error verifying database: $e');
      rethrow;
    }
  }

  Future<void> clearDatabase() async {
    try {
      final db = await database;
      await db.delete('word_forms');
      await db.delete('words');
    } catch (e) {
      if (kDebugMode) print('Error clearing database: $e');
      rethrow;
    }
  }

  Future<Word?> getWord(String wordId) async {
    if (!await _accessManager.verifyPremiumAccess()) {
      throw UnauthorizedException('Premium access required');
    }

    final db = await database;
    final List<Map<String, dynamic>> words = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [wordId],
    );

    if (words.isEmpty) return null;

    // Create a modifiable copy of the word map
    final Map<String, dynamic> modifiableWordData = Map<String, dynamic>.from(
      words.first,
    );

    final wordForms = await db.query(
      'word_forms',
      where: 'word_id = ?',
      whereArgs: [modifiableWordData['id']],
    );

    // Convert word forms to modifiable maps as well
    final List<Map<String, dynamic>> modifiableWordForms = wordForms
        .map((form) => Map<String, dynamic>.from(form))
        .toList();

    modifiableWordData['word_forms'] = modifiableWordForms;
    return Word.fromJson(modifiableWordData);
  }

  Future<List<Word>> searchWords(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> words = await db.rawQuery(
      'SELECT * FROM words WHERE english_term LIKE ? OR primary_arabic_script LIKE ? ORDER BY english_term',
      ['%$query%', '%$query%'],
    );

    final List<Word> results = [];
    for (var word in words) {
      // Create a modifiable copy of the word map
      final Map<String, dynamic> modifiableWordData = Map<String, dynamic>.from(
        word,
      );

      final wordForms = await db.rawQuery(
        'SELECT * FROM word_forms WHERE word_id = ?',
        [modifiableWordData['id']],
      );

      // Convert word forms to modifiable maps as well
      final List<Map<String, dynamic>> modifiableWordForms = wordForms
          .map((form) => Map<String, dynamic>.from(form))
          .toList();

      modifiableWordData['word_forms'] = modifiableWordForms;
      results.add(Word.fromJson(modifiableWordData));
    }

    return results;
  }

  Future<void> toggleFavorite(String wordId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'words',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [wordId],
    );
  }

  Future<List<Word>> getFavoriteWords() async {
    final db = await database;
    final List<Map<String, dynamic>> words = await db.rawQuery(
      'SELECT * FROM words WHERE is_favorite = 1 ORDER BY english_term',
    );

    final List<Word> results = [];
    for (var word in words) {
      // Create a modifiable copy of the word map
      final Map<String, dynamic> modifiableWordData = Map<String, dynamic>.from(
        word,
      );

      final wordForms = await db.rawQuery(
        'SELECT * FROM word_forms WHERE word_id = ?',
        [modifiableWordData['id']],
      );

      // Convert word forms to modifiable maps as well
      final List<Map<String, dynamic>> modifiableWordForms = wordForms
          .map((form) => Map<String, dynamic>.from(form))
          .toList();

      modifiableWordData['word_forms'] = modifiableWordForms;
      results.add(Word.fromJson(modifiableWordData));
    }

    return results;
  }
}
