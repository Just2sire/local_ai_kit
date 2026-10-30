import 'dart:convert';

import 'package:flutter_edge_ai_rag/flutter_edge_ai_rag.dart';
import 'package:flutter_edge_ai_sqlite/flutter_edge_ai_sqlite.dart';
import 'package:path_provider/path_provider.dart';

import '../input/doc_chunk.dart';
import '../llm/local_llm.dart';
import 'rag_config.dart';

/// Facade RAG on-device — encapsule `flutter_edge_ai_rag`.
///
/// Les préfixes de tâche d'embedding sont appliqués par
/// [FlutterEdgeAiActiveEmbedder] : il faut donc transmettre le texte brut,
/// sans préfixe ajouté manuellement.
class LocalRag {
  LocalRag(this.config);

  final RagConfig config;
  RagIndex? _index;

  bool get isInitialized => _index != null;

  Future<void> init() async {
    if (_index != null) return;

    final directory = await getApplicationDocumentsDirectory();
    final rag = FlutterEdgeAiRag(providers: [SqliteVectorStoreProvider()]);
    final embedder = FlutterEdgeAiActiveEmbedder(
      profileId: config.embedderProfileId,
    );

    _index = await rag.open(
      spec: VectorStoreSpec(
        providerId: 'sqlite',
        location: '${directory.path}/${config.dbName}',
      ),
      embedder: embedder,
    );
  }

  RagIndex get _requireIndex {
    final index = _index;
    if (index == null) {
      throw StateError(
        'LocalRag.init() doit être appelé avant toute opération.',
      );
    }
    return index;
  }

  /// Indexe un chunk texte.
  Future<void> add(DocChunk chunk) async {
    await _requireIndex.add(
      id: chunk.id,
      document: EmbeddingInput.text(chunk.text),
      // Le texte stocké est le contenu brut : l'embedding porte déjà le
      // préfixe de tâche, qui n'a pas sa place dans le contexte restitué.
      content: chunk.text,
      metadata: chunk.metadata.isNotEmpty ? jsonEncode(chunk.metadata) : null,
    );
  }

  /// Indexe plusieurs chunks.
  Future<void> addAll(List<DocChunk> chunks) async {
    for (final chunk in chunks) {
      await add(chunk);
    }
  }

  /// Supprime un chunk par id.
  Future<void> remove(String id) => _requireIndex.remove(id: id);

  /// Recherche sémantique — renvoie les chunks les plus proches.
  Future<List<RetrievalResult>> search(String query) {
    return _requireIndex.search(
      query: EmbeddingInput.text(query),
      topK: config.topK,
    );
  }

  String _buildPrompt(String question, List<RetrievalResult> results) {
    final context = results.map((result) => result.content).join('\n\n---\n\n');
    return '''Contexte :
$context

Question : $question
Réponse :''';
  }

  /// RAG complet : retrieval -> prompt -> génération.
  Future<String> queryWithLlm(LocalLlm llm, String question) async {
    final results = await search(question);
    return llm.generate(_buildPrompt(question, results));
  }

  /// RAG complet en streaming, avec possibilité de réutiliser
  /// les résultats d'une recherche déjà effectuée.
  Stream<String> queryStreamWithLlm(
    LocalLlm llm,
    String question, {
    List<RetrievalResult>? results,
  }) async* {
    final retrieved = results ?? await search(question);
    yield* llm.stream(_buildPrompt(question, retrieved));
  }

  Future<void> dispose() async {
    final index = _index;
    _index = null;
    await index?.dispose();
  }
}
