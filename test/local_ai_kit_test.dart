import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_kit/local_ai_kit.dart';

void main() {
  group('EmbedTask', () {
    test('apply prefixes correctly', () {
      expect(
        EmbedTask.query.apply('what is flutter?'),
        'task: search query | text: what is flutter?',
      );
      expect(
        EmbedTask.document.apply('flutter is a framework'),
        'task: search result | text: flutter is a framework',
      );
      expect(
        EmbedTask.code.apply('void main() {}'),
        'task: code search | text: void main() {}',
      );
    });
  });

  group('DocChunk', () {
    test('creates chunk with metadata', () {
      const chunk = DocChunk(
        id: 'chunk_1',
        text: 'hello world',
        metadata: {'author': 'test'},
      );
      expect(chunk.id, 'chunk_1');
      expect(chunk.text, 'hello world');
      expect(chunk.metadata['author'], 'test');
    });
  });

  group('RagConfig', () {
    test('default configuration values', () {
      const config = RagConfig();
      expect(config.topK, 5);
      expect(config.dbName, 'local_ai_kit.db');
      expect(config.embedderProfileId, 'embeddinggemma-2-440m');
    });
  });

  group('TextChunker', () {
    test('splits by paragraphs', () {
      const chunker = TextChunker(targetChars: 50, overlapChars: 10);
      final text = 'Premier paragraphe court.\n\nDeuxième paragraphe un peu plus long pour tester.\n\nTroisième paragraphe.';
      final chunks = chunker.chunk(text);
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.first.contains('Premier paragraphe court.'), isTrue);
    });

    test('splits with fixedSize strategy', () {
      const chunker = TextChunker(
        targetChars: 30,
        overlapChars: 5,
        strategy: ChunkingStrategy.fixedSize,
      );
      final text = 'Un texte continu sans saut de ligne qui dépasse la taille cible.';
      final chunks = chunker.chunk(text);
      expect(chunks.length, greaterThan(1));
    });
  });

  group('DocumentExtractor', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('local_ai_kit_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extracts text from .txt file', () async {
      final txtFile = File('${tempDir.path}/test.txt');
      await txtFile.writeAsString('Bonjour, ceci est un document de test.');

      final text = await extractTextFromFile(filePath: txtFile.path);
      expect(text, 'Bonjour, ceci est un document de test.');
    });

    test('throws FileException when file does not exist', () async {
      expect(
        () => extractTextFromFile(filePath: '${tempDir.path}/not_found.txt'),
        throwsA(isA<FileException>()),
      );
    });

    test('throws FormatNotSupportedException for unknown extension', () async {
      final unknownFile = File('${tempDir.path}/sample.exe');
      await unknownFile.writeAsString('data');

      expect(
        () => extractTextFromFile(filePath: unknownFile.path),
        throwsA(isA<FormatNotSupportedException>()),
      );
    });

    test('extracts text from simulated .docx file', () async {
      final docxFile = File('${tempDir.path}/sample.docx');

      final archive = Archive();
      final xml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Titre du document Word</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Contenu du paragraphe &amp; suite.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>
''';
      final xmlBytes = utf8.encode(xml);
      archive.addFile(ArchiveFile('word/document.xml', xmlBytes.length, xmlBytes));
      final zipBytes = ZipEncoder().encode(archive)!;
      await docxFile.writeAsBytes(zipBytes);

      final extracted = await extractTextFromFile(filePath: docxFile.path);
      expect(extracted, contains('Titre du document Word'));
      expect(extracted, contains('Contenu du paragraphe & suite.'));
    });
  });
}
