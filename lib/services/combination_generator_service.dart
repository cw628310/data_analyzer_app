import 'dart:math';

import '../models/analysis_result.dart';
import '../models/generation_settings.dart';
import '../models/number_record.dart';

class CombinationGeneratorService {
  List<GeneratedCombination> generate({
    required ReferenceNumber reference,
    required AnalysisResult analysis,
    required List<NumberRecord> fileBRecords,
    required GenerationSettings settings,
  }) {
    if (fileBRecords.isEmpty) {
      return [];
    }

    final bRedFrequency = _countRed(fileBRecords);
    final bBlueFrequency = _countBlue(fileBRecords);
    final bPartnerNumbers = _partnerNumbersFromB(reference, fileBRecords);
    final candidates = <int>{
      ...analysis.partnerNumbers.keys.take(12),
      ...bPartnerNumbers.keys.take(12),
      ...bRedFrequency.keys.take(12),
    }.where((n) => n >= 1 && n <= 33).toList()
      ..sort();

    final blueCandidates = <int>[
      if (settings.blueBallMode != BlueBallMode.replace) reference.blueBall,
      ...bBlueFrequency.keys.take(6),
      ...analysis.blueFrequency.keys.take(6),
    ].where((n) => n >= 1 && n <= 16).toSet().toList();

    final generated = <GeneratedCombination>[];
    final seen = <String>{};
    final targetAttempts = max(300, settings.count * 80);

    for (var attempt = 0; attempt < targetAttempts; attempt++) {
      final redBalls = _buildRedBalls(
        reference: reference,
        analysis: analysis,
        candidates: candidates,
        bRedFrequency: bRedFrequency,
        settings: settings,
        attempt: attempt,
      );
      if (redBalls.length != 6) {
        continue;
      }
      redBalls.sort();
      final blueBall = _pickBlue(
        reference: reference,
        blueCandidates: blueCandidates,
        bBlueFrequency: bBlueFrequency,
        settings: settings,
        attempt: attempt,
      );
      final record = NumberRecord(
        redBalls: redBalls,
        blueBall: blueBall,
        sourceFileName: '生成结果',
      );

      final key = record.display;
      if (seen.contains(key)) {
        continue;
      }
      if (settings.excludeSameAsReference && key == reference.display) {
        continue;
      }
      final keepCount = redBalls.where(reference.redBalls.contains).length;
      if (keepCount != settings.keepRedCount) {
        continue;
      }

      final score = _score(
        redBalls: redBalls,
        blueBall: blueBall,
        reference: reference,
        analysis: analysis,
        bRedFrequency: bRedFrequency,
        bBlueFrequency: bBlueFrequency,
        settings: settings,
      );
      final reasons = _reasons(
        redBalls: redBalls,
        blueBall: blueBall,
        reference: reference,
        analysis: analysis,
        bRedFrequency: bRedFrequency,
        bPartnerNumbers: bPartnerNumbers,
      );

      seen.add(key);
      generated.add(
        GeneratedCombination(record: record, score: score, reasons: reasons),
      );
    }

    generated.sort((a, b) => b.score.compareTo(a.score));
    return generated.take(settings.count).toList();
  }

  List<int> _buildRedBalls({
    required ReferenceNumber reference,
    required AnalysisResult analysis,
    required List<int> candidates,
    required Map<int, int> bRedFrequency,
    required GenerationSettings settings,
    required int attempt,
  }) {
    final keepTarget = settings.keepRedCount.clamp(0, 5).toInt();
    final kept = _rankReferenceForKeep(reference, analysis)
        .skip(attempt % max(1, 6 - keepTarget + 1))
        .take(keepTarget)
        .toSet();

    final result = <int>{...kept};
    final rankedCandidates = candidates.toList()
      ..sort((a, b) {
        final scoreA = (analysis.partnerNumbers[a] ?? 0) +
            (bRedFrequency[a] ?? 0) +
            (analysis.redFrequency[a] ?? 0);
        final scoreB = (analysis.partnerNumbers[b] ?? 0) +
            (bRedFrequency[b] ?? 0) +
            (analysis.redFrequency[b] ?? 0);
        return scoreB.compareTo(scoreA);
      });

    for (final number in rankedCandidates.skip(attempt % 5)) {
      if (result.length == 6) {
        break;
      }
      if (reference.redBalls.contains(number)) {
        continue;
      }
      result.add(number);
    }

    var fill = 1;
    while (result.length < 6 && fill <= 33) {
      if (!reference.redBalls.contains(fill)) {
        result.add(fill);
      }
      fill++;
    }

    return result.toList();
  }

  List<int> _rankReferenceForKeep(
    ReferenceNumber reference,
    AnalysisResult analysis,
  ) {
    final values = reference.redBalls.toList();
    values.sort((a, b) {
      final scoreA = (analysis.redFrequency[a] ?? 0) +
          analysis.pairCoOccurrence.entries
              .where((entry) => entry.key.split('+').contains(_pad(a)))
              .fold<int>(0, (sum, entry) => sum + entry.value);
      final scoreB = (analysis.redFrequency[b] ?? 0) +
          analysis.pairCoOccurrence.entries
              .where((entry) => entry.key.split('+').contains(_pad(b)))
              .fold<int>(0, (sum, entry) => sum + entry.value);
      return scoreB.compareTo(scoreA);
    });
    return values;
  }

  int _pickBlue({
    required ReferenceNumber reference,
    required List<int> blueCandidates,
    required Map<int, int> bBlueFrequency,
    required GenerationSettings settings,
    required int attempt,
  }) {
    if (settings.blueBallMode == BlueBallMode.keep) {
      return reference.blueBall;
    }
    if (settings.blueBallMode == BlueBallMode.prefer && attempt % 2 == 0) {
      return reference.blueBall;
    }
    if (blueCandidates.isEmpty) {
      return reference.blueBall;
    }
    blueCandidates.sort(
      (a, b) => (bBlueFrequency[b] ?? 0).compareTo(bBlueFrequency[a] ?? 0),
    );
    return blueCandidates[attempt % blueCandidates.length];
  }

  double _score({
    required List<int> redBalls,
    required int blueBall,
    required ReferenceNumber reference,
    required AnalysisResult analysis,
    required Map<int, int> bRedFrequency,
    required Map<int, int> bBlueFrequency,
    required GenerationSettings settings,
  }) {
    final keepCount = redBalls.where(reference.redBalls.contains).length;
    final coreKeep = redBalls.where(analysis.coreRedNumbers.contains).length;
    final bSupport = redBalls.fold<int>(0, (sum, n) => sum + (bRedFrequency[n] ?? 0));
    final aPartnerSupport =
        redBalls.fold<int>(0, (sum, n) => sum + (analysis.partnerNumbers[n] ?? 0));
    final structureScore = settings.keepStructureClose
        ? _structureSimilarity(redBalls, analysis.structureProfile)
        : 0.0;
    final blueScore = blueBall == reference.blueBall
        ? 10.0
        : min(8, (bBlueFrequency[blueBall] ?? 0)).toDouble();

    return keepCount * 20 +
        coreKeep * 10 +
        bSupport * 0.8 +
        aPartnerSupport * 0.6 +
        structureScore * 20 +
        blueScore;
  }

  double _structureSimilarity(List<int> redBalls, StructureProfile target) {
    final sorted = redBalls.toList()..sort();
    final odd = sorted.where((n) => n.isOdd).length;
    final small = sorted.where((n) => n <= 16).length;
    final zones = [
      sorted.where((n) => n >= 1 && n <= 11).length,
      sorted.where((n) => n >= 12 && n <= 22).length,
      sorted.where((n) => n >= 23 && n <= 33).length,
    ];
    final sum = sorted.fold(0, (value, element) => value + element);
    final span = sorted.last - sorted.first;
    final oddScore = 1 - (odd - target.oddCount).abs() / 6;
    final sizeScore = 1 - (small - target.smallCount).abs() / 6;
    final zoneScore = 1 -
        List.generate(3, (i) => (zones[i] - target.zoneCounts[i]).abs())
                .fold<int>(0, (a, b) => a + b) /
            12;
    final sumScore = 1 - min(1, (sum - target.sum).abs() / 60);
    final spanScore = 1 - min(1, (span - target.span).abs() / 30);
    return (oddScore + sizeScore + zoneScore + sumScore + spanScore) / 5;
  }

  List<String> _reasons({
    required List<int> redBalls,
    required int blueBall,
    required ReferenceNumber reference,
    required AnalysisResult analysis,
    required Map<int, int> bRedFrequency,
    required Map<int, int> bPartnerNumbers,
  }) {
    final kept = redBalls.where(reference.redBalls.contains).toList();
    final replaced = redBalls.where((n) => !reference.redBalls.contains(n)).toList();
    final reasons = <String>[];
    reasons.add('保留了参考号码中的 ${kept.map(_pad).join('、')}，保留数量为 ${kept.length} 个。');
    final coreKept = kept.where(analysis.coreRedNumbers.contains).toList();
    if (coreKept.isNotEmpty) {
      reasons.add('${coreKept.map(_pad).join('、')} 在文件 A 中出现次数或共现关系较强。');
    }
    if (replaced.isNotEmpty) {
      final details = replaced.map((n) {
        final bCount = bRedFrequency[n] ?? 0;
        final partnerCount = bPartnerNumbers[n] ?? analysis.partnerNumbers[n] ?? 0;
        return '${_pad(n)}（文件B出现 $bCount 次，相似搭配 $partnerCount 次）';
      }).join('、');
      reasons.add('$details 用于补充参考号码中的弱关联位置。');
    }
    if (blueBall == reference.blueBall) {
      reasons.add('蓝球 ${_pad(blueBall)} 与参考号码一致。');
    } else {
      reasons.add('蓝球 ${_pad(blueBall)} 来自文件 B 或文件 A 的蓝球分布。');
    }
    reasons.add('整体按参考号码的保留数量、文件 A 规律、文件 B 数据支持和结构接近度综合排序。');
    return reasons;
  }

  Map<int, int> _countRed(List<NumberRecord> records) {
    final result = <int, int>{};
    for (final record in records) {
      for (final number in record.redBalls) {
        result[number] = (result[number] ?? 0) + 1;
      }
    }
    return _sortMap(result);
  }

  Map<int, int> _countBlue(List<NumberRecord> records) {
    final result = <int, int>{};
    for (final record in records) {
      result[record.blueBall] = (result[record.blueBall] ?? 0) + 1;
    }
    return _sortMap(result);
  }

  Map<int, int> _partnerNumbersFromB(
    ReferenceNumber reference,
    List<NumberRecord> records,
  ) {
    final result = <int, int>{};
    for (final record in records) {
      final hits = record.redBalls.where(reference.redBalls.contains).length;
      if (hits >= 2) {
        for (final number in record.redBalls) {
          if (!reference.redBalls.contains(number)) {
            result[number] = (result[number] ?? 0) + 1;
          }
        }
      }
    }
    return _sortMap(result);
  }

  Map<int, int> _sortMap(Map<int, int> input) {
    return Map.fromEntries(
      input.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}