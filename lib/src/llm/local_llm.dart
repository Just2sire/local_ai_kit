import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// Wrapper de génération locale.
///
/// Le modèle actif de `flutter_edge_ai` est récupéré une seule fois dans
/// [init], puis réutilisé pour chaque requête. Chaque génération ouvre un
/// chat dédié et le ferme à la fin pour ne pas laisser de session active.
class LocalLlm {
  LocalLlm({required this.systemPrompt, this.maxTokens = 2048});

  final String systemPrompt;
  final int maxTokens;

  InferenceModel? _model;

  bool get isInitialized => _model != null;

  Future<void> init() async {
    if (_model != null) return;
    _model = await FlutterEdgeAi.getActiveModel(maxTokens: maxTokens);
  }

  InferenceModel get _requireModel {
    final model = _model;
    if (model == null) {
      throw StateError(
        'LocalLlm.init() doit être appelé avant toute génération.',
      );
    }
    return model;
  }

  Future<InferenceChat> _createChat() {
    return _requireModel.createChat(systemInstruction: systemPrompt);
  }

  /// Génération complète (attend la fin).
  Future<String> generate(String prompt) async {
    final chat = await _createChat();
    try {
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      final buffer = StringBuffer();
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) buffer.write(response.token);
      }
      return buffer.toString();
    } finally {
      await chat.close();
    }
  }

  /// Stream token par token.
  Stream<String> stream(String prompt) async* {
    final chat = await _createChat();
    try {
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) yield response.token;
      }
    } finally {
      await chat.close();
    }
  }

  Future<void> dispose() async {
    final model = _model;
    _model = null;
    await model?.close();
  }
}
