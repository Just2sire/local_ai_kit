// Préfixes de tâche attendus par EmbeddingGemma 2
enum EmbedTask {
  query('task: search query | text: '),
  document('task: search result | text: '),
  code('task: code search | text: ');

  const EmbedTask(this.prefix);
  final String prefix;

  String apply(String text) => '$prefix$text';
}