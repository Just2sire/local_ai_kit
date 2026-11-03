import 'package:flutter/material.dart';
import 'package:local_rag_kit/local_rag_kit.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'local_rag_kit example',
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  static const _sourceText = '''
Le RAG local combine une recherche sémantique et un modèle de génération.

Les documents sont découpés en blocs, puis indexés dans une base vectorielle.

La recherche renvoie les blocs les plus proches de la question posée.
''';

  List<String> _chunks = const [];
  String _answer = '';

  void _chunkText() {
    const chunker = TextChunker(targetChars: 80, overlapChars: 10);
    setState(() {
      _chunks = chunker.chunk(_sourceText);
    });
  }

  Future<void> _runRag() async {
    const config = RagConfig(topK: 2);
    final rag = LocalRag(config);
    final indexer = DocIndexer();

    setState(() => _answer = 'Initialisation...');
    try {
      await rag.init();
      await indexer.indexDocument(rag, docId: 'example', fullText: _sourceText);
      final results = await rag.search('Comment fonctionne le RAG local ?');
      setState(() {
        _answer = results.map((result) => result.content).join('\n\n');
      });
    } catch (error) {
      setState(() => _answer = 'Erreur : $error');
    } finally {
      await rag.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('local_rag_kit example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: _chunkText,
                child: const Text('Découper le texte'),
              ),
              OutlinedButton(
                onPressed: _runRag,
                child: const Text('Lancer le RAG'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_chunks.isNotEmpty) ...[
            Text(
              '${_chunks.length} blocs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final chunk in _chunks)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(chunk),
                ),
              ),
          ],
          if (_answer.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Résultat', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(_answer),
          ],
        ],
      ),
    );
  }
}
