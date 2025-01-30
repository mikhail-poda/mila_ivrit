import 'dart:js' as js;

class WebTTS {
  static void speak(String text) {
    try {
      final speechSynthesis = js.context['speechSynthesis'];
      final utterance = js.JsObject(js.context['SpeechSynthesisUtterance'], [text]);

      // Set language to Hebrew
      utterance['lang'] = 'he-IL';
      utterance['rate'] = 0.8; // Slightly slower rate
      utterance['pitch'] = 1.0;

      speechSynthesis.callMethod('speak', [utterance]);
    } catch (e) {
      print('Web TTS error: $e');
    }
  }
}