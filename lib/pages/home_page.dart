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
import '../services/combination_generator_service.dart';
import '../services/number_parser_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _parser = NumberParserService();
  final _analysisService = AnalysisService();
  final _generator = CombinationGeneratorService();
  final _referenceController = TextEditingController(text: '01.02.03.04.05.06+09');

  List<ParsedFileResult> _fileAResults = [];
  List<ParsedFileResult> _fileBResults = [];
  ReferenceNumber? _reference;
  AnalysisResult? _analysis;
  GenerationSettings _settings = const GenerationSettings();
  List<GeneratedCombination> _generated = [];
  bool _busy = false;

  List<NumberRecord> get _recordsA =>
      _fileAResults.expand((result) => result.records).toList();
  List<NumberRecord> get _recordsB =>
      _fileBResults.expand((result) => result.records).toList();

  @override
  void dispose() {
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles({required bool forAnalysis}) async {
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
        if (forAnalysis) {
          _fileAResults = parsedResults;
          _analysis = null;
          _generated = [];
        } else {
          _fileBResults = parsedResults;
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

  void _runAnalysis() {
    if (_recordsA.isEmpty) {
      _showMessage('请先导入分析文件 A');
      return;
    }
    try {
      final reference = _parser.parseReference(_referenceController.text);
      final analysis = _analysisService.analyze(
        records: _recordsA,
        reference: reference,
      );
      setState(() {
        _reference = reference;
        _analysis = analysis;
        _generated = [];
      });
    } on FormatException catch (error) {
      _showMessage(error.message);
    }
  }

  void _generate() {
    if (_analysis == null || _reference == null) {
      _showMessage('请先完成文件 A 分析');
      return;
    }
    if (_recordsB.isEmpty) {
      _showMessage('请先导入组合文件 B');
      return;
    }
    final generated = _generator.generate(
      reference: _reference!,
      analysis: _analysis!,
      fileBRecords: _recordsB,
      settings: _settings,
    );
    setState(() => _generated = generated);
    if (generated.isEmpty) {
      _showMessage('没有生成符合当前条件的组合，请降低相似度或减少保留数量');
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
    await Share.shareXFiles([XFile(file.path)], text: '数据分析仪生成结果');
  }

  String _resultText() {
    final buffer = StringBuffer()
      ..writeln('数据分析仪生成结果')
      ..writeln('参考号码：${_reference?.display ?? ''}')
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
              _importCard(
                title: '第一步：导入分析文件 A',
                description: '可选择一个或多个 TXT 购买情况文件，用于分析参考号码规律。',
                results: _fileAResults,
                onPressed: () => _pickFiles(forAnalysis: true),
              ),
              _referenceCard(),
              if (_analysis != null) _analysisCard(_analysis!),
              _settingsCard(),
              _importCard(
                title: '第五步：导入组合文件 B',
                description: '可选择一个或多个 TXT 文件，用于生成相似风格的新组合。',
                results: _fileBResults,
                onPressed: () => _pickFiles(forAnalysis: false),
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
      title: '离线购买数据分析',
      child: const Text(
        '软件根据用户导入的购买情况文件和参考号码，分析出现次数、概率、共现关系、搭配规律和相似组合，再结合第二批文件生成类似组合。全程离线，不需要网络。',
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

  Widget _referenceCard() {
    return _sectionCard(
      title: '第二步：输入参考号码',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('格式固定为：01.02.03.04.05.06+09'),
          const SizedBox(height: 12),
          TextField(
            controller: _referenceController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '参考号码',
            ),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _runAnalysis,
            icon: const Icon(Icons.analytics),
            label: const Text('开始分析文件 A'),
          ),
        ],
      ),
    );
  }

  Widget _analysisCard(AnalysisResult analysis) {
    return _sectionCard(
      title: '第三步：规律分析结果',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(analysis.summaryText),
          const SizedBox(height: 16),
          _subTitle('参考红球次数'),
          _statWrap(
            analysis.referenceRedStats.map(
              (stat) => '${_pad(stat.number)}：${stat.count}次，${_percent(stat.probability)}',
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
    );
  }

  Widget _settingsCard() {
    return _sectionCard(
      title: '第四步：设置生成条件',
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
            label: '最少保留参考红球',
            value: _settings.minKeepRed,
            items: const [1, 2, 3, 4, 5],
            onChanged: (value) => setState(
              () => _settings = _settings.copyWith(minKeepRed: value),
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
      title: '第六步：生成相似组合',
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
}
