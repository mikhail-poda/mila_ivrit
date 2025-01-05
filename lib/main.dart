import 'dart:math';

import 'package:darq/darq.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hebrew Vocabulary',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const VocabularyLearningScreen(),
    );
  }
}

class Word {
  int rank;
  final String hebrew;
  final String english;
  final String phonetic;

  Word({
    this.rank = 0,
    required this.hebrew,
    required this.english,
    required this.phonetic,
  });

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'hebrew': hebrew,
        'english': english,
        'phonetic': phonetic,
      };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        rank: json['rank'],
        hebrew: json['hebrew'],
        english: json['english'],
        phonetic: json['phonetic'],
      );
}

class SavedState {
  final List<Word> words;
  final String currentVocabulary;

  SavedState({
    required this.words,
    required this.currentVocabulary,
  });

  Map<String, dynamic> toJson() => {
        'words': words.map((w) => w.toJson()).toList(),
        'currentVocabulary': currentVocabulary,
      };

  factory SavedState.fromJson(Map<String, dynamic> json) => SavedState(
        words: (json['words'] as List)
            .map((w) => Word.fromJson(w))
            .where((word) => word.english.isNotEmpty && word.hebrew.isNotEmpty)
            .toList(),
        currentVocabulary: json['currentVocabulary'],
      );
}

class VocabularyLearningScreen extends StatefulWidget {
  const VocabularyLearningScreen({super.key});

  @override
  State<VocabularyLearningScreen> createState() =>
      _VocabularyLearningScreenState();
}

class _VocabularyLearningScreenState extends State<VocabularyLearningScreen>
    with WidgetsBindingObserver {
  List<Word> words = [];
  Word? currentWord;
  bool showTranslation = false;
  bool showEvaluation = false;
  final difficulties = ['again', 'good', 'easy'];
  final uri =
      'https://docs.google.com/spreadsheets/d/e/2PACX-1vTTUPG22pCGbrlYULESZ5FFyYTo9jyFGFEBk1Wx41gZiNvkonYcLPypdPGCZzFxTzywU4hCra4Fmx-b/pubhtml';
  bool _isSaving = false;
  bool _isLoading = true;
  String currentVocabulary = '';
  List<String> completedVocabularies = [];
  List<String> availableVocabularies = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadState();
  }

  Future<List<String>> getVocabularies() async {
    final response = await http.get(Uri.parse(uri));
    final document = parser.parse(response.body);

    return document
        .getElementById('sheet-menu')!
        .getElementsByTagName('a')
        .map((e) => e.text)
        .where((e) => !e.startsWith('.'))
        .toList();
  }

  Future<List<Word>> loadVocabularyWords(String vocabName) async {
    final response = await http.get(Uri.parse(uri));
    final document = parser.parse(response.body);

    final vocabIndex = availableVocabularies.indexOf(vocabName);
    final tbody = document
        .getElementById('sheets-viewport')!
        .getElementsByTagName('tbody')[vocabIndex];

    return tbody
        .getElementsByTagName('tr')
        .skip(1)
        .map((row) {
          final cells =
              row.getElementsByTagName('td').map((e) => e.text.trim()).toList();
          return Word(
            hebrew: cells[4],
            english: cells[5],
            phonetic: cells[2],
          );
        })
        .where((word) => word.english.isNotEmpty && word.hebrew.isNotEmpty)
        .toList();
  }

  Future<void> saveState() async {
    if (_isSaving) return;
    _isSaving = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final state = SavedState(
        words: words,
        currentVocabulary: currentVocabulary,
      );
      await prefs.setString('savedState', json.encode(state.toJson()));
    } finally {
      _isSaving = false;
    }
  }

  Future<void> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStateJson = prefs.getString('savedState');

      availableVocabularies = await getVocabularies();

      if (savedStateJson == null) {
        currentVocabulary = availableVocabularies.first;
        words = await loadVocabularyWords(currentVocabulary);
        words.shuffle();
      } else {
        final savedState = SavedState.fromJson(json.decode(savedStateJson));
        words = savedState.words;
        currentVocabulary = savedState.currentVocabulary;
      }

      completedVocabularies = [];
      for (var vocab in availableVocabularies) {
        if (vocab == currentVocabulary) {
          break;
        }
        completedVocabularies.add(vocab);
      }

      selectNextWord();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void selectNextWord() {
    if (words.isEmpty) return;

    setState(() {
      _isLoading = false;
      showTranslation = false;
      showEvaluation = false;
      currentWord = words[0];
    });
  }

  void handleShowTranslation() {
    setState(() {
      showTranslation = true;
      showEvaluation = true;
    });
  }

  void handleDifficultySelection(String difficulty) async {
    if (!showEvaluation || currentWord == null) return;

    switch (difficulty) {
      case 'again':
        if (currentWord!.rank < 4) {
          currentWord!.rank = 1;
        } else  {
          currentWord!.rank = 2;
        }
        break;
      case 'good':
        if (currentWord!.rank < 4) {
          currentWord!.rank += 1;
        } else if (currentWord!.rank > 5) {
          currentWord!.rank -= 1;
        }
        break;
      case 'easy':
        if (currentWord!.rank == 0) {
          currentWord!.rank = 8;
        } else if (currentWord!.rank < 4) {
          currentWord!.rank += 2;
        } else {
          currentWord!.rank += 1;
        }
        break;
    }

    words.removeAt(0);
    var index = pow(2, (currentWord!.rank + 1)).toInt();

    if (index >= words.length) {
      final nextVocabIndex =
          availableVocabularies.indexOf(currentVocabulary) + 1;
      if (nextVocabIndex < availableVocabularies.length) {

        setState(() {
          _isLoading = true;
        });

        currentVocabulary = availableVocabularies[nextVocabIndex];
        final newWords = await loadVocabularyWords(currentVocabulary);
        newWords.shuffle();
        words.addAll(newWords);
        await saveState();
      }
    }

    if (index < words.length) {
      words.insert(index, currentWord!);
    } else {
      words.add(currentWord!);
    }

    selectNextWord();
  }

  Color getButtonColor(String difficulty) {
    switch (difficulty) {
      case 'again':
        return Colors.orange;
      case 'good':
        return Colors.lightBlueAccent;
      case 'easy':
        return Colors.green;
      default:
        return Colors.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    var used = words.where((x) => x.rank > 0).toList();
    var learned = used.where((x) => x.rank > 8).toList();
    var points = used.sum((word) => word.rank);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(' $currentVocabulary', style: Theme.of(context).textTheme.bodyLarge),
                  Row(children: [
                    Icon(Icons.list, size: 30, color: Colors.black45),
                    Text(' ${words.length}', style: Theme.of(context).textTheme.bodyLarge),
                  ]),
                  Row(children: [
                    Icon(LucideIcons.check, size: 30, color: Colors.green),
                    Text(' ${used.length}', style: Theme.of(context).textTheme.bodyLarge),
                  ]),
                  Row(children: [
                    Icon(LucideIcons.checkCheck, size: 30, color: Colors.teal),
                    Text(' ${learned.length}', style: Theme.of(context).textTheme.bodyLarge),
                  ]),
                  Row(children: [
                    Icon(Icons.emoji_events, size: 25, color: Colors.amber),
                    Text(' $points', style: Theme.of(context).textTheme.bodyLarge),
                  ]),
                ],
              ),
              Expanded(
                child: Center(
                  child: Card(
                    elevation: 4,
                    child: Container(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (currentWord?.english ?? 'Loading...').replaceAll('; ', '\n'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          if (showTranslation) ...[
                            const SizedBox(height: 16),
                            Text(
                              currentWord?.hebrew ?? '',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            if (currentWord?.phonetic.isNotEmpty ?? false) ...[
                              const SizedBox(height: 8),
                              Text(
                                currentWord?.phonetic ?? '',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      fontSize: Theme.of(context).textTheme.headlineMedium!.fontSize!.toDouble() * 0.8,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: !showTranslation
                    ? ElevatedButton(
                        onPressed: () => handleShowTranslation(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 32,
                          ),
                        ),
                        child: const Text(
                          '            Show            ',
                          style: TextStyle(fontSize: 20),
                        ),
                      )
                    : Row(
                        children: difficulties.map((difficulty) {
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: ElevatedButton(
                                onPressed: () => handleDifficultySelection(difficulty),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: getButtonColor(difficulty),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text(
                                  difficulty,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              Text('Version: 0.4 • Word rank: ${currentWord?.rank ?? 0}'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await saveState();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      saveState();
    }
  }
}
