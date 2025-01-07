import 'dart:math';
import 'dart:html' as html;
import 'package:darq/darq.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

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

  bool isNotEmpty() => english.isNotEmpty && hebrew.isNotEmpty;
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
            .where((word) => word.isNotEmpty())
            .toList(),
        currentVocabulary: json['currentVocabulary'],
      );
}

class VocabularyLearningScreen extends StatefulWidget {
  const VocabularyLearningScreen({super.key});

  @override
  State<VocabularyLearningScreen> createState() => _VocabularyLearningScreenState();
}

enum AppState {
  loading,
  error,
  noInternet,
  guess,
  assessment
}

class AppError {
  final String message;
  final String? stackTrace;

  AppError(this.message, [this.stackTrace]);
}

class _VocabularyLearningScreenState extends State<VocabularyLearningScreen> with WidgetsBindingObserver {
  AppState _appState = AppState.loading;
  AppError? _error;
  List<Word> words = [];
  Word? currentWord;
  Timer? _autoSaveTimer;
  final difficulties = ['again', 'good', 'easy'];
  final uri = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTTUPG22pCGbrlYULESZ5FFyYTo9jyFGFEBk1Wx41gZiNvkonYcLPypdPGCZzFxTzywU4hCra4Fmx-b/pubhtml';
  bool _isSaving = false;
  String currentVocabulary = '';
  List<String> availableVocabularies = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadState();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      saveState();
    });
  }

  Future<bool> _checkInternetConnection() async {
    return html.window.navigator.onLine ?? false;
  }

  Future<List<String>> getVocabularies() async {
    try {
      if (!await _checkInternetConnection()) {
        setState(() {
          _appState = AppState.noInternet;
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
        _appState = AppState.error;
        _error = AppError(e.toString(), stackTrace.toString());
      });
      return [];
    }
  }

  Future<void> loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStateJson = prefs.getString('savedState');

      if (savedStateJson == null) {
        availableVocabularies = await getVocabularies();
        if (_appState != AppState.error && _appState != AppState.noInternet) {
          currentVocabulary = availableVocabularies.first;
          words = await loadVocabularyWords(currentVocabulary);
          words.shuffle();
        }
      } else {
        final savedState = SavedState.fromJson(json.decode(savedStateJson));
        words = savedState.words;
        currentVocabulary = savedState.currentVocabulary;
      }

      if (_appState != AppState.error && _appState != AppState.noInternet) {
        selectNextWord();
      }
    } catch (e, stackTrace) {
      setState(() {
        _appState = AppState.error;
        _error = AppError(e.toString(), stackTrace.toString());
      });
    }
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
      final cells = row.getElementsByTagName('td').map((e) => e.text.trim()).toList();
      return Word(
        hebrew: cells[4].trim(),
        english: cells[5].trim(),
        phonetic: cells[2].trim(),
      );
    })
        .where((word) => word.isNotEmpty())
        .toList();
  }

  Future<void> saveState() async {
    if (words.length < 10) return;
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

  void selectNextWord() {
    if (words.isEmpty) return;

    setState(() {
      _appState = AppState.guess;
      currentWord = words[0];
    });
  }

  void handleShowTranslation() {
    setState(() {
      _appState = AppState.assessment;
    });
  }

  void handleDifficultySelection(String difficulty) async {
    if (currentWord == null) return;

    switch (difficulty) {
      case 'again':
        if (currentWord!.rank < 4) {
          currentWord!.rank = 1;
        } else  {
          currentWord!.rank = 2;
        }
        break;
      case 'good':
        if (currentWord!.rank == 0) {
          currentWord!.rank = 3;
        } else if (currentWord!.rank < 4) {
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
      availableVocabularies = await getVocabularies();
      final nextVocabIndex = availableVocabularies.indexOf(currentVocabulary) + 1;
      if (nextVocabIndex < availableVocabularies.length) {
        setState(() {
          _appState = AppState.loading;
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
      case 'again': return Colors.orange;
      case 'good': return Colors.lightBlueAccent;
      case 'easy': return Colors.green;
      default: return Colors.cyan;
    }
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'An error occurred',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(_error?.message ?? 'Unknown error'),
            if (_error?.stackTrace != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _error!.stackTrace!,
                    style: const TextStyle(fontFamily: 'Courier'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: loadState,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoInternetScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No Internet Connection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Please check your connection and try again'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: loadState,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading vocabulary...'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_appState) {
          AppState.loading => _buildLoadingScreen(),
          AppState.error => _buildErrorScreen(),
          AppState.noInternet => _buildNoInternetScreen(),
          AppState.guess => _buildMainContent(showTranslation: false),
          AppState.assessment => _buildMainContent(showTranslation: true),
        },
      ),
    );
  }

  Widget _buildWordCard(bool showTranslation) {
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
                    (currentWord?.english ?? 'Loading...').replaceAll('; ', '\n'),
                    textScaler: const TextScaler.linear(2),
                    style: lightFont,
                  ),
                  if (showTranslation) ...[
                    const SizedBox(height: 16),
                    Text(
                      currentWord?.hebrew ?? '',
                      textScaler: const TextScaler.linear(2.25),
                      style: boldFont,
                      textDirection: TextDirection.rtl,
                    ),
                    if (currentWord?.phonetic.isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      Text(
                        currentWord?.phonetic ?? '',
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
            _buildDictionaryButtons(currentWord?.hebrew ?? ''),
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
          iconLink(Icons.list_alt, 'https://www.pealim.com/search/?q=${currentWord!.hebrew}', 24),
          const SizedBox(width: 16),
          iconLink(Icons.g_translate, 'https://translate.google.com/?sl=iw&tl=en&text=${currentWord!.hebrew}', 24,),
          const SizedBox(width: 16),
          iconLink(Icons.compare_arrows, 'https://context.reverso.net/translation/hebrew-english/${currentWord!.hebrew}', 30,),
        ],
      ),
    );
  }

  IconButton iconLink(IconData icon, String link, double iconSize) {
    return IconButton(
      icon: Icon(icon, color: Colors.grey),
      iconSize: iconSize,
      onPressed: () {
        final jsUrl = Uri.encodeFull(link);
        html.window.open(jsUrl, '_blank');
      },
    );
  }

  Widget _buildActionButtons(bool showTranslation) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          !showTranslation
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
        ],
      ),
    );
  }

  Widget _buildHeader(List<Word> used, List<Word> learned, int points) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text(currentVocabulary, style: Theme.of(context).textTheme.bodyLarge),
        Row(children: [
          const Icon(Icons.list, size: 30, color: Colors.black45),
          Text(' ${words.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(LucideIcons.check, size: 30, color: Colors.green),
          Text(' ${used.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(LucideIcons.checkCheck, size: 30, color: Colors.teal),
          Text(' ${learned.length}', style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(Icons.emoji_events, size: 25, color: Colors.amber),
          Text(' $points', style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ],
    );
  }

  Widget _buildMainContent({required bool showTranslation}) {
    var used = words.where((x) => x.rank > 0).toList();
    var learned = used.where((x) => x.rank > 8).toList();
    var points = used.sum((word) => word.rank);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildHeader(used, learned, points),
          Expanded(
            child: _buildWordCard(showTranslation),
          ),
          _buildActionButtons(showTranslation),
          Text('Version: 0.8.1 • Word rank: ${currentWord?.rank ?? 0}'),
        ],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _autoSaveTimer?.cancel();
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