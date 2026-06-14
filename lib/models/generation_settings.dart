enum BlueBallMode {
  keep,
  prefer,
  replace,
}

enum SimilarityLevel {
  low,
  medium,
  high,
}

class GenerationSettings {
  const GenerationSettings({
    this.count = 10,
    this.keepRedCount = 3,
    this.blueBallMode = BlueBallMode.prefer,
    this.similarityLevel = SimilarityLevel.medium,
    this.useFileAFrequency = true,
    this.useCoOccurrence = true,
    this.useFileBFrequency = true,
    this.keepStructureClose = true,
    this.excludeSameAsReference = true,
  });

  final int count;
  final int keepRedCount;
  final BlueBallMode blueBallMode;
  final SimilarityLevel similarityLevel;
  final bool useFileAFrequency;
  final bool useCoOccurrence;
  final bool useFileBFrequency;
  final bool keepStructureClose;
  final bool excludeSameAsReference;

  GenerationSettings copyWith({
    int? count,
    int? keepRedCount,
    BlueBallMode? blueBallMode,
    SimilarityLevel? similarityLevel,
    bool? useFileAFrequency,
    bool? useCoOccurrence,
    bool? useFileBFrequency,
    bool? keepStructureClose,
    bool? excludeSameAsReference,
  }) {
    return GenerationSettings(
      count: count ?? this.count,
      keepRedCount: keepRedCount ?? this.keepRedCount,
      blueBallMode: blueBallMode ?? this.blueBallMode,
      similarityLevel: similarityLevel ?? this.similarityLevel,
      useFileAFrequency: useFileAFrequency ?? this.useFileAFrequency,
      useCoOccurrence: useCoOccurrence ?? this.useCoOccurrence,
      useFileBFrequency: useFileBFrequency ?? this.useFileBFrequency,
      keepStructureClose: keepStructureClose ?? this.keepStructureClose,
      excludeSameAsReference:
          excludeSameAsReference ?? this.excludeSameAsReference,
    );
  }
}