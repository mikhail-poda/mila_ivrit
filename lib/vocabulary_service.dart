import 'dart:html' as html;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

import 'main.dart';

class VocabularyService {
  static const String sheetsUrl = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTTUPG22pCGbrlYULESZ5FFyYTo9jyFGFEBk1Wx41gZiNvkonYcLPypdPGCZzFxTzywU4hCra4Fmx-b/pubhtml';

  dom.Document? _document;
  List<String>? _vocabularies;

  static final VocabularyService _instance = VocabularyService._internal();

  factory VocabularyService() => _instance;

  VocabularyService._internal();

  Future<bool> checkInternetConnection() async {
    return html.window.navigator.onLine ?? false;
  }

  Future<void> _ensureDocumentLoaded() async {
    if (_document != null) return;

    final response = await http.get(Uri.parse(sheetsUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to load vocabularies: ${response.statusCode}');
    }

    _document = parser.parse(response.body);
  }

  Future<List<String>> getVocabularies() async {
    if (_vocabularies != null) {
      return _vocabularies!;
    }

    await _ensureDocumentLoaded();

    final sheetMenu = _document!.getElementById('sheet-menu');
    if (sheetMenu == null) {
      throw Exception('Sheet menu not found in document');
    }

    _vocabularies = sheetMenu
        .getElementsByTagName('a')
        .map((e) => e.text)
        .where((e) => !e.startsWith('.'))
        .toList();

    if (_vocabularies!.isEmpty) {
      throw Exception('No vocabularies found');
    }

    return _vocabularies!;
  }

  Future<List<Word>> getVocabularyWords(int vocabIndex) async {
    await _ensureDocumentLoaded();

    if (vocabIndex < 0) {
      throw Exception('Vocabulary index can not be negative');
    }

    final viewport = _document!.getElementById('sheets-viewport');
    if (viewport == null) {
      throw Exception('Viewport not found in document');
    }

    final tbodies = viewport.getElementsByTagName('tbody');
    if (vocabIndex >= tbodies.length) {
      throw Exception('Invalid vocabulary index');
    }

    return tbodies[vocabIndex]
        .getElementsByTagName('tr')
        .skip(1)
        .map((row) {
          final cells = row.getElementsByTagName('td');
          if (cells.length < 6) return null;

          final hebrew = cells[4].text.trim();
          final english = cells[5].text.trim();
          final phonetic = cells[2].text.trim();

          if (hebrew.isEmpty || english.isEmpty) return null;

          return Word(
            hebrew: hebrew,
            english: english,
            phonetic: phonetic,
          );
        })
        .where((word) => word != null)
        .cast<Word>()
        .toList();
  }
}
