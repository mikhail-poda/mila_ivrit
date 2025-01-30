import 'dart:math';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'web_tts.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:convert';
import 'dart:async';
import 'base_learning.dart';

const boldFont = TextStyle(fontWeight: FontWeight.bold);
const lightFont = TextStyle(fontWeight: FontWeight.w300);
const italicFont = TextStyle(fontWeight: FontWeight.w300, fontStyle: FontStyle.italic);

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
  final String phonetic;

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
  final String currentVocabulary;

  SavedState({
    required this.words,
    required this.excluded,
    required this.currentVocabulary,
  });

  @override
  Map<String, dynamic> toJson() => {
        'words': words.map((w) => w.toJson()).toList(),
        'excluded': excluded.map((w) => w.toJson()).toList(),
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
        currentVocabulary: json['currentVocabulary'],
      );
}

class VocabularyLearningScreen extends BaseLearningScreen<Word> {
  const VocabularyLearningScreen({super.key});

  @override
  State<VocabularyLearningScreen> createState() => _VocabularyLearningScreenState();
}

class _VocabularyLearningScreenState extends BaseLearningScreenState<Word, VocabularyLearningScreen> with WidgetsBindingObserver {
  final difficulties = ['again', 'good', 'easy'];
  final uri = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTTUPG22pCGbrlYULESZ5FFyYTo9jyFGFEBk1Wx41gZiNvkonYcLPypdPGCZzFxTzywU4hCra4Fmx-b/pubhtml';

  int lastIndex = -1;
  List<Word> excluded = [];
  String currentVocabulary = '';
  List<String> availableVocabularies = [];

  @override
  String get version => '1.0.0';

  @override
  String get prefsKey => 'hebrew_vocabulary';

  void _playHebrewWord(String hebrewWord) {
    try {
      WebTTS.speak(hebrewWord);
    } catch (e) {}
  }

  Future<Map<String, Word>> _fetchAndCombineSourceMap() async {
    final a2Words = await _loadVocabularyWords('A2');
    final b1Words = await _loadVocabularyWords('B1');
    final combinedWords = [...a2Words, ...b1Words];

    final sourceMap = <String, Word>{};
    for (final word in combinedWords) {
      final key = '${word.english}-${word.hebrew}';
      sourceMap[key] = word;
    }

    return sourceMap;
  }

  Future<void> _syncWithSourceMap() async {
    final sourceMap = await _fetchAndCombineSourceMap();

    items.removeWhere((word) => removeWhere(word, sourceMap));
    excluded.removeWhere((word) => removeWhere(word, sourceMap));

    items.addAll(sourceMap.values);
    await saveState();
  }

  bool removeWhere(Word word, Map<String, Word> sourceMap) {
    final key = '${word.english}-${word.hebrew}';
    if (sourceMap.containsKey(key)) {
      sourceMap.remove(key);
      return false;
    } else {
      return true;
    }
  }

  Future<bool> _checkInternetConnection() async {
    return html.window.navigator.onLine ?? false;
  }

  @override
  Future<void> syncWithSource() async {
    await _syncWithSourceMap();
    lastIndex = -1;
    selectNextItem();
  }

  Future<List<String>> _getVocabularies() async {
    try {
      if (!await _checkInternetConnection()) {
        setState(() {
          appState = AppState.noInternet;
        });
        return [];
      }

      final response = await http.get(Uri.parse(uri));
      final document = parser.parse(response.body);

      return document
          .getElementById('sheet-menu')!
          .getElementsByTagName('a')
          .map((e) => e.text)
          .where((e) => !e.startsWith('.'))
          .toList();
    } catch (e, stackTrace) {
      setState(() {
        appState = AppState.error;
        error = AppError(e.toString(), stackTrace.toString());
      });
      return [];
    }
  }

  @override
  void loadSavedState(String savedStateJson) {
    final savedState = SavedState.fromJson(json.decode(savedStateJson));
    items = savedState.words;
    excluded = savedState.excluded;
    currentVocabulary = savedState.currentVocabulary;
  }

  @override
  Future<void> loadInitState() async {
    availableVocabularies = await _getVocabularies();
    if (appState != AppState.error && appState != AppState.noInternet) {
      currentVocabulary = availableVocabularies.first; // availableVocabularies[2]; //
      items = await _loadVocabularyWords(currentVocabulary);
      items.shuffle();
    }
  }

  Future<List<Word>> _loadVocabularyWords(String vocabName) async {
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
          final cells = row.getElementsByTagName('td').map((e) => e.text.trim()).toList();

          return Word(
            hebrew: cells[4].trim(),
            english: cells[5].trim(),
            phonetic: cells[2].trim(),
          );
        }).where((word) => word.isNotEmpty()).toList();
  }

  @override
  SavedState getSavedState() {
    final state = SavedState(
      words: items,
      excluded: excluded,
      currentVocabulary: currentVocabulary,
    );
    return state;
  }

  void _handleDifficultySelection(String difficulty) async {
    if (currentItem == null) return;

    switch (difficulty) {
      case 'again':
        if (currentItem!.rank < 4) {
          currentItem!.rank = 1;
        } else {
          currentItem!.rank = 2;
        }
        break;
      case 'good':
        if (currentItem!.rank == 0) {
          currentItem!.rank = 3;
        } else if (currentItem!.rank < 4) {
          currentItem!.rank += 1;
        } else if (currentItem!.rank > 5) {
          currentItem!.rank -= 1;
        }
        break;
      case 'easy':
        if (currentItem!.rank == 0) {
          if (currentVocabulary == 'A0' || currentVocabulary == 'A1') {
            currentItem!.rank = 10;
          } else {
            currentItem!.rank = 8;
          }
        } else if (currentItem!.rank < 4) {
          currentItem!.rank += 2;
        } else {
          currentItem!.rank += 1;
        }
        break;
    }

    items.removeAt(0);

    if (currentItem!.rank < 10) {
      var offset = currentItem!.rank < 6 ? 0 : Random().nextDouble();
      var index = pow(2, currentItem!.rank + offset).toInt();

      if (index >= items.length) {
        availableVocabularies = await _getVocabularies();
        final nextVocabIndex = availableVocabularies.indexOf(currentVocabulary) + 1;
        if (nextVocabIndex < availableVocabularies.length) {
          setState(() {
            appState = AppState.loading;
          });

          currentVocabulary = availableVocabularies[nextVocabIndex];
          final newWords = await _loadVocabularyWords(currentVocabulary);
          newWords.shuffle();
          items.addAll(newWords);
          await saveState();
        }
      }

      if (index < items.length) {
        items.insert(index, currentItem!);
        lastIndex = index;
      } else {
        items.add(currentItem!);
        lastIndex = items.length;
      }
    } else {
      excluded.add(currentItem!);
      lastIndex = -1;
    }

    selectNextItem();
  }

  Color _getButtonColor(String difficulty) {
    switch (difficulty) {
      case 'again': return Colors.orange;
      case 'good': return Colors.lightBlueAccent;
      case 'easy': return Colors.green;
      default: return Colors.cyan;
    }
  }

  @override
  Widget buildWordCard() {
    var showTranslation = appState == AppState.assessment;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            elevation: 4,
            child: Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (currentItem?.english ?? 'Loading...').replaceAll('; ', '\n'),
                    textScaler: const TextScaler.linear(2),
                    style: lightFont,
                  ),
                  if (showTranslation) ...[
                    const SizedBox(height: 16),
                    Text(
                      currentItem?.hebrew ?? '',
                      textScaler: const TextScaler.linear(2.25),
                      style: boldFont,
                      textDirection: TextDirection.rtl,
                    ),
                    if (currentItem?.phonetic.isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      Text(
                        currentItem?.phonetic ?? '',
                        textScaler: const TextScaler.linear(1.75),
                        style: italicFont,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (showTranslation) ...[
            _buildDictionaryButtons(currentItem?.hebrew ?? ''),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildDictionaryButtons(String word) {
    if (word.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _iconLink(Icons.search, 'https://www.google.com/search?q=${currentItem!.hebrew}', 24),
          const SizedBox(width: 16),
          _iconLink(Icons.list_alt, 'https://www.pealim.com/search/?q=${currentItem!.hebrew}', 24),
          const SizedBox(width: 16),
          _iconLink(Icons.g_translate, 'https://translate.google.com/?sl=iw&tl=en&text=${currentItem!.hebrew}', 24,),
          const SizedBox(width: 16),
          _iconLink(Icons.compare_arrows, 'https://context.reverso.net/translation/hebrew-english/${currentItem!.hebrew}', 30,),
          const SizedBox(width: 16),
          _playHebrewWordIcon(currentItem!.hebrew),
        ],
      ),
    );
  }

  IconButton _iconLink(IconData icon, String link, double iconSize) {
    return IconButton(
      icon: Icon(icon, color: Colors.grey),
      iconSize: iconSize,
      onPressed: () {
        final jsUrl = Uri.encodeFull(link);
        html.window.open(jsUrl, '_blank');
      },
    );
  }

  _playHebrewWordIcon(String hebrewWord) {
    return IconButton(
      icon: Icon(Icons.volume_up, color: Colors.grey),
      iconSize: 24,
      onPressed: () {
        if (hebrewWord != null) {
          _playHebrewWord(hebrewWord);
        }
      },
    );
  }

  @override
  Widget buildActionButtons() {
    var showTranslation = appState == AppState.assessment;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          !showTranslation
              ? _buildShowButton()
              : Row(children: difficulties.map((difficulty) => _buildDifficultyButton(difficulty)).toList())
        ],
      ),
    );
  }

  Expanded _buildDifficultyButton(String difficulty) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: () => _handleDifficultySelection(difficulty),
          style: ElevatedButton.styleFrom(
            backgroundColor: _getButtonColor(difficulty),
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
  }

  Widget _buildShowButton() {
    return GestureDetector(
        onHorizontalDragEnd: (details) => _undoLastAssessment(details),
        child: ElevatedButton(
          onPressed: () => setState(() {
            appState = AppState.assessment;
          }),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32,),
          ),
          child: const Text('            Show            ', style: TextStyle(fontSize: 20),
          ),
        ));
  }

  @override
  Widget buildHeader() {
    var total = items.length;
    var used = items.where((x) => x.rank > 0).toList();
    var known = used.where((x) => x.rank >= 8).toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text(currentVocabulary, style: Theme.of(context).textTheme.bodyLarge),
        Row(children: [
          const Icon(Icons.list, size: 30, color: Colors.black45),
          Text(' ${total - used.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(LucideIcons.check, size: 30, color: Colors.green),
          Text(' ${used.length - known.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(LucideIcons.checkCheck, size: 30, color: Colors.teal),
          Text(' ${known.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(Icons.emoji_events, size: 25, color: Colors.amber),
          Text(' ${excluded.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ],
    );
  }

  void _undoLastAssessment(DragEndDetails details) {
    if (details.primaryVelocity == null && details.primaryVelocity! < 500) return;
    if (items.isEmpty) return;
    if (lastIndex < 0) return;

    var item = items[lastIndex];
    items.removeAt(lastIndex);
    items.insert(0, item);
    lastIndex = -1;
    selectNextItem();
  }
}
