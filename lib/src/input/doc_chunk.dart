// Unité d'information à indexer
class DocChunk {
  const DocChunk({
    required this.id,
    required this.text,
    this.metadata = const {},
  });

  final String id;
  final String text;
  final Map<String, dynamic> metadata;
}
