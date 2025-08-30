import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

const boldFont = TextStyle(fontWeight: FontWeight.bold);
const lightFont = TextStyle(fontWeight: FontWeight.w300);
const italicFont =
    TextStyle(fontWeight: FontWeight.w300, fontStyle: FontStyle.italic);

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
  final String hebrew;
  final String english;
  final String phonetic;
  int rank;

  Word({
    required this.hebrew,
    required this.english,
    required this.phonetic,
    this.rank = 0,
  });

  Map<String, dynamic> toJson() => {
        'hebrew': hebrew,
        'english': english,
        'phonetic': phonetic,
        'rank': rank,
      };

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        hebrew: json['hebrew'],
        english: json['english'],
        phonetic: json['phonetic'],
        rank: json['rank'] ?? 0,
      );
}

class SavedState {
  final List<Word> words;
  final List<Word> excluded;
  final String vocabularyHash;

  SavedState({
    required this.words,
    required this.excluded,
    required this.vocabularyHash,
  });

  Map<String, dynamic> toJson() => {
        'words': words.map((w) => w.toJson()).toList(),
        'excluded': excluded.map((w) => w.toJson()).toList(),
        'vocabularyHash': vocabularyHash,
      };

  factory SavedState.fromJson(Map<String, dynamic> json) => SavedState(
        words: (json['words'] as List? ?? [])
            .map((w) => Word.fromJson(w))
            .toList(),
        excluded: (json['excluded'] as List? ?? [])
            .map((w) => Word.fromJson(w))
            .toList(),
        vocabularyHash: json['vocabularyHash'] ?? '',
      );
}

class VocabularyLearningScreen extends StatefulWidget {
  const VocabularyLearningScreen({super.key});

  @override
  State<VocabularyLearningScreen> createState() =>
      VocabularyLearningScreenState();
}

class VocabularyLearningScreenState extends State<VocabularyLearningScreen> {
  static const String version = '2.0.5';
  static const String prefsKey = 'hebrew_vocabulary_v2';
  static const int finalRank = 6;
  static const int midRank = 4;

  List<Word> words = [];
  List<Word> excluded = [];
  Word? currentWord;
  bool showTranslation = false;
  bool isLoading = true;
  String? error;
  String currentVocabularyHash = '';

  @override
  void initState() {
    super.initState();
    _loadVocabulary();
  }

  String _calculateHash(String content) {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<List<Word>> _loadVocabularyFromAssets() async {
    try {
      final content = await rootBundle.loadString('assets/vocabulary.tsv');
      currentVocabularyHash = _calculateHash(content);

      final lines = content.split('\n');
      final words = <Word>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final parts = line.split('\t');
        if (parts.length >= 3) {
          final hebrew = parts[0].trim();
          final phonetic = parts[1].trim();
          final english = parts[2].trim();

          if (hebrew.isNotEmpty && english.isNotEmpty) {
            words.add(
                Word(hebrew: hebrew, english: english, phonetic: phonetic));
          }
        }
      }

      return words;
    } catch (e) {
      throw Exception('Failed to load vocabulary: $e');
    }
  }

  Future<void> _loadVocabulary() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });

      // Load vocabulary from assets
      final vocabularyWords = await _loadVocabularyFromAssets();

      // Try to load saved state
      final prefs = await SharedPreferences.getInstance();
      final savedStateJson = prefs.getString(prefsKey);

      bool needsReload = false;

      if (savedStateJson != null) {
        final savedState = SavedState.fromJson(json.decode(savedStateJson));

        // Check if vocabulary hash has changed
        if (savedState.vocabularyHash != currentVocabularyHash) {
          needsReload = true;
        } else {
          // Use saved state
          words = savedState.words;
          excluded = savedState.excluded;
        }
      } else {
        needsReload = true;
      }

      if (needsReload) {
        // Fresh start or vocabulary changed
        words = vocabularyWords;
        excluded = [];
        await _saveState();
      }

      _selectNextWord();

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        error = e.toString();
      });
    }
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final state = SavedState(
        words: words,
        excluded: excluded,
        vocabularyHash: currentVocabularyHash,
      );
      await prefs.setString(prefsKey, json.encode(state.toJson()));
    } catch (e) {
      printError('Error saving state: $e');
    }
  }

  void printError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _selectNextWord() {
    if (words.isEmpty) {
      if (excluded.isNotEmpty) {
        // Reset all words
        words = excluded;
        excluded = [];
        for (var word in words) {
          word.rank = 0;
        }
        words.shuffle();
      }
    }

    if (words.isNotEmpty) {
      setState(() {
        currentWord = words.first;
        showTranslation = false;
      });
    }
  }

  void _handleDifficulty(String difficulty) async {
    if (currentWord == null) return;

    switch (difficulty) {
      case 'again':
        currentWord!.rank = 0;
        break;
      case 'good':
        currentWord!.rank++;
        break;
      case 'easy':
        currentWord!.rank += 2;
        break;
    }

    words.removeAt(0);
    if (currentWord!.rank > finalRank) {
      excluded.add(currentWord!);
    } else {
      var index =
          pow(2, (currentWord!.rank + 1)).toInt().clamp(1, words.length);
      words.insert(index, currentWord!);
    }

    await _saveState();
    _selectNextWord();
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
              'Error Loading Vocabulary',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(error ?? 'Unknown error'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadVocabulary,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final learning = words.where((w) => w.rank > 0).length;
    final mastered = excluded.length;
    final new_ = words.where((w) => w.rank == 0).length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(Icons.fiber_new, new_, Colors.blue),
          _buildStatItem(Icons.school, learning, Colors.orange),
          _buildStatItem(Icons.check_circle, mastered, Colors.green),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, int count, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 6),
        Text('$count',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget buildWordCard() {
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
                children:
                    (currentWord!.rank >= midRank || currentWord!.rank == 0)
                        ? getL12Text(showTranslation)
                        : getL21Text(showTranslation),
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

  List<Widget> getL12Text(bool showTranslation) {
    return [
      Text(
        currentWord!.english.replaceAll('; ', '\n'),
        textScaler: const TextScaler.linear(2),
        style: lightFont,
      ),
      if (showTranslation) ...[
        const SizedBox(height: 16),
        ...getHebrew(),
      ],
    ];
  }

  List<Widget> getL21Text(bool showTranslation) {
    return [
      ...getHebrew(),
      if (showTranslation) ...[
        const SizedBox(height: 16),
        Text(
          currentWord!.english.replaceAll('; ', '\n'),
          textScaler: const TextScaler.linear(2),
          style: lightFont,
        ),
      ],
    ];
  }

  List<Widget> getHebrew() {
    return [
      Text(
        currentWord!.hebrew,
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
    ];
  }

  Widget _buildDictionaryButtons(String word) {
    if (word.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _iconLink(Icons.search,
              'https://www.google.com/search?q=${currentWord!.hebrew}', 24),
          const SizedBox(width: 16),
          _iconLink(Icons.list_alt,
              'https://www.pealim.com/search/?q=${currentWord!.hebrew}', 24),
          const SizedBox(width: 16),
          _iconLink(
            Icons.g_translate,
            'https://translate.google.com/?sl=iw&tl=en&text=${currentWord!.hebrew}&op=translate',
            24,
          ),
          const SizedBox(width: 16),
          _iconLink(
            Icons.compare_arrows,
            'https://context.reverso.net/translation/hebrew-english/${currentWord!.hebrew}',
            30,
          ),
          const SizedBox(width: 16),
          _playHebrewWordIcon(currentWord!.hebrew),
        ],
      ),
    );
  }

  IconButton _playHebrewWordIcon(String hebrewWord) {
    return IconButton(
      icon: const Icon(Icons.volume_up, color: Colors.grey),
      iconSize: 24,
      onPressed: () => _playHebrewWord(hebrewWord),
    );
  }

  void _playHebrewWord(String hebrewWord) {
    try {
      final speechSynthesis = web.window.speechSynthesis;
      final utterance = web.SpeechSynthesisUtterance(hebrewWord);

      utterance.lang = 'he-IL';
      utterance.rate = 0.8;
      utterance.pitch = 1.0;

      speechSynthesis.speak(utterance);
    } catch (e) {
      printError('TTS error: $e');
    }
  }

  IconButton _iconLink(IconData icon, String link, double iconSize) {
    return IconButton(
      icon: Icon(icon, color: Colors.grey),
      iconSize: iconSize,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: currentWord!.hebrew));
        final jsUrl = Uri.encodeFull(link);
        web.window.open(jsUrl, '_blank');
      },
    );
  }

  Widget _buildActionButtons() {
    if (!showTranslation) {
      return ElevatedButton(
        onPressed: () => setState(() => showTranslation = true),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
        ),
        child: const Text('Show', style: TextStyle(fontSize: 20)),
      );
    }

    return Row(
      children: [
        _buildDifficultyButton('Again', Colors.orange, 'again'),
        const SizedBox(width: 8),
        _buildDifficultyButton('Good', Colors.lightBlueAccent, 'good'),
        const SizedBox(width: 8),
        _buildDifficultyButton('Easy', Colors.green, 'easy'),
      ],
    );
  }

  Widget _buildDifficultyButton(String label, Color color, String difficulty) {
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _handleDifficulty(difficulty),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? _buildLoadingScreen()
            : error != null
                ? _buildErrorScreen()
                : Column(
                    children: [
                      _buildHeader(),
                      Expanded(child: buildWordCard()),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: _buildActionButtons(),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'Version: $version • Rank: ${currentWord?.rank ?? 0}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
