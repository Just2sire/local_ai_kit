enum ChunkingStrategy {
  /// Découpe aux sauts de paragraphe, en fusionnant les paragraphes courts.
  paragraph,

  /// Découpe à taille fixe, utile pour un texte sans paragraphes nets.
  fixedSize,
}

/// Découpe un texte en blocs de [targetChars] caractères au maximum.
///
/// Les tailles sont exprimées en caractères, pas en tokens.
class TextChunker {
  const TextChunker({
    this.targetChars = 1800,
    this.overlapChars = 200,
    this.strategy = ChunkingStrategy.paragraph,
  });

  final int targetChars;
  final int overlapChars;
  final ChunkingStrategy strategy;

  List<String> chunk(String text) {
    if (targetChars <= 0) {
      throw ArgumentError.value(
        targetChars,
        'targetChars',
        'Doit être supérieur à zéro.',
      );
    }

    if (overlapChars < 0 || overlapChars >= targetChars) {
      throw ArgumentError.value(
        overlapChars,
        'overlapChars',
        'Doit être compris entre 0 inclus et targetChars exclu.',
      );
    }

    final normalized = text.trim();
    if (normalized.isEmpty) return [];

    return switch (strategy) {
      ChunkingStrategy.paragraph => _byParagraph(normalized),
      ChunkingStrategy.fixedSize => _fixedSize(normalized),
    };
  }

  List<String> _byParagraph(String text) {
    final paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty);

    final chunks = <String>[];
    var buffer = '';

    void flush() {
      final value = buffer.trim();
      if (value.isNotEmpty) chunks.add(value);
      buffer = '';
    }

    for (final paragraph in paragraphs) {
      if (paragraph.length > targetChars) {
        flush();
        chunks.addAll(_fixedSize(paragraph));
        continue;
      }

      final candidate = buffer.isEmpty ? paragraph : '$buffer\n\n$paragraph';

      if (candidate.length <= targetChars) {
        buffer = candidate;
        continue;
      }

      final previous = buffer;
      flush();

      final prefix = switch (overlapChars) {
        0 => '',
        _ when previous.length <= overlapChars => previous,
        _ => previous.substring(previous.length - overlapChars),
      };

      final combined = prefix.isEmpty ? paragraph : '$prefix\n\n$paragraph';
      buffer = combined.length <= targetChars ? combined : paragraph;
    }

    flush();
    return chunks;
  }

  List<String> _fixedSize(String text) {
    final chunks = <String>[];
    final step = targetChars - overlapChars;
    var start = 0;

    while (start < text.length) {
      final end = (start + targetChars).clamp(0, text.length);
      final value = text.substring(start, end).trim();

      if (value.isNotEmpty) chunks.add(value);

      if (end == text.length) break;
      start += step;
    }

    return chunks;
  }
}
