
enum ChunkingStrategy {
  paragraph,
  fixedSize,
}

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
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);

    final chunks = <String>[];
    var buffer = '';

    void flush() {
      final value = buffer.trim();
      if (value.isNotEmpty) chunks.add(value);
      buffer = '';
    }

    for (final paragraph in paragraphs) {
      // Un paragraphe trop long doit être découpé.
      if (paragraph.length > targetChars) {
        flush();
        chunks.addAll(_fixedSize(paragraph));
        continue;
      }

      final candidate = buffer.isEmpty
          ? paragraph
          : '$buffer\n\n$paragraph';

      if (candidate.length <= targetChars) {
        buffer = candidate;
        continue;
      }

      final previous = buffer;
      flush();

      // Construire le nouveau chunk avec un overlap limité.
      var prefix = '';
      if (overlapChars > 0 && previous.length > overlapChars) {
        prefix = previous.substring(previous.length - overlapChars);
      } else if (overlapChars > 0) {
        prefix = previous;
      }

      final combined = prefix.isEmpty
          ? paragraph
          : '$prefix\n\n$paragraph';

      if (combined.length <= targetChars) {
        buffer = combined;
      } else {
        // Le paragraphe est conservé, mais sans overlap si nécessaire.
        buffer = paragraph;
      }
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


// enum ChunkingStrategy {
//   paragraph,  // découpe aux sauts de paragraphe (\n\n) — le plus sémantique
//   fixedSize,  // découpe à taille fixe — fallback si le texte est compact
// }

// class TextChunker {
//   const TextChunker({
//     this.targetChars = 1800,   // ≈ 400 tokens (1 token ≈ 4.5 chars)
//     this.overlapChars = 200,   // ≈ 50 tokens de chevauchement
//     this.strategy = ChunkingStrategy.paragraph,
//   });

//   final int targetChars;
//   final int overlapChars;
//   final ChunkingStrategy strategy;

//   List<String> chunk(String text) {
//     return switch (strategy) {
//       ChunkingStrategy.paragraph => _byParagraph(text),
//       ChunkingStrategy.fixedSize => _fixedSize(text),
//     };
//   }

//   // Découpe sur les sauts de paragraphe, fusionne les trop petits,
//   // re-découpe les trop grands
//   List<String> _byParagraph(String text) {
//     final rawParagraphs = text
//         .split(RegExp(r'\n{2,}'))
//         .map((p) => p.trim())
//         .where((p) => p.isNotEmpty)
//         .toList();

//     final chunks = <String>[];
//     final buffer = StringBuffer();

//     for (final para in rawParagraphs) {
//       // Paragraphe seul plus grand que la cible → le découper en fixedSize
//       if (para.length > targetChars) {
//         if (buffer.isNotEmpty) {
//           chunks.add(buffer.toString().trim());
//           buffer.clear();
//         }
//         chunks.addAll(_fixedSize(para));
//         continue;
//       }

//       // Ajouter le paragraphe au buffer si ça tient encore
//       if (buffer.length + para.length + 2 > targetChars && buffer.isNotEmpty) {
//         chunks.add(buffer.toString().trim());
//         // Overlap : on repart avec la fin du chunk précédent
//         final prev = chunks.last;
//         buffer.clear();
//         if (overlapChars > 0 && prev.length > overlapChars) {
//           buffer.write(prev.substring(prev.length - overlapChars));
//           buffer.write('\n\n');
//         }
//       }

//       buffer.write(para);
//       buffer.write('\n\n');
//     }

//     if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
//     return chunks;
//   }

//   // Découpe strictement par nombre de caractères avec overlap
//   List<String> _fixedSize(String text) {
//     final chunks = <String>[];
//     int start = 0;

//     while (start < text.length) {
//       final end = (start + targetChars).clamp(0, text.length);
//       chunks.add(text.substring(start, end).trim());
//       start += targetChars - overlapChars;
//     }

//     return chunks;
//   }
// }