class RagConfig {
  const RagConfig({
    this.topK = 5,
    this.systemPrompt = 'Tu es un assistant utile et précis.',
    this.dbName = 'local_ai_kit.db',
    this.embedderProfileId = 'embeddinggemma-2-440m',
  });

  final int topK;
  final String systemPrompt;
  final String dbName;
  final String embedderProfileId;
}