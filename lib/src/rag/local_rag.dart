import 'dart:convert';
import 'package:flutter_edge_ai_rag/flutter_edge_ai_rag.dart';
import 'package:flutter_edge_ai_sqlite/flutter_edge_ai_sqlite.dart';
import 'package:path_provider/path_provider.dart';

import '../input/doc_chunk.dart';
import '../input/embed_task.dart';
import '../llm/local_llm.dart';
import 'rag_config.dart';

// Facade RAG on-device — encapsule flutter_edge_ai_rag
class LocalRag {
  LocalRag(this.config);

  final RagConfig config;
  RagIndex? _index;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final rag = FlutterEdgeAiRag(providers: [SqliteVectorStoreProvider()]);
    final embedder = FlutterEdgeAiActiveEmbedder(
      profileId: config.embedderProfileId,
    );
    _index = await rag.open(
      spec: VectorStoreSpec(
        providerId: 'sqlite',
        location: '${dir.path}/${config.dbName}',
      ),
      embedder: embedder,
    );
  }

  // Indexer un chunk texte
  Future<void> add(DocChunk chunk) async {
    await _index!.add(
      id: chunk.id,
      document: EmbeddingInput.text(EmbedTask.document.apply(chunk.text)),
      metadata: chunk.metadata.isNotEmpty ? jsonEncode(chunk.metadata) : null,
    );
  }

  // Indexer plusieurs chunks d'un coup
  Future<void> addAll(List<DocChunk> chunks) async {
    for (final c in chunks) {
      await add(c);
    }
  }

  // Supprimer un chunk par id
  Future<void> remove(String id) => _index!.remove(id: id);

  // Recherche sémantique — renvoie les chunks les plus proches
  Future<List<RetrievalResult>> search(String query) {
    return _index!.search(
      query: EmbeddingInput.text(EmbedTask.query.apply(query)),
      topK: config.topK,
    );
  }

  // RAG complet : retrieval -> prompt -> génération
  Future<String> queryWithLlm(LocalLlm llm, String question) async {
    final results = await search(question);
    final context = results
        .map((r) => r.content.replaceFirst(EmbedTask.document.prefix, ''))
        .join('\n\n---\n\n');

    final prompt = '''Contexte :
$context

Question : $question
Réponse :''';

    return llm.generate(prompt);
  }

  
  // RAG complet en streaming, avec possibilité de réutiliser
  // les résultats d'une recherche déjà effectuée.
  Stream<String> queryStreamWithLlm(
    LocalLlm llm,
    String question, {
    List<RetrievalResult>? results,
  }) async* {
    final retrieved = results ?? await search(question);

    final context = retrieved
        .map(
          (r) => r.content.replaceFirst(
            EmbedTask.document.prefix,
            '',
          ),
        )
        .join('\n\n---\n\n');

    final prompt = '''Contexte :
$context

Question : $question
Réponse :''';

    yield* llm.stream(prompt);
  }


/*
  // Stream version
  Stream<String> queryStreamWithLlm(LocalLlm llm, String question) async* {
    final results = await search(question);
    final context = results
        .map((r) => r.content.replaceFirst(EmbedTask.document.prefix, ''))
        .join('\n\n---\n\n');

    final prompt = '''Contexte :
$context

Question : $question
Réponse :''';

    yield* llm.stream(prompt);
  }
*/
  Future<void> dispose() => _index?.dispose() ?? Future.value();
}
