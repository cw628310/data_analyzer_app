import 'number_record.dart';

class NumberStat {
  const NumberStat({
    required this.number,
    required this.count,
    required this.probability,
  });

  final int number;
  final int count;
  final double probability;
}

class StructureProfile {
  const StructureProfile({
    required this.oddCount,
    required this.evenCount,
    required this.smallCount,
    required this.bigCount,
    required this.zoneCounts,
    required this.sum,
    required this.span,
    required this.consecutivePairs,
  });

  final int oddCount;
  final int evenCount;
  final int smallCount;
  final int bigCount;
  final List<int> zoneCounts;
  final int sum;
  final int span;
  final List<String> consecutivePairs;

  String get oddEvenText => '$oddCount:$evenCount';
  String get sizeText => '$smallCount:$bigCount';
  String get zoneText => zoneCounts.join('-');
}

class AnalysisResult {
  const AnalysisResult({
    required this.totalRecords,
    required this.redFrequency,
    required this.blueFrequency,
    required this.referenceRedStats,
    required this.referenceBlueStat,
    required this.pairCoOccurrence,
    required this.tripleCoOccurrence,
    required this.similarHitDistribution,
    required this.partnerNumbers,
    required this.coreRedNumbers,
    required this.weakRedNumbers,
    required this.structureProfile,
    required this.summaryText,
  });

  final int totalRecords;
  final Map<int, int> redFrequency;
  final Map<int, int> blueFrequency;
  final List<NumberStat> referenceRedStats;
  final NumberStat referenceBlueStat;
  final Map<String, int> pairCoOccurrence;
  final Map<String, int> tripleCoOccurrence;
  final Map<int, int> similarHitDistribution;
  final Map<int, int> partnerNumbers;
  final List<int> coreRedNumbers;
  final List<int> weakRedNumbers;
  final StructureProfile structureProfile;
  final String summaryText;
}

class GeneratedCombination {
  const GeneratedCombination({
    required this.record,
    required this.score,
    required this.reasons,
  });

  final NumberRecord record;
  final double score;
  final List<String> reasons;
}
