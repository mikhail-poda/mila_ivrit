import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class WebUtilsWeb {
  DateTime? _lastEventTime;
  static const Duration _minEventInterval = Duration(seconds: 2);

  void initializeLifecycleListeners(Function saveCallback) {
    void handleSaveEvent() {
      final now = DateTime.now();
      if (_lastEventTime != null &&
          now.difference(_lastEventTime!) < _minEventInterval) {
        return;
      }
      _lastEventTime = now;
      saveCallback();
    }

    html.window.onBeforeUnload.listen((event) {
      handleSaveEvent();
    });

    html.document.onVisibilityChange.listen((event) {
      if (html.document.hidden ?? false) {
        handleSaveEvent();
      }
    });
  }
}

abstract class LearnableItem {
  int rank;

  LearnableItem({this.rank = 0});

  Map<String, dynamic> toJson();
  bool isNotEmpty();
}

class AppError {
  final String message;
  final String? stackTrace;

  AppError(this.message, [this.stackTrace]);
}

enum AppState {
  loading,
  error,
  noInternet,
  guess,
  assessment
}

abstract class BaseSavedState {
  Map<String, dynamic> toJson();
}

abstract class BaseLearningScreen<T extends LearnableItem> extends StatefulWidget {
  const BaseLearningScreen({super.key});
}

abstract class BaseLearningScreenState<T extends LearnableItem, S extends BaseLearningScreen<T>> extends State<S> with WidgetsBindingObserver {
  AppState appState = AppState.loading;
  AppError? error;
  List<T> items = [];
  T? currentItem;
  Timer? _autoSaveTimer;
  bool _isSaving = false;

  // Abstract methods to be implemented by specific apps
  String get prefsKey;
  String get version;
  void loadSavedState(String savedStateJson);
  Future<void> loadInitState();
  BaseSavedState getSavedState();
  Widget buildHeader();
  Widget buildWordCard();
  Widget buildActionButtons();
  Future<void> syncWithSource();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WebUtilsWeb().initializeLifecycleListeners(() => saveState());
    _loadState();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      saveState();
    });
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStateJson = prefs.getString(prefsKey);

      if (savedStateJson == null) {
        await loadInitState();
      } else {
        loadSavedState(savedStateJson);
      }

      if (appState != AppState.error && appState != AppState.noInternet) {
        selectNextItem();
      }
    } catch (e, stackTrace) {
      setState(() {
        appState = AppState.error;
        error = AppError(e.toString(), stackTrace.toString());
      });
    }
  }

  Future<void> saveState() async {
    if (items.isEmpty) return;
    if (_isSaving) return;
    _isSaving = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final state = getSavedState();
      await prefs.setString(prefsKey, json.encode(state.toJson()));
    } finally {
      _isSaving = false;
    }
  }

  void selectNextItem() {
    if (items.isEmpty) return;
    setState(() {
      appState = AppState.guess;
      currentItem = items[0];
    });
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
            Text('An error occurred', style: Theme.of(context).textTheme.headlineSmall,),
            const SizedBox(height: 8),
            Text(error?.message ?? 'Unknown error'),
            if (error?.stackTrace != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8),),
                child: SingleChildScrollView(child: Text(error!.stackTrace!, style: const TextStyle(fontFamily: 'Courier'),),),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _loadState, child: const Text('Retry'),),
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
          Text('No Internet Connection', style: Theme.of(context).textTheme.headlineSmall,),
          const SizedBox(height: 8),
          const Text('Please check your connection and try again'),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _loadState, child: const Text('Retry'),),
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
          Text('Loading...'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (appState) {
          AppState.loading => _buildLoadingScreen(),
          AppState.error => _buildErrorScreen(),
          AppState.noInternet => _buildNoInternetScreen(),
          AppState.guess => _buildMainRefreshableContent(),
          AppState.assessment => _buildMainContent(),
        },
      ),
    );
  }

  Widget _buildMainRefreshableContent() {
    return RefreshIndicator(
      onRefresh: () async {
        await syncWithSource();
      },
      child: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          buildHeader(),
          Expanded(child: buildWordCard(),),
          buildActionButtons(),
          Text('Version: $version • Word rank: ${currentItem?.rank ?? 0}'),
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