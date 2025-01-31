import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mila_ivrit/vocabulary_service.dart';

import 'base_learning.dart';
import 'main.dart';
import 'web_tts.dart';

const boldFont = TextStyle(fontWeight: FontWeight.bold);
const lightFont = TextStyle(fontWeight: FontWeight.w300 );
const italicFont = TextStyle(fontWeight: FontWeight.w300, fontStyle: FontStyle.italic);

class VocabularyLearningScreenState
    extends BaseLearningScreenState<Word, VocabularyLearningScreen> {
  final _difficulties = ['again', 'good', 'easy'];
  final _finalRank = 11;
  final _middleRank = 5;
  final _vocabularyService = VocabularyService();

  int _lastIndex = -1;
  int _vocabularyIndex = 0;
  String _currentVocabulary = '';

  List<Word> _excluded = [];
  List<String>? _availableVocabularies;

  @override
  String get version => '1.0.2';

  @override
  String get prefsKey => 'hebrew_vocabulary';

  void _playHebrewWord(String hebrewWord) {
    try {
      WebTTS.speak(hebrewWord);
    } catch (e) {}
  }

  Future<List<String>> _ensureVocabulariesLoaded() async {
    _availableVocabularies ??= await _vocabularyService.getVocabularies();
    return _availableVocabularies!;
  }

  Future<void> _addVocabulary(int vocabularyIndex) async {
    var availableVocabularies = await _ensureVocabulariesLoaded();
    _currentVocabulary = availableVocabularies[vocabularyIndex];
    _vocabularyIndex = vocabularyIndex;

    var vocabulary = await _vocabularyService.getVocabularyWords(vocabularyIndex);
    vocabulary.shuffle();
    vocabulary.sort((a, b) => a.hebrew.length.compareTo(b.hebrew.length));

    items.addAll(vocabulary);
  }

  @override
  Future<void> loadInitState() async {
    try {
      if (!await _vocabularyService.checkInternetConnection()) {
        setState(() {
          appState = AppState.noInternet;
        });
        return;
      }

      await _addVocabulary(_vocabularyIndex);
    } catch (e, stackTrace) {
      setState(() {
        appState = AppState.error;
        error = AppError(e.toString(), stackTrace.toString());
      });
    }
  }

  @override
  Future<void> syncWithSource() async {
    try {
      if (!await _vocabularyService.checkInternetConnection()) {
        return;
      }

      _lastIndex = -1;
      setState(() {
        appState = AppState.loading;
      });

      final List<Word> combinedWords = [];
      for (var i = 0; i <= _vocabularyIndex; i++) {
        combinedWords.addAll(await _vocabularyService.getVocabularyWords(i));
      }

      final sourceMap = <String, Word>{};
      for (final word in combinedWords) {
        final key = '${word.english}-${word.hebrew}';
        sourceMap[key] = word;
      }

      await _syncWithSourceMap(sourceMap);

      setState(() {
        appState = AppState.guess;
      });
    } catch (e, stackTrace) {
      setState(() {
        appState = AppState.error;
        error = AppError(e.toString(), stackTrace.toString());
      });
    }
  }

  Future<void> _syncWithSourceMap(Map<String, Word> sourceMap) async {
    final sourceKeys = sourceMap.keys.toSet();
    final existingKeys = {
      ...items.map((w) => '${w.english}-${w.hebrew}'),
      ..._excluded.map((w) => '${w.english}-${w.hebrew}')
    };

    items.removeWhere((word) => !sourceKeys.contains('${word.english}-${word.hebrew}'));
    _excluded.removeWhere((word) => !sourceKeys.contains('${word.english}-${word.hebrew}'));

    for (var word in items) {
      word.phonetic = sourceMap['${word.english}-${word.hebrew}']!.phonetic;
    }

    final newWords = sourceMap.entries
        .where((entry) => !existingKeys.contains(entry.key))
        .map((entry) => entry.value)
        .toList();

    items.addAll(newWords);
    await saveState();
  }

  @override
  void loadSavedState(String savedStateJson) {
    final savedState = SavedState.fromJson(json.decode(savedStateJson));
    items.clear();
    items.addAll(savedState.words);
    _excluded = savedState.excluded;
    _vocabularyIndex = savedState.vocabularyIndex;
    _currentVocabulary = savedState.currentVocabulary;
  }

  @override
  SavedState getSavedState() {
    return SavedState(
        words: items,
        excluded: _excluded,
        vocabularyIndex: _vocabularyIndex,
        currentVocabulary: _currentVocabulary);
  }

  Future<void> tryGoNextLevel() async {
    if (items.any((word) => word.rank > 0)) return;
    _excluded.addAll(items);
    items.clear();
    await _tryAddVocabulary();
    selectNextItem();
  }

  void _handleDifficultySelection(String difficulty) async {
    if (currentItem == null) return;

    switch (difficulty) {
      case 'again':
        if (currentItem!.rank < _middleRank) {
          currentItem!.rank = 1;
        } else {
          currentItem!.rank = 3;
        }
        break;
      case 'good':
        if (currentItem!.rank == 0) {
          currentItem!.rank = _middleRank;
        } else if (currentItem!.rank < _middleRank - 1) {
          currentItem!.rank += 1;
        } else if (currentItem!.rank > _middleRank) {
          currentItem!.rank -= 1;
        }
        break;
      case 'easy':
        if (currentItem!.rank == 0) {
          currentItem!.rank = _finalRank;
        } else if (currentItem!.rank < _middleRank) {
          currentItem!.rank += 2;
        } else {
          currentItem!.rank += 1;
        }
        break;
    }

    items.removeAt(0);

    if (currentItem!.rank < _finalRank) {
      var offset =
          currentItem!.rank < (_middleRank + 2) ? 0 : Random().nextDouble();
      var index = pow(2, currentItem!.rank + offset).toInt();

      if (index >= items.length) {
        await _tryAddVocabulary();
      }

      if (index < items.length) {
        items.insert(index, currentItem!);
        _lastIndex = index;
      } else {
        items.add(currentItem!);
        _lastIndex = items.length;
      }
    } else {
      _excluded.add(currentItem!);
      _lastIndex = -2;
    }

    if (items.isEmpty) {
      await _tryAddVocabulary();
    }

    selectNextItem();
  }

  Future<void> _tryAddVocabulary() async {
    final vocabularies = await _ensureVocabulariesLoaded();
    if (_vocabularyIndex + 1 < vocabularies.length) {
      setState(() {
        appState = AppState.loading;
      });
      await _addVocabulary(_vocabularyIndex + 1);
      await saveState();
    }
  }

  void _undoLastAssessment(DragEndDetails details) {
    if (details.primaryVelocity == null && details.primaryVelocity! < 500) {
      return;
    }
    if (items.isEmpty) return;

    if (_lastIndex > 0) {
      var item = items[_lastIndex];
      items.removeAt(_lastIndex);
      items.insert(0, item);
    } else if (_lastIndex == -2) {
      var ind = _excluded.length - 1;
      var item = _excluded[ind];
      _excluded.removeAt(ind);
      items.insert(0, item);
    }

    _lastIndex = -1;
    selectNextItem();
  }

  Color _getButtonColor(String difficulty) {
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
                    currentItem!.english.replaceAll('; ', '\n'),
                    textScaler: const TextScaler.linear(2),
                    style: lightFont,
                  ),
                  if (showTranslation) ...[
                    const SizedBox(height: 16),
                    Text(
                      currentItem!.hebrew,
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
          _iconLink(Icons.search,
              'https://www.google.com/search?q=${currentItem!.hebrew}', 24),
          const SizedBox(width: 16),
          _iconLink(Icons.list_alt,
              'https://www.pealim.com/search/?q=${currentItem!.hebrew}', 24),
          const SizedBox(width: 16),
          _iconLink(
            Icons.g_translate,
            'https://translate.google.com/?sl=iw&tl=en&text=${currentItem!.hebrew}',
            24,
          ),
          const SizedBox(width: 16),
          _iconLink(
            Icons.compare_arrows,
            'https://context.reverso.net/translation/hebrew-english/${currentItem!.hebrew}',
            30,
          ),
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

  IconButton _playHebrewWordIcon(String hebrewWord) {
    return IconButton(
      icon: Icon(Icons.volume_up, color: Colors.grey),
      iconSize: 24,
      onPressed: () => _playHebrewWord(hebrewWord),
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
              : Row(
                  children: _difficulties
                      .map((difficulty) => _buildDifficultyButton(difficulty))
                      .toList())
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
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 32,
            ),
          ),
          child: Text(
            '            Show            ',
            style: TextStyle(fontSize: 20),
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
        GestureDetector(
          onTap: () => tryGoNextLevel(),
          child: Text(_currentVocabulary,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
        Row(children: [
          const Icon(Icons.list, size: 30, color: Colors.black45),
          Text(' ${total - used.length}',
              style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(LucideIcons.check, size: 30, color: Colors.green),
          Text(' ${used.length - known.length}',
              style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(LucideIcons.checkCheck, size: 30, color: Colors.teal),
          Text(' ${known.length}',
              style: Theme.of(context).textTheme.bodyLarge),
        ]),
        Row(children: [
          const Icon(Icons.emoji_events, size: 25, color: Colors.amber),
          Text(' ${_excluded.length}',
              style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ],
    );
  }
}
