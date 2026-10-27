import 'package:flutter_edge_ai/flutter_edge_ai.dart';

// Wrapper chat — maintient le modèle actif entre les requêtes
class LocalLlm {
  LocalLlm({required this.systemPrompt, this.maxTokens = 2048});

  final String systemPrompt;
  final int maxTokens;

  InferenceModel? _model;

  Future<void> init() async {
    _model = await FlutterEdgeAi.getActiveModel(maxTokens: maxTokens);
  }

  // Génération complète (attend la fin)
  Future<String> generate(String prompt) async {
    final chat = await _model!.createChat(systemInstruction: systemPrompt);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

    final buf = StringBuffer();
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) buf.write(r.token);
    }
    return buf.toString();
  }

  // Stream token par token
  Stream<String> stream(String prompt) async* {
    final chat = await _model!.createChat(systemInstruction: systemPrompt);
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

    await for (final r in chat.generateChatResponseAsync()) {
      if (r is TextResponse) yield r.token;
    }
  }

  Future<void> dispose() => _model?.close() ?? Future.value();
}