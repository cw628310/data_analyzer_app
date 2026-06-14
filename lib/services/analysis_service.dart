import '../models/analysis_result.dart';
import '../models/number_record.dart';

class AnalysisService {
  AnalysisResult analyze({
    required List<NumberRecord> records,
    required ReferenceNumber reference,
  }) {
    final total = records.length;
    final redFrequency = _countRed(records);
    final blueFrequency = _countBlue(records);
    final pairCoOccurrence = _countCoOccurrence(records, reference.redBalls, 2);
    final tripleCoOccurrence = _countCoOccurrence(records, reference.redBalls, 3);
    final similarHitDistribution = <int, int>{for (var i = 0; i <= 6; i++) i: 0};
    final partnerNumbers = <int, int>{};

    for (final record in records) {
      final hits = record.redBalls
          .where((number) => reference.redBalls.contains(number))
          .length;
      similarHitDistribution[hits] = (similarHitDistribution[hits] ?? 0) + 1;
      if (hits >= 2) {
        for (final number in record.redBalls) {
          if (!reference.redBalls.contains(number)) {
            partnerNumbers[number] = (partnerNumbers[number] ?? 0) + 1;
          }
        }
      }
    }

    final referenceRedStats = reference.redBalls
        .map(
          (number) => NumberStat(
            number: number,
            count: redFrequency[number] ?? 0,
            probability: total == 0 ? 0 : (redFrequency[number] ?? 0) / total,
          ),
        )
        .toList();

    final referenceBlueStat = NumberStat(
      number: reference.blueBall,
      count: blueFrequency[reference.blueBall] ?? 0,
      probability: total == 0 ? 0 : (blueFrequency[reference.blueBall] ?? 0) / total,
    );

    final coreRedNumbers = _rankCoreNumbers(
      reference.redBalls,
      redFrequency,
      pairCoOccurrence,
    ).take(3).toList();
    final weakRedNumbers = _rankCoreNumbers(
      reference.redBalls,
      redFrequency,
      pairCoOccurrence,
    ).reversed.take(2).toList();
    final structure = _structure(reference.redBalls);

    return AnalysisResult(
      totalRecords: total,
      redFrequency: redFrequency,
      blueFrequency: blueFrequency,
      referenceRedStats: referenceRedStats,
      referenceBlueStat: referenceBlueStat,
      pairCoOccurrence: pairCoOccurrence,
      tripleCoOccurrence: tripleCoOccurrence,
      similarHitDistribution: similarHitDistribution,
      partnerNumbers: _sortMap(partnerNumbers),
      coreRedNumbers: coreRedNumbers,
      weakRedNumbers: weakRedNumbers,
      structureProfile: structure,
      summaryText: _summary(
        total: total,
        reference: reference,
        stats: referenceRedStats,
        pairs: pairCoOccurrence,
        distribution: similarHitDistribution,
        partners: partnerNumbers,
        structure: structure,
      ),
    );
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

  Map<String, int> _countCoOccurrence(
    List<NumberRecord> records,
    List<int> reference,
    int size,
  ) {
    final combinations = _combinations(reference, size);
    final result = <String, int>{};
    for (final combination in combinations) {
      final key = combination.map(_pad).join('+');
      result[key] = 0;
      for (final record in records) {
        if (combination.every(record.redBalls.contains)) {
          result[key] = (result[key] ?? 0) + 1;
        }
      }
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  List<List<int>> _combinations(List<int> values, int size) {
    final result = <List<int>>[];
    void build(int start, List<int> current) {
      if (current.length == size) {
        result.add(List.of(current));
        return;
      }
      for (var i = start; i < values.length; i++) {
        current.add(values[i]);
        build(i + 1, current);
        current.removeLast();
      }
    }

    build(0, []);
    return result;
  }

  List<int> _rankCoreNumbers(
    List<int> reference,
    Map<int, int> redFrequency,
    Map<String, int> pairs,
  ) {
    final scores = <int, int>{};
    for (final number in reference) {
      final numberText = _pad(number);
      final pairScore = pairs.entries
          .where((entry) => entry.key.split('+').contains(numberText))
          .fold<int>(0, (sum, entry) => sum + entry.value);
      scores[number] = (redFrequency[number] ?? 0) + pairScore;
    }
    final sorted = reference.toList()
      ..sort((a, b) => (scores[b] ?? 0).compareTo(scores[a] ?? 0));
    return sorted;
  }

  StructureProfile _structure(List<int> redBalls) {
    final sorted = redBalls.toList()..sort();
    final odd = sorted.where((n) => n.isOdd).length;
    final small = sorted.where((n) => n <= 16).length;
    final zones = [
      sorted.where((n) => n >= 1 && n <= 11).length,
      sorted.where((n) => n >= 12 && n <= 22).length,
      sorted.where((n) => n >= 23 && n <= 33).length,
    ];
    final consecutive = <String>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      if (sorted[i + 1] - sorted[i] == 1) {
        consecutive.add('${_pad(sorted[i])}+${_pad(sorted[i + 1])}');
      }
    }
    return StructureProfile(
      oddCount: odd,
      evenCount: sorted.length - odd,
      smallCount: small,
      bigCount: sorted.length - small,
      zoneCounts: zones,
      sum: sorted.fold(0, (sum, value) => sum + value),
      span: sorted.last - sorted.first,
      consecutivePairs: consecutive,
    );
  }

  String _summary({
    required int total,
    required ReferenceNumber reference,
    required List<NumberStat> stats,
    required Map<String, int> pairs,
    required Map<int, int> distribution,
    required Map<int, int> partners,
    required StructureProfile structure,
  }) {
    final hot = stats.toList()..sort((a, b) => b.count.compareTo(a.count));
    final pairTop = pairs.entries.take(3).map((e) => '${e.key} ${e.value}次').join('，');
    final partnerTop = (_sortMap(partners).entries.take(5))
        .map((e) => '${_pad(e.key)} ${e.value}次')
        .join('，');
    final highSimilar = (distribution[4] ?? 0) + (distribution[5] ?? 0) + (distribution[6] ?? 0);
    return '共分析 $total 组购买号码。参考号码 ${reference.display} 中，'
        '${hot.take(3).map((e) => _pad(e.number)).join('、')} 在文件 A 中相对更活跃；'
        '命中 4 个以上参考红球的相似组合有 $highSimilar 组。'
        '较强共现组合：${pairTop.isEmpty ? '暂无' : pairTop}。'
        '常见搭配数字：${partnerTop.isEmpty ? '暂无' : partnerTop}。'
        '参考号码结构为奇偶 ${structure.oddEvenText}、大小 ${structure.sizeText}、'
        '三区 ${structure.zoneText}、和值 ${structure.sum}、跨度 ${structure.span}。';
  }

  Map<int, int> _sortMap(Map<int, int> input) {
    return Map.fromEntries(
      input.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}
