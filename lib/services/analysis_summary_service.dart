import '../models/analysis_result.dart';
import '../models/number_record.dart';

class AnalysisSummaryService {
  String buildSideSummary({
    required String sideName,
    required List<NumberRecord> records,
    required ReferenceNumber reference,
    required AnalysisResult analysis,
  }) {
    final coreNumbers = analysis.coreRedNumbers;
    final weakNumbers = analysis.weakRedNumbers;
    final supportNumbers = reference.redBalls
        .where((number) => !coreNumbers.contains(number))
        .where((number) => !weakNumbers.contains(number))
        .toList();
    final closest = _closestRecords(
      records: records,
      reference: reference,
      limit: 2,
    );
    final blueLevel = _blueLevel(analysis.referenceBlueStat, analysis.totalRecords);

    return [
      '$sideName总体判断：${reference.display} 在当前文件中可以按“核心支撑号 + 搭配支撑号 + 弱补号码 + 蓝球判断”来理解。该结果来自购买情况数据的统计相似性，不代表中奖预测。',
      '核心支撑号码：${_formatNumbers(coreNumbers)}。这些号码在当前文件中的出现次数或共现关系相对更强，是这一边分析中更值得保留的部分。',
      '中间支撑号码：${_formatNumbers(supportNumbers)}。这些号码不是最强热号，但可以作为连接号或搭配号，用来保持组合结构。',
      '相对较弱号码：${_formatNumbers(weakNumbers)}。这些号码在当前文件中的频率或共现支撑较弱，更适合作为补充位置看待。',
      '蓝球判断：${_pad(reference.blueBall)} 在当前文件中出现 ${analysis.referenceBlueStat.count} 次，属于$blueLevel。',
      '最接近的原始组合：${closest.isEmpty ? '暂无可对比组合' : closest.join('；')}。',
      '$sideName总结：这组号码不是简单看单个数字热度，而是结合单号频率、二三数组合共现、相似原始组合和结构特征得出的分析结果。',
    ].join('\n\n');
  }

  String buildCombinedSummary({
    required List<NumberRecord> records,
    required ReferenceNumber leftReference,
    required ReferenceNumber rightReference,
    required ReferenceNumber confirmedReference,
    required AnalysisResult leftAnalysis,
    required AnalysisResult rightAnalysis,
    required AnalysisResult confirmedAnalysis,
  }) {
    final sharedReds = leftReference.redBalls
        .where((number) => rightReference.redBalls.contains(number))
        .toList()
      ..sort();
    final confirmedCore = confirmedAnalysis.coreRedNumbers;
    final confirmedWeak = confirmedAnalysis.weakRedNumbers;
    final confirmedSupport = confirmedReference.redBalls
        .where((number) => !confirmedCore.contains(number))
        .where((number) => !confirmedWeak.contains(number))
        .toList();
    final closest = _closestRecords(
      records: records,
      reference: confirmedReference,
      limit: 3,
    );
    final blueLevel =
        _blueLevel(confirmedAnalysis.referenceBlueStat, confirmedAnalysis.totalRecords);

    return [
      '综合判断：综合左边和右边第 3 步结果，并结合左右两边导入的全部文件后，系统确认出 ${confirmedReference.display} 作为综合参考组合。',
      '左右交叉号码：${_formatNumbers(sharedReds)}。这些号码同时出现在左右参考号码中，属于最直接的交叉依据；如果为空，则说明本次综合主要来自频率和搭配关系重组。',
      '综合核心支撑号码：${_formatNumbers(confirmedCore)}。这些号码在合并后的文件中频率、共现或左右分析支撑更强。',
      '综合中间支撑号码：${_formatNumbers(confirmedSupport)}。这些号码用于连接核心号，并保持综合组合的结构完整。',
      '综合相对较弱号码：${_formatNumbers(confirmedWeak)}。这些号码不是主要核心，更像补位号码。',
      '综合蓝球判断：${_pad(confirmedReference.blueBall)} 在合并文件中出现 ${confirmedAnalysis.referenceBlueStat.count} 次，属于$blueLevel。',
      '最接近的原始组合：${closest.isEmpty ? '暂无可对比组合' : closest.join('；')}。',
      '综合重组思路：先看左右共同或互补支撑，再看合并文件中的单号频率、共现关系和相似原始组合，最后形成综合确认号码。',
      '最终提示：该结果只代表购买情况数据中的统计相似性和组合思路，不代表中奖预测。',
    ].join('\n\n');
  }

  List<String> _closestRecords({
    required List<NumberRecord> records,
    required ReferenceNumber reference,
    required int limit,
  }) {
    final scored = records.map((record) {
      final hits = record.redBalls
          .where((number) => reference.redBalls.contains(number))
          .length;
      final blueHit = record.blueBall == reference.blueBall ? 1 : 0;
      return _ClosestRecord(
        record: record,
        redHits: hits,
        blueHit: blueHit,
        score: hits * 10 + blueHit,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored
        .where((item) => item.redHits > 0)
        .take(limit)
        .map(
          (item) =>
              '${item.record.display}（命中红球 ${item.redHits} 个${item.blueHit == 1 ? '，蓝球命中' : ''}）',
        )
        .toList();
  }

  String _blueLevel(NumberStat stat, int totalRecords) {
    if (totalRecords == 0) {
      return '暂无判断';
    }
    final average = totalRecords / 16;
    if (stat.count >= average * 1.25) {
      return '偏热蓝球';
    }
    if (stat.count <= average * 0.75) {
      return '偏冷蓝球';
    }
    return '中频蓝球';
  }

  String _formatNumbers(List<int> numbers) {
    if (numbers.isEmpty) {
      return '暂无明显号码';
    }
    return numbers.map(_pad).join('、');
  }

  String _pad(int value) => value.toString().padLeft(2, '0');
}

class _ClosestRecord {
  const _ClosestRecord({
    required this.record,
    required this.redHits,
    required this.blueHit,
    required this.score,
  });

  final NumberRecord record;
  final int redHits;
  final int blueHit;
  final int score;
}