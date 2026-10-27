import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import '../chunking/doc_indexer.dart';
import '../chunking/text_chunker.dart';
import '../rag/local_rag.dart';

/// Exception lancée lorsque le format de fichier n'est pas supporté.
class FormatNotSupportedException implements Exception {
  final String message;
  FormatNotSupportedException(this.message);
  @override
  String toString() => 'FormatNotSupportedException: $message';
}

/// Exception lancée lorsqu'un fichier est introuvable ou inaccessible.
class FileException implements Exception {
  final String message;
  FileException(this.message);
  @override
  String toString() => 'FileException: $message';
}

/// Extrait le texte d'un fichier sélectionné par l'utilisateur.
/// Prend en charge les formats : .txt, .pdf, .docx (ainsi que .md, .json, .csv)
Future<String> extractTextFromFile({
  required String filePath,
  TextChunker? chunker,
}) async {
  final file = File(filePath);
  final extension = path.extension(filePath).toLowerCase();

  if (!file.existsSync()) {
    throw FileException('Le fichier n\'existe pas : $filePath');
  }

  final String rawText;
  switch (extension) {
    case '.txt':
    case '.md':
    case '.csv':
    case '.json':
    case '.log':
      rawText = await _extractPlainText(file);
      break;
    case '.pdf':
      rawText = await _extractPdfText(file);
      break;
    case '.docx':
      rawText = await _extractDocxText(file);
      break;
    default:
      throw FormatNotSupportedException(
        'Format de fichier non supporté : $extension. '
        'Les formats supportés sont : .txt, .pdf, .docx',
      );
  }

  final cleanedText = rawText.trim();
  if (cleanedText.isEmpty) {
    throw FormatNotSupportedException(
      'Le fichier $filePath est vide ou aucun texte n\'a pu en être extrait.',
    );
  }

  return cleanedText;
}

/// Extrait le texte brut d'un fichier texte (.txt, .md, .csv, etc.)
Future<String> _extractPlainText(File file) async {
  try {
    return await file.readAsString(encoding: utf8);
  } catch (_) {
    return await file.readAsString(encoding: latin1);
  }
}

/// Extrait le texte d'un fichier DOCX (archive zip contenant word/document.xml).
Future<String> _extractDocxText(File file) async {
  final bytes = await file.readAsBytes();
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentFile = archive.findFile('word/document.xml');
    if (documentFile == null) {
      throw FormatNotSupportedException(
        'Fichier DOCX invalide : composant word/document.xml introuvable.',
      );
    }

    final contentBytes = documentFile.content as List<int>;
    final xml = utf8.decode(contentBytes, allowMalformed: true);

    // Extraction des paragraphes <w:p>
    final pRegex = RegExp(r'<w:p(?:\s[^>]*)?>(.*?)</w:p>', dotAll: true);
    final tRegex = RegExp(r'<w:t(?:\s[^>]*)?>(.*?)</w:t>', dotAll: true);

    final paragraphs = <String>[];
    for (final pMatch in pRegex.allMatches(xml)) {
      final pContent = pMatch.group(1) ?? '';
      final tMatches = tRegex.allMatches(pContent);
      final pText = tMatches.map((m) => _unescapeXml(m.group(1) ?? '')).join();
      if (pText.trim().isNotEmpty) {
        paragraphs.add(pText.trim());
      }
    }

    if (paragraphs.isNotEmpty) {
      return paragraphs.join('\n\n');
    }

    // Fallback : extraire tous les tags <w:t>
    final allTMatches = tRegex.allMatches(xml);
    final allText = allTMatches.map((m) => _unescapeXml(m.group(1) ?? '')).join(' ');
    if (allText.trim().isNotEmpty) {
      return allText.trim();
    }

    return '';
  } catch (e) {
    if (e is FormatNotSupportedException) rethrow;
    throw FormatNotSupportedException(
      'Impossible d\'extraire le contenu du fichier DOCX : $e',
    );
  }
}

/// Décode les entités XML basiques
String _unescapeXml(String text) {
  return text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// Extrait le texte d'un fichier PDF en décompressant les flux et analysant les blocs texte.
Future<String> _extractPdfText(File file) async {
  final bytes = await file.readAsBytes();
  try {
    final text = _extractTextFromPdfBytes(bytes);
    if (text.trim().isNotEmpty) {
      return text.trim();
    }
  } catch (_) {}

  // Fallback : extraction de chaînes ASCII lisibles
  final fallback = _extractAsciiFallback(bytes);
  if (fallback.trim().isNotEmpty) {
    return fallback.trim();
  }

  throw FormatNotSupportedException(
    'Extraction PDF : aucun texte lisible n\'a pu être extrait. '
    'Le document peut être numérisé (image sans OCR) ou protégé.',
  );
}

/// Parcourt les streams du PDF et extrait les instructions texte Tj et TJ
String _extractTextFromPdfBytes(Uint8List bytes) {
  final buffer = StringBuffer();
  final latin1Str = latin1.decode(bytes);

  // Recherche de tous les streams : stream ... endstream
  final streamRegex = RegExp(r'stream\r?\n', dotAll: true);
  final endStreamRegex = RegExp(r'\r?\nendstream', dotAll: true);

  int searchStart = 0;
  while (true) {
    final streamMatch = streamRegex.firstMatch(latin1Str.substring(searchStart));
    if (streamMatch == null) break;

    final streamStartPos = searchStart + streamMatch.end;
    final endMatch = endStreamRegex.firstMatch(latin1Str.substring(streamStartPos));
    if (endMatch == null) break;

    final streamEndPos = streamStartPos + endMatch.start;

    // Vérifier les 200 caractères précédents pour voir si /FlateDecode est mentionné
    final headerStart = (streamStartPos - 300).clamp(0, streamStartPos);
    final headerSnippet = latin1Str.substring(headerStart, streamStartPos);
    final isFlate = headerSnippet.contains('/FlateDecode');

    final rawStreamBytes = bytes.sublist(streamStartPos, streamEndPos);
    String streamText = '';

    if (isFlate) {
      try {
        final decompressed = zlib.decode(rawStreamBytes);
        streamText = utf8.decode(decompressed, allowMalformed: true);
      } catch (_) {
        try {
          final decompressed = zlib.decode(rawStreamBytes);
          streamText = latin1.decode(decompressed);
        } catch (_) {
          // ignore stream decoding error
        }
      }
    } else {
      streamText = latin1.decode(rawStreamBytes);
    }

    if (streamText.isNotEmpty) {
      final extracted = _parsePdfStreamText(streamText);
      if (extracted.trim().isNotEmpty) {
        buffer.writeln(extracted.trim());
        buffer.writeln();
      }
    }

    searchStart = streamEndPos + endMatch.end;
  }

  return buffer.toString();
}

/// Analyse un flux PDF texte pour en extraire les textes des blocs BT ... ET
String _parsePdfStreamText(String streamContent) {
  final buffer = StringBuffer();

  // Blocs de texte BT ... ET
  final btEtRegex = RegExp(r'BT\s*(.*?)\s*ET', dotAll: true);
  final btMatches = btEtRegex.allMatches(streamContent);

  final tjRegex = RegExp(r'\((.*?)\)\s*Tj', dotAll: true);
  final tjArrayRegex = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
  final stringRegex = RegExp(r'\((.*?)\)', dotAll: true);

  for (final block in btMatches) {
    final blockContent = block.group(1) ?? '';

    // Extraire les Tj simples
    for (final m in tjRegex.allMatches(blockContent)) {
      final t = _cleanPdfString(m.group(1) ?? '');
      if (t.isNotEmpty) buffer.write('$t ');
    }

    // Extraire les tableaux TJ
    for (final m in tjArrayRegex.allMatches(blockContent)) {
      final arrayContent = m.group(1) ?? '';
      for (final sm in stringRegex.allMatches(arrayContent)) {
        final t = _cleanPdfString(sm.group(1) ?? '');
        if (t.isNotEmpty) buffer.write(t);
      }
      buffer.write(' ');
    }

    buffer.writeln();
  }

  return buffer.toString();
}

String _cleanPdfString(String str) {
  return str
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .trim();
}

/// Fallback pour extraire des séquences de caractères imprimables
String _extractAsciiFallback(Uint8List bytes) {
  final buffer = StringBuffer();
  int currentRun = 0;
  final runBuffer = StringBuffer();

  for (final b in bytes) {
    // Caractères imprimables ASCII + accents latins fréquents
    if ((b >= 32 && b <= 126) || b == 10 || b == 13 || (b >= 192 && b <= 255)) {
      runBuffer.writeCharCode(b);
      currentRun++;
    } else {
      if (currentRun >= 8) {
        final line = runBuffer.toString().trim();
        // Filtrer les chaînes internes PDF
        if (line.isNotEmpty &&
            !line.startsWith('/') &&
            !line.startsWith('%PDF') &&
            !line.contains('endobj') &&
            !line.contains('obj<<')) {
          buffer.writeln(line);
        }
      }
      currentRun = 0;
      runBuffer.clear();
    }
  }

  return buffer.toString();
}

/// Télécharge et extrait le texte d'un fichier choisi par l'utilisateur ou via filePath.
/// Découpe le texte puis indexe les chunks dans [LocalRag] via [DocIndexer].
/// Retourne le nombre total de chunks créés.
Future<int> indexDocumentFromFile({
  required LocalRag rag,
  DocIndexer? indexer,
  required String docId,
  String? filePath,
  Map<String, dynamic> metadata = const {},
  ChunkingStrategy strategy = ChunkingStrategy.paragraph,
  int targetChars = 1800,
  int overlapChars = 200,
  void Function(int done, int total)? onProgress,
}) async {
  final actualIndexer = indexer ??
      DocIndexer(
        chunker: TextChunker(
          targetChars: targetChars,
          overlapChars: overlapChars,
          strategy: strategy,
        ),
      );

  return runIndexDocumentFromFile(
    rag: rag,
    indexer: actualIndexer,
    docId: docId,
    filePath: filePath,
    metadata: metadata,
    onProgress: onProgress,
  );
}

/// Exécute la sélection, l'extraction et l'indexation avec une instance spécifique de [DocIndexer].
Future<int> runIndexDocumentFromFile({
  required LocalRag rag,
  required DocIndexer indexer,
  required String docId,
  required String? filePath,
  Map<String, dynamic> metadata = const {},
  void Function(int done, int total)? onProgress,
}) async {
  String selectedPath;

  if (filePath == null || filePath.isEmpty) {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'docx', 'md', 'json', 'csv'],
    );

    if (file == null || file.path == null) {
      throw FormatNotSupportedException('Aucun fichier sélectionné.');
    }
    selectedPath = file.path!;
  } else {
    selectedPath = filePath;
  }

  final extractedText = await extractTextFromFile(filePath: selectedPath);
  final ext = path.extension(selectedPath).replaceAll('.', '').toLowerCase();
  final fileName = path.basename(selectedPath);

  final enrichedMetadata = {
    'file_name': fileName,
    'file_type': ext,
    'source': ext,
    ...metadata,
  };

  return await indexer.indexDocument(
    rag,
    docId: docId,
    fullText: extractedText,
    metadata: enrichedMetadata,
    onProgress: onProgress,
  );
}
