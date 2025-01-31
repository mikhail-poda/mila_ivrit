import 'package:flutter/material.dart';

import 'base_learning.dart';
import 'vocabulary_state.dart';

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

class Word extends LearnableItem {
  final String hebrew;
  final String english;
  String phonetic;

  Word({
    super.rank = 0,
    required this.hebrew,
    required this.english,
    required this.phonetic,
  });

  @override
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

  @override
  bool isNotEmpty() => english.isNotEmpty && hebrew.isNotEmpty;
}

class SavedState implements BaseSavedState {
  final List<Word> words;
  final List<Word> excluded;
  final int vocabularyIndex;
  final String currentVocabulary;

  SavedState(
      {required this.words,
      required this.excluded,
      required this.vocabularyIndex,
      required this.currentVocabulary});

  @override
  Map<String, dynamic> toJson() => {
        'words': words.map((w) => w.toJson()).toList(),
        'excluded': excluded.map((w) => w.toJson()).toList(),
        'vocabularyIndex': vocabularyIndex,
        'currentVocabulary': currentVocabulary
      };

  factory SavedState.fromJson(Map<String, dynamic> json) => SavedState(
        words: (json['words'] as List)
            .map((w) => Word.fromJson(w))
            .where((word) => word.isNotEmpty())
            .toList(),
        excluded: (json['excluded'] as List)
            .map((w) => Word.fromJson(w))
            .where((word) => word.isNotEmpty())
            .toList(),
    vocabularyIndex: json['vocabularyIndex'] as int,
    currentVocabulary: json['currentVocabulary'],
      );
}

class VocabularyLearningScreen extends BaseLearningScreen<Word> {
  const VocabularyLearningScreen({super.key});

  @override
  State<VocabularyLearningScreen> createState() =>
      VocabularyLearningScreenState();
}
