import '../document/document_extractor.dart';
import '../input/doc_chunk.dart';
import '../rag/local_rag.dart';
import 'text_chunker.dart';

class DocIndexer {
  const DocIndexer({this.chunker = const TextChunker()});

  final TextChunker chunker;

  /// Découpe + indexe tout un document
  /// Retourne le nombre de chunks créés
  Future<int> indexDocument(
    LocalRag rag, {
    required String docId,
    required String fullText,
    Map<String, dynamic> metadata = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    final chunks = chunker.chunk(fullText);
    final total = chunks.length;

    for (var i = 0; i < total; i++) {
      await rag.add(
        DocChunk(
          id: '${docId}_chunk_$i',
          text: chunks[i],
          // Métadonnées enrichies : on sait à quel chunk on est
          metadata: {
            ...metadata,
            'doc_id': docId,
            'chunk_index': i,
            'chunk_total': total,
          },
        ),
      );
      onProgress?.call(i + 1, total);
    }

    return total;
  }

  /// Supprime tous les chunks d'un document
  Future<void> removeDocument(
    LocalRag rag,
    String docId,
    int totalChunks,
  ) async {
    for (var i = 0; i < totalChunks; i++) {
      await rag.remove('${docId}_chunk_$i');
    }
  }

  /// Télécharge/sélectionne et extrait le texte d'un fichier (.txt, .pdf, .docx, etc.),
  /// puis découpe et indexe le document.
  Future<int> indexDocumentFromFile({
    required LocalRag rag,
    required String docId,
    String? filePath,
    Map<String, dynamic> metadata = const {},
    ChunkingStrategy? strategy,
    int? targetChars,
    int? overlapChars,
    void Function(int done, int total)? onProgress,
  }) async {
    final actualChunker =
        (strategy != null || targetChars != null || overlapChars != null)
        ? TextChunker(
            strategy: strategy ?? chunker.strategy,
            targetChars: targetChars ?? chunker.targetChars,
            overlapChars: overlapChars ?? chunker.overlapChars,
          )
        : chunker;

    return runIndexDocumentFromFile(
      rag: rag,
      indexer: DocIndexer(chunker: actualChunker),
      docId: docId,
      filePath: filePath,
      metadata: metadata,
      onProgress: onProgress,
    );
  }
}
