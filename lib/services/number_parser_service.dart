import '../models/number_record.dart';

class NumberParserService {
  static final RegExp _recordPattern = RegExp(
    r'红球[：:]\s*([0-9]{1,2}(?:\s*[,，.]\s*[0-9]{1,2}){5})\s*蓝球[：:]\s*([0-9]{1,2})',
  );

  ParsedFileResult parseFile({
    required String fileName,
    required String content,
  }) {
    final records = <NumberRecord>[];
    final errors = <String>[];
    final matches = _recordPattern.allMatches(content).toList();

    if (matches.isEmpty) {
      errors.add('未识别到“红球：...蓝球：...”格式的号码');
    }

    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final redText = match.group(1) ?? '';
      final blueText = match.group(2) ?? '';
      final redBalls = redText
          .split(RegExp(r'[,，.]'))
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList()
        ..sort();
      final blueBall = int.tryParse(blueText.trim());

      if (redBalls.length != 6) {
        errors.add('第 ${i + 1} 组红球数量不是 6 个，已跳过');
        continue;
      }
      if (redBalls.toSet().length != 6) {
        errors.add('第 ${i + 1} 组红球存在重复，已跳过');
        continue;
      }
      if (redBalls.any((n) => n < 1 || n > 33)) {
        errors.add('第 ${i + 1} 组红球超出 01-33，已跳过');
        continue;
      }
      if (blueBall == null || blueBall < 1 || blueBall > 16) {
        errors.add('第 ${i + 1} 组蓝球超出 01-16，已跳过');
        continue;
      }

      records.add(
        NumberRecord(
          redBalls: redBalls,
          blueBall: blueBall,
          sourceFileName: fileName,
        ),
      );
    }

    return ParsedFileResult(
      fileName: fileName,
      records: records,
      errors: errors,
    );
  }

  ReferenceNumber parseReference(String input) {
    final value = input.trim();
    final match = RegExp(
      r'^([0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[0-9]{2})\+([0-9]{2})$',
    ).firstMatch(value);

    if (match == null) {
      throw const FormatException('请输入正确格式，例如：01.02.03.04.05.06+09');
    }

    final redBalls = match
        .group(1)!
        .split('.')
        .map((e) => int.parse(e))
        .toList()
      ..sort();
    final blueBall = int.parse(match.group(2)!);

    if (redBalls.toSet().length != 6) {
      throw const FormatException('红球不能重复');
    }
    if (redBalls.any((n) => n < 1 || n > 33)) {
      throw const FormatException('红球范围应为 01-33');
    }
    if (blueBall < 1 || blueBall > 16) {
      throw const FormatException('蓝球范围应为 01-16');
    }

    return ReferenceNumber(redBalls: redBalls, blueBall: blueBall);
  }
}

