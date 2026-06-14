import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/analysis_result.dart';
import '../models/generation_settings.dart';
import '../models/number_record.dart';
import '../services/analysis_service.dart';
import '../services/analysis_summary_service.dart';
import '../services/combination_generator_service.dart';
import '../services/number_parser_service.dart';
import '../services/remote_learning_service.dart';

enum _FileSlot {
  left,
  right,
  generation,
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _parser = NumberParserService();
  final _analysisService = AnalysisService();
  final _summaryService = AnalysisSummaryService();
  final _remoteLearningService = RemoteLearningService();
  final _generator = CombinationGeneratorService();
  final _leftReferenceController =
      TextEditingController(text: '01.02.03.04.05.06+09');
  final _rightReferenceController =
      TextEditingController(text: '07.08.09.10.11.12+10');

  List<ParsedFileResult> _leftFileResults = [];
  List<ParsedFileResult> _rightFileResults = [];
  List<ParsedFileResult> _generationFileResults = [];
  ReferenceNumber? _leftReference;
  ReferenceNumber? _rightReference;
  ReferenceNumber? _confirmedReference;
  AnalysisResult? _leftAnalysis;
  AnalysisResult? _rightAnalysis;
  AnalysisResult? _confirmedAnalysis;
  String? _leftSummaryText;
  String? _rightSummaryText;
  String? _confirmedSummaryText;
  GenerationSettings _settings = const GenerationSettings();
  List<GeneratedCombination> _generated = [];
  bool _busy = false;

  List<NumberRecord> get _leftRecords =>
      _leftFileResults.expand((result) => result.records).toList();
  List<NumberRecord> get _rightRecords =>
      _rightFileResults.expand((result) => result.records).toList();
  List<NumberRecord> get _combinedAnalysisRecords => [
        ..._leftRecords,
        ..._rightRecords,
      ];
  List<NumberRecord> get _generationRecords =>
      _generationFileResults.expand((result) => result.records).toList();

  @override
  void dispose() {
    _leftReferenceController.dispose();
    _rightReferenceController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles(_FileSlot slot) async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (result == null) {
        return;
      }
      final parsedResults = <ParsedFileResult>[];
      for (final file in result.files) {
        if (file.path == null) {
          parsedResults.add(
            ParsedFileResult(
              fileName: file.name,
              records: const [],
              errors: const ['无法读取该文件路径'],
            ),
          );
          continue;
        }
        final content = await File(file.path!).readAsString();
        parsedResults.add(_parser.parseFile(fileName: file.name, content: content));
      }
      setState(() {
        switch (slot) {
          case _FileSlot.left:
            _leftFileResults = parsedResults;
            _leftAnalysis = null;
            _leftReference = null;
            _leftSummaryText = null;
            _confirmedAnalysis = null;
            _confirmedReference = null;
            _confirmedSummaryText = null;
            _generated = [];
          case _FileSlot.right:
            _rightFileResults = parsedResults;
            _rightAnalysis = null;
            _rightReference = null;
            _rightSummaryText = null;
            _confirmedAnalysis = null;
            _confirmedReference = null;
            _confirmedSummaryText = null;
            _generated = [];
          case _FileSlot.generation:
            _generationFileResults = parsedResults;
            _generated = [];
        }
      });
    } catch (error) {
      _showMessage('文件读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _runSideAnalysis({required bool isLeft}) {
    final records = isLeft ? _leftRecords : _rightRecords;
    final controller =
        isLeft ? _leftReferenceController : _rightReferenceController;
    final sideName = isLeft ? '左边' : '右边';

    if (records.isEmpty) {
      _showMessage('请先导入$sideName分析文件');
      return;
    }
    try {
      final reference = _parser.parseReference(controller.text);
      final analysis = _analysisService.analyze(
        records: records,
        reference: reference,
      );
      setState(() {
        if (isLeft) {
          _leftReference = reference;
          _leftAnalysis = analysis;
          _leftSummaryText = _summaryService.buildSideSummary(
            sideName: '左边',
            records: records,
            reference: reference,
            analysis: analysis,
          );
          _learnSideSummary(isLeft: true);
        } else {
          _rightReference = reference;
          _rightAnalysis = analysis;
          _rightSummaryText = _summaryService.buildSideSummary(
            sideName: '右边',
            records: records,
            reference: reference,
            analysis: analysis,
          );
          _learnSideSummary(isLeft: false);
        }
        _confirmedAnalysis = null;
        _confirmedReference = null;
        _confirmedSummaryText = null;
        _generated = [];
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  void _runConfirmedAnalysis() {
    if (_leftAnalysis == null ||
        _rightAnalysis == null ||
        _leftReference == null ||
        _rightReference == null) {
      _showMessage('请先完成左边和右边的步骤 3 分析');
      return;
    }
    if (_combinedAnalysisRecords.isEmpty) {
      _showMessage('左右两边分析文件为空，无法综合确认');
      return;
    }

    final confirmedReference = _buildConfirmedReference();
    final confirmedAnalysis = _analysisService.analyze(
      records: _combinedAnalysisRecords,
      reference: confirmedReference,
    );

    setState(() {
      _confirmedReference = confirmedReference;
      _confirmedAnalysis = confirmedAnalysis;
      _confirmedSummaryText = _summaryService.buildCombinedSummary(
        records: _combinedAnalysisRecords,
        leftReference: _leftReference!,
        rightReference: _rightReference!,
        confirmedReference: confirmedReference,
        leftAnalysis: _leftAnalysis!,
        rightAnalysis: _rightAnalysis!,
        confirmedAnalysis: confirmedAnalysis,
      );
      _generated = [];
    });
    _learnConfirmedSummary();
  }

  Future<void> _learnSideSummary({required bool isLeft}) async {
    final reference = isLeft ? _leftReference : _rightReference;
    final summary = isLeft ? _leftSummaryText : _rightSummaryText;
    if (reference == null || summary == null || summary.isEmpty) {
      return;
    }

    final optimized = await _remoteLearningService.learnSideSummary(
      sideName: isLeft ? '左边' : '右边',
      reference: reference.display,
      summary: summary,
    );

    if (!mounted || optimized == summary) {
      return;
    }

    setState(() {
      if (isLeft) {
        _leftSummaryText = optimized;
      } else {
        _rightSummaryText = optimized;
      }
    });
  }

  Future<void> _learnConfirmedSummary() async {
    if (_confirmedReference == null ||
        _leftReference == null ||
        _rightReference == null ||
        _confirmedSummaryText == null ||
        _confirmedSummaryText!.isEmpty) {
      return;
    }

    final currentSummary = _confirmedSummaryText!;
    final optimized = await _remoteLearningService.learnCombinedSummary(
      reference: _confirmedReference!.display,
      leftReference: _leftReference!.display,
      rightReference: _rightReference!.display,
      summary: currentSummary,
    );

    if (!mounted || optimized == currentSummary) {
      return;
    }

    setState(() {
      _confirmedSummaryText = optimized;
    });
  }

  ReferenceNumber _buildConfirmedReference() {
    final left = _leftReference!;
    final right = _rightReference!;
    final combinedRedFrequency = _countRed(_combinedAnalysisRecords);
    final combinedBlueFrequency = _countBlue(_combinedAnalysisRecords);
    final allReferenceReds = <int>{...left.redBalls, ...right.redBalls};

    final scored = <int, int>{};
    for (final number in allReferenceReds) {
      var score = combinedRedFrequency[number] ?? 0;
      if (left.redBalls.contains(number) && right.redBalls.contains(number)) {
        score += 20;
      }
      if (_leftAnalysis?.coreRedNumbers.contains(number) ?? false) {
        score += 10;
      }
      if (_rightAnalysis?.coreRedNumbers.contains(number) ?? false) {
        score += 10;
      }
      scored[number] = score;
    }

    for (final entry in combinedRedFrequency.entries.take(12)) {
      scored.putIfAbsent(entry.key, () => entry.value);
    }

    final redBalls = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final selectedReds = redBalls.take(6).map((entry) => entry.key).toList()
      ..sort();

    final leftBlueCount = combinedBlueFrequency[left.blueBall] ?? 0;
    final rightBlueCount = combinedBlueFrequency[right.blueBall] ?? 0;
    final blueBall = rightBlueCount > leftBlueCount ? right.blueBall : left.blueBall;

    return ReferenceNumber(redBalls: selectedReds, blueBall: blueBall);
  }

  void _generate() {
    if (_confirmedAnalysis == null || _confirmedReference == null) {
      _showMessage('请先完成步骤 4 综合确认');
      return;
    }
    if (_generationRecords.isEmpty) {
      _showMessage('请先导入组合文件');
      return;
    }
    final generated = _generator.generate(
      reference: _confirmedReference!,
      analysis: _confirmedAnalysis!,
      fileBRecords: _generationRecords,
      settings: _settings,
    );
    setState(() => _generated = generated);
    if (generated.isEmpty) {
      _showMessage('没有生成符合当前条件的组合，请调整相似度或保留参考红球数量');
    }
  }

  Future<void> _copyResults() async {
    if (_generated.isEmpty) {
      _showMessage('暂无可复制的结果');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _resultText()));
    _showMessage('已复制全部结果');
  }

  Future<void> _exportResults() async {
    if (_generated.isEmpty) {
      _showMessage('暂无可导出的结果');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/数据分析仪结果_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    await file.writeAsString(_resultText());
    await SharePlus.instance.share(
      ShareParams(
        text: '数据分析仪生成结果',
        files: [XFile(file.path)],
      ),
    );
  }

  String _resultText() {
    final buffer = StringBuffer()
      ..writeln('数据分析仪生成结果')
      ..writeln('综合确认号码：${_confirmedReference?.display ?? ''}')
      ..writeln('左边参考号码：${_leftReference?.display ?? ''}')
      ..writeln('右边参考号码：${_rightReference?.display ?? ''}')
      ..writeln();
    for (var i = 0; i < _generated.length; i++) {
      final item = _generated[i];
      buffer
        ..writeln('推荐组合 ${i + 1}：${item.record.display}')
        ..writeln('原因：');
      for (final reason in item.reasons) {
        buffer.writeln('- $reason');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据分析仪'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _introCard(),
              _mirrorInputCard(),
              _sideAnalysisResultCard(),
              _confirmedAnalysisCard(),
              _settingsCard(stepTitle: '第五步：设置生成条件'),
              _importCard(
                title: '第六步：导入组合文件',
                description: '可选择一个或多个 TXT 文件，用于生成相似风格的新组合。',
                results: _generationFileResults,
                onPressed: () => _pickFiles(_FileSlot.generation),
              ),
              _generateCard(),
              const SizedBox(height: 32),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black.withAlpha(46),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _introCard() {
    return _sectionCard(
      title: '双侧离线购买数据分析',
      child: const Text(
        '左边和右边各导入一组购买情况文件并输入一组参考号码，系统先分别分析，再把左右文件和左右结果综合确认，最后用综合确认结果生成相似组合。全程离线，不需要网络。',
      ),
    );
  }

  Widget _importCard({
    required String title,
    required String description,
    required List<ParsedFileResult> results,
    required VoidCallback onPressed,
  }) {
    final total = results.fold<int>(0, (sum, item) => sum + item.records.length);
    final errorCount = results.fold<int>(0, (sum, item) => sum + item.errors.length);
    return _sectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.upload_file),
            label: const Text('选择 TXT 文件'),
          ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('已导入 ${results.length} 个文件，合计识别 $total 组，异常 $errorCount 条。'),
            const SizedBox(height: 8),
            ...results.map(
              (item) => Text(
                '${item.fileName}：识别 ${item.records.length} 组'
                '${item.errors.isEmpty ? '' : '，异常 ${item.errors.length} 条'}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mirrorInputCard() {
    return _sectionCard(
      title: '步骤 1-2：左右两边导入文件并输入参考号码',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: _sideInputPanel(
                title: '左边一组',
                description: '左边分析文件，可选择一个或多个 TXT 文件。',
                controller: _leftReferenceController,
                results: _leftFileResults,
                onPickFiles: () => _pickFiles(_FileSlot.left),
                onAnalyze: () => _runSideAnalysis(isLeft: true),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 360,
              child: _sideInputPanel(
                title: '右边一组',
                description: '右边分析文件，可选择一个或多个 TXT 文件。',
                controller: _rightReferenceController,
                results: _rightFileResults,
                onPickFiles: () => _pickFiles(_FileSlot.right),
                onAnalyze: () => _runSideAnalysis(isLeft: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideInputPanel({
    required String title,
    required String description,
    required TextEditingController controller,
    required List<ParsedFileResult> results,
    required VoidCallback onPickFiles,
    required VoidCallback onAnalyze,
  }) {
    final total = results.fold<int>(0, (sum, item) => sum + item.records.length);
    final errorCount =
        results.fold<int>(0, (sum, item) => sum + item.errors.length);

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onPickFiles,
              icon: const Icon(Icons.upload_file),
              label: const Text('选择 TXT 文件'),
            ),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('已导入 ${results.length} 个文件，识别 $total 组，异常 $errorCount 条。'),
            ],
            const SizedBox(height: 12),
            const Text('参考号码格式：01.02.03.04.05.06+09'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '参考号码',
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAnalyze,
              icon: const Icon(Icons.analytics),
              label: const Text('分析这一边'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideAnalysisResultCard() {
    if (_leftAnalysis == null && _rightAnalysis == null) {
      return _sectionCard(
        title: '第三步：左右两边分别分析结果',
        child: const Text('完成左边或右边分析后，这里会显示对应的规律分析结果。'),
      );
    }

    return _sectionCard(
      title: '第三步：左右两边分别分析结果',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: _analysisPanel(
                title: '左边分析结果',
                reference: _leftReference,
                analysis: _leftAnalysis,
                summaryText: _leftSummaryText,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 360,
              child: _analysisPanel(
                title: '右边分析结果',
                reference: _rightReference,
                analysis: _rightAnalysis,
                summaryText: _rightSummaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmedAnalysisCard() {
    return _sectionCard(
      title: '第四步：综合左右结果再度分析确认',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '系统会综合左边步骤 3、右边步骤 3 的分析结果，并结合左右两边步骤 1 导入的全部文件，再生成一组综合确认号码和综合分析结果。后续生成组合会使用这里的综合确认结果。',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runConfirmedAnalysis,
            icon: const Icon(Icons.fact_check),
            label: const Text('综合确认'),
          ),
          if (_confirmedAnalysis != null && _confirmedReference != null) ...[
            const SizedBox(height: 16),
            _analysisPanel(
              title: '综合确认结果：${_confirmedReference!.display}',
              reference: _confirmedReference,
              analysis: _confirmedAnalysis,
              summaryText: _confirmedSummaryText,
            ),
          ],
        ],
      ),
    );
  }

  Widget _analysisPanel({
    required String title,
    required ReferenceNumber? reference,
    required AnalysisResult? analysis,
    String? summaryText,
  }) {
    if (analysis == null || reference == null) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('暂未分析'),
        ),
      );
    }

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('参考号码：${reference.display}'),
            const SizedBox(height: 8),
            if (summaryText != null && summaryText.isNotEmpty) ...[
              _summaryBox(summaryText),
            ] else ...[
              Text(analysis.summaryText),
            ],
            const SizedBox(height: 16),
            _subTitle('参考红球次数'),
            _statWrap(
              analysis.referenceRedStats.map(
                (stat) =>
                    '${_pad(stat.number)}：${stat.count}次，${_percent(stat.probability)}',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '蓝球 ${_pad(analysis.referenceBlueStat.number)}：'
              '${analysis.referenceBlueStat.count}次，'
              '${_percent(analysis.referenceBlueStat.probability)}',
            ),
            const SizedBox(height: 12),
            _subTitle('高频共现'),
            _statWrap(
              analysis.pairCoOccurrence.entries
                  .take(6)
                  .map((entry) => '${entry.key}：${entry.value}次'),
            ),
            const SizedBox(height: 12),
            _subTitle('常见搭配数字'),
            _statWrap(
              analysis.partnerNumbers.entries
                  .take(10)
                  .map((entry) => '${_pad(entry.key)}：${entry.value}次'),
            ),
            const SizedBox(height: 12),
            _subTitle('结构'),
            Text(
              '奇偶 ${analysis.structureProfile.oddEvenText}，'
              '大小 ${analysis.structureProfile.sizeText}，'
              '三区 ${analysis.structureProfile.zoneText}，'
              '和值 ${analysis.structureProfile.sum}，'
              '跨度 ${analysis.structureProfile.span}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBox(String text) {
    final paragraphs = text.split('\n\n');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '分析总结',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...paragraphs.map(
            (paragraph) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(paragraph),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({required String stepTitle}) {
    return _sectionCard(
      title: stepTitle,
      child: Column(
        children: [
          _dropdown<int>(
            label: '生成数量',
            value: _settings.count,
            items: const [5, 10, 20, 30],
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(count: value),
            ),
          ),
          _dropdown<int>(
            label: '允许保留参考红球',
            value: _settings.keepRedCount,
            items: const [0, 1, 2, 3, 4, 5],
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(keepRedCount: value),
            ),
          ),
          _dropdown<BlueBallMode>(
            label: '蓝球处理',
            value: _settings.blueBallMode,
            items: BlueBallMode.values,
            labelBuilder: (value) => switch (value) {
              BlueBallMode.keep => '必须保留参考蓝球',
              BlueBallMode.prefer => '优先保留参考蓝球',
              BlueBallMode.replace => '允许替换蓝球',
            },
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(blueBallMode: value),
            ),
          ),
          _dropdown<SimilarityLevel>(
            label: '相似度强度',
            value: _settings.similarityLevel,
            items: SimilarityLevel.values,
            labelBuilder: (value) => switch (value) {
              SimilarityLevel.low => '低',
              SimilarityLevel.medium => '中',
              SimilarityLevel.high => '高',
            },
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(similarityLevel: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('结构接近参考号码'),
            value: _settings.keepStructureClose,
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(keepStructureClose: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('排除完全相同组合'),
            value: _settings.excludeSameAsReference,
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(excludeSameAsReference: value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generateCard() {
    return _sectionCard(
      title: '第七步：生成相似组合',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成相似组合'),
          ),
          if (_generated.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('共生成 ${_generated.length} 组相似组合'),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _copyResults,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制全部'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exportResults,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('导出 TXT'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._generated.asMap().entries.map(
                  (entry) => _resultItem(entry.key + 1, entry.value),
                ),
          ],
        ],
      ),
    );
  }

  Widget _resultItem(int index, GeneratedCombination item) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '推荐组合 $index：${item.record.display}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...item.reasons.map((reason) => Text('• $reason')),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _subTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
  }

  Widget _statWrap(Iterable<String> items) {
    final list = items.toList();
    if (list.isEmpty) {
      return const Text('暂无数据');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: list.map((text) => Chip(label: Text(text))).toList(),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T> onChanged,
    String Function(T value)? labelBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder?.call(item) ?? item.toString()),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }

  String _pad(int value) => value.toString().padLeft(2, '0');

  String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  Map<int, int> _countRed(List<NumberRecord> records) {
    final result = <int, int>{};
    for (final record in records) {
      for (final number in record.redBalls) {
        result[number] = (result[number] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Map<int, int> _countBlue(List<NumberRecord> records) {
    final result = <int, int>{};
    for (final record in records) {
      result[record.blueBall] = (result[record.blueBall] ?? 0) + 1;
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }
}
