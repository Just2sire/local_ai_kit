# local_ai_kit

`local_ai_kit` est un package Flutter qui regroupe les briques nécessaires à un
flux de génération augmentée par récupération (RAG) local : découpage de
documents, index vectoriel SQLite, recherche sémantique et génération avec un
modèle local. Il s’appuie sur les packages `flutter_edge_ai` et
`flutter_edge_ai_rag`.

## Fonctionnalités

- Découpage de texte par paragraphes ou en blocs de taille fixe, avec chevauchement.
- Indexation d’un document avec identifiants et métadonnées par bloc.
- **Téléchargement et extraction de documents** : sélection de fichiers (.txt, .pdf, .docx) et extraction automatique du texte.
- Stockage vectoriel SQLite dans le répertoire documents de l'application.
- Recherche sémantique avec un nombre de résultats configurable.
- Génération complète ou diffusion des réponses token par token.
- Suppression d’un bloc ou de tous les blocs d'un document.

## Prérequis

- Flutter avec un SDK Dart compatible avec la contrainte du package (`^3.13.4`).
- Les modèles requis doivent être installés et activés via `flutter_edge_ai` avant
  l’initialisation : un modèle d’embedding correspondant au profil configuré et
  un modèle de génération pour `LocalLlm`.

## Installation

Ajoutez le package à votre projet Flutter :

```sh
flutter pub add local_ai_kit
```

Si le package n'est pas publié sur pub.dev, déclarez-le plutôt comme dépendance Git ou chemin local dans `pubspec.yaml`.

## Utilisation : Téléverser et indexer des documents

Le package supporte maintenant le téléchargement et l'extraction de documents au format `.txt`, `.pdf` et `.docx`. Vous pouvez utiliser la méthode `indexDocumentFromFile` pour sélectionner un fichier ou en fournir un chemin, extraire son contenu et l'indexer automatiquement.

### Exemple : Indexer un document depuis un fichier sélectionné

```dart
import 'package:local_ai_kit/local_ai_kit.dart';
import 'package:path/path.dart' as path;

Future<void> uploadAndIndexDocument() async {
  const config = RagConfig(
    topK: 4,
    systemPrompt: 'Réponds en français en te basant sur le contexte fourni.',
  );

  final rag = LocalRag(config);
  final indexer = DocIndexer();

  await rag.init();

  try {
    // Téléverser et indexer un document (sélectionne un fichier via le sélecteur système)
    final chunksCount = await indexer.indexDocumentFromFile(
      rag: rag,
      docId: 'guide_utilisateur',
      // Laisser null ouvre le sélecteur de fichiers système;
      // fournissez un chemin directement si vous en avez déjà un
      // filePath: '/path/to/your/document.pdf',
      metadata: {'source': 'user_uploaded'},
    );

    print('$chunksCount chunks ont été indexés depuis le document.');

    // Recherche dans le document indexé
    final results = await rag.search('Comment démarrer ?');
    for (final result in results) {
      print(result.content);
    }

    // Génération avec LLM
    final llm = LocalLlm(systemPrompt: config.systemPrompt);
    await llm.init();
    final answer = await rag.queryWithLlm(llm, 'Comment démarrer ?');
    print(answer);
    await llm.dispose();
  } finally {
    await rag.dispose();
  }
}
```

### Extraction de texte depuis différents formats

Le texte est extrait automatiquement selon l'extension du fichier :

- **`.txt`** : lecture directe du contenu texte
- **`.pdf`** : extraction basique (pour une extraction avancée, envisagez d'ajouter le package `pdfx`)
- **`.docx`** : lecture directe (pour une extraction avancée, envisagez d'ajouter un package d'analyse DOCX)

Si l'extension n'est pas reconnue, une exception `FormatNotSupportedException` est lancée.

### Personnalisation du chunking

Vous pouvez contrôler la façon dont le texte est découpé en passant des paramètres au `DocIndexer` :

```dart
final indexer = DocIndexer(
  const TextChunker(
    targetChars: 2000,
    overlapChars: 300,
    strategy: ChunkingStrategy.fixedSize,
  ),
);
```

### Suppression d'un document indexé

Pour supprimer un document indexé, utilisez `DocIndexer.removeDocument` avec son identifiant et le nombre de chunks créés :

```dart
await indexer.removeDocument(rag, 'guide_utilisateur', chunksCount);
```

```sh
flutter pub add local_ai_kit
```

Si le package n’est pas publié sur pub.dev, déclarez-le plutôt comme dépendance
Git ou chemin local dans `pubspec.yaml`.

## Exemple

L’exemple suppose que les modèles nécessaires sont déjà disponibles et actifs.
`RagConfig.embedderProfileId` doit correspondre au profil d’embedding installé.

```dart
import 'package:local_ai_kit/local_ai_kit.dart';

Future<void> runLocalRag() async {
 const config = RagConfig(
  topK: 4,
  systemPrompt: 'Réponds en français en te basant sur le contexte fourni.',
 );

 final rag = LocalRag(config);
 final llm = LocalLlm(systemPrompt: config.systemPrompt);

 await rag.init();
 await llm.init();

 try {
  const indexer = DocIndexer(
   chunker: TextChunker(
    targetChars: 1800,
    overlapChars: 200,
    strategy: ChunkingStrategy.paragraph,
   ),
  );

  await indexer.indexDocument(
   rag,
   docId: 'guide',
   fullText: 'Contenu du document à indexer...',
   metadata: const {'source': 'guide_interne'},
  );

  final results = await rag.search('Comment démarrer ?');
  for (final result in results) {
   print(result.content);
  }

  final answer = await rag.queryWithLlm(llm, 'Comment démarrer ?');
  print(answer);
 } finally {
  await llm.dispose();
  await rag.dispose();
 }
}
```

`LocalRag.init()` ouvre ou crée la base `local_ai_kit.db` dans le répertoire
documents de l’application. Pour changer son nom ou le profil d’embedding,
personnalisez `RagConfig`.

### Diffuser la réponse

Pour afficher la génération au fur et à mesure :

```dart
await for (final token in rag.queryStreamWithLlm(llm, 'Résume le document.')) {
 print(token);
}
```

### Découper un texte sans l’indexer

```dart
const chunker = TextChunker(
 targetChars: 1200,
 overlapChars: 100,
 strategy: ChunkingStrategy.fixedSize,
);

final chunks = chunker.chunk('Texte à découper...');
```

`TextChunker` utilise par défaut une découpe par paragraphes, avec une cible de
1 800 caractères et un chevauchement de 200 caractères. Les tailles sont
exprimées en caractères, pas en tokens.

## API principale

- `RagConfig` configure `topK`, le prompt système, le nom de la base et le profil
  d’embedding.
- `DocChunk` représente un bloc avec un identifiant, un texte et des métadonnées
  facultatives.
- `DocIndexer.indexDocument` découpe puis indexe un document et peut signaler la
  progression avec `onProgress`.
- `LocalRag.search` renvoie les résultats de recherche ; `queryWithLlm` et
  `queryStreamWithLlm` ajoutent la génération de réponse.
- `LocalLlm.generate` renvoie la réponse complète ; `LocalLlm.stream` expose les
  tokens sous forme de flux.
- `EmbedTask` fournit les préfixes de tâche `query`, `document` et `code` utiles
  aux embeddings.

Appelez `init()` avant d’utiliser `LocalRag` ou `LocalLlm`, puis `dispose()` quand
ils ne sont plus nécessaires. Pour supprimer un document indexé, utilisez
`DocIndexer.removeDocument` avec son identifiant et le nombre de blocs créés.
