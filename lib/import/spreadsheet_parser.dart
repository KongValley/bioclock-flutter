import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:xml/xml.dart';

const Map<String, List<String>> _injectionAliases = {
  'injectedAt': ['注射时间', '时间', '日期时间', 'injectedat', 'date'],
  'medication': ['药物', '药名', '药品', 'medication', 'drug'],
  'dose': ['剂量', 'dose'],
  'unit': ['单位', 'unit'],
  'site': ['注射部位', '部位', 'site'],
  'lotNumber': ['批号', '批次', 'lotnumber', 'lot'],
  'note': ['备注', '说明', 'note'],
  'status': ['状态', 'status'],
  'lineLabel': ['用药线', '用药条目', 'linelabel', 'line'],
};

const Map<String, List<String>> _symptomAliases = {
  'loggedAt': ['记录时间', '时间', 'loggedat', 'date'],
  'severity': ['严重程度', '严重度', 'severity'],
  'painScore': ['疼痛评分', '疼痛', 'painscore', 'pain'],
  'tags': ['症状', '症状标签', 'tags'],
  'temperature': ['体温', '温度', 'temperature'],
  'note': ['备注', '说明', 'note'],
  'injectionAt': ['关联注射时间', '关联注射', 'injectionat'],
};

const Map<String, List<String>> _medicationAliases = {
  'name': ['药名', '药物', '药品', '名称', 'name'],
  'genericName': ['通用名', 'genericname', 'generic'],
  'brandNames': ['商品名', 'brandnames', 'brand'],
  'route': ['给药途径', '途径', '用药途径', 'route'],
  'defaultDose': ['默认剂量', '剂量', 'defaultdose', 'dose'],
  'unit': ['单位', 'unit'],
  'catalogKey': ['目录标识', '目录', 'catalogkey'],
};

const Map<String, List<String>> _oralAliases = {
  'takenAt': ['记录时间', '时间', '服药时间', '打卡时间', 'takenat', 'loggedat', 'date'],
  'medication': ['药物', '药名', '药品', 'medication', 'drug'],
  'status': ['状态', 'status'],
  'dose': ['剂量', 'dose'],
  'unit': ['单位', 'unit'],
  'note': ['备注', '说明', 'note'],
  'lineLabel': ['用药线', '用药条目', 'linelabel', 'line'],
};

const List<String> _injectionSheetNames = ['注射记录', '注射', 'injections', 'injection'];
const List<String> _symptomSheetNames = ['症状记录', '症状', 'symptoms', 'symptom'];
const List<String> _medicationSheetNames = [
  '药物',
  '药品',
  '药物目录',
  'medications',
  'medication',
  'drugs',
  'drug',
];
const List<String> _oralSheetNames = ['口服打卡', '口服记录', '口服', 'orallogs', 'oral'];

enum _RowKind { injection, symptom, medication, oral }

String _pad(int v) => v.toString().padLeft(2, '0');

String _formatDate(DateTime d) =>
    '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';

/// 将 Excel 日期序列号转为本地时间文本 `YYYY-MM-DD HH:mm`。
String _serialToText(num serial, {required bool date1904}) {
  final rawDays = serial.toDouble();
  final wholeDays = rawDays.floor();
  final fractionSeconds = ((rawDays - wholeDays) * 86400).round();

  final DateTime datePart;
  if (date1904) {
    datePart = DateTime(1904, 1, 1 + wholeDays);
  } else {
    // 1900 系统包含 1900-02-29 历史闰年 bug，以 1899-12-30 为第 0 天与 SheetJS 一致
    final adjusted = wholeDays < 60 ? wholeDays + 1 : wholeDays;
    datePart = DateTime(1899, 12, 30 + adjusted);
  }
  final dt = datePart.add(Duration(seconds: fractionSeconds));
  return _formatDate(dt);
}

final RegExp _isoFractionRe = RegExp(r'\.\d+$');

String _dateCellText(Object? value, {required bool date1904}) {
  if (value is DateTime) return _formatDate(value);
  if (value is num) return _serialToText(value, date1904: date1904);
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return '';
  // spreadsheet_decoder 将内置日期格式单元格解出为 YYYY-MM-DDTHH:mm:ss(.sss)
  if (_isoFractionRe.hasMatch(raw)) {
    return raw.replaceFirst(_isoFractionRe, '').replaceFirst('T', ' ');
  }
  return raw;
}

String _plainText(Object? value) {
  if (value is DateTime) return _formatDate(value);
  return (value ?? '').toString().trim();
}

final RegExp _parenNoteRe = RegExp(r'[（(][^）)]*[）)]');
final RegExp _headerStripRe = RegExp(r'[\s_\-*:：]');

String _normalizeHeader(Object? value) {
  return (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(_parenNoteRe, '')
      .replaceAll(_headerStripRe, '');
}

Map<String, int> _buildIndex(
  List<dynamic> header,
  Map<String, List<String>> aliases,
) {
  final normalized = header.map(_normalizeHeader).toList();
  final index = <String, int>{};
  for (final entry in aliases.entries) {
    final found = normalized.indexWhere((cell) => entry.value.contains(cell));
    if (found >= 0) index[entry.key] = found;
  }
  return index;
}

Map<String, Object?> _readRow(List<dynamic> row, Map<String, int> index) {
  final result = <String, Object?>{};
  for (final entry in index.entries) {
    if (entry.value >= row.length) continue;
    final value = row[entry.value];
    if (value != null && value.toString().trim().isNotEmpty) {
      result[entry.key] = value;
    }
  }
  return result;
}

bool _isEmptyRow(List<dynamic> row) {
  return row.every((cell) => cell == null || cell.toString().trim().isEmpty);
}

List<Map<String, Object?>> _parseMatrix(
  List<List<dynamic>> matrix,
  Map<String, List<String>> aliases,
  String requiredKey,
  String missingMessage,
) {
  if (matrix.isEmpty) return const [];
  final index = _buildIndex(matrix.first, aliases);
  if (!index.containsKey(requiredKey)) {
    throw ImportValidationException(missingMessage);
  }
  final rows = <Map<String, Object?>>[];
  for (var i = 1; i < matrix.length; i += 1) {
    if (_isEmptyRow(matrix[i])) continue;
    rows.add(_readRow(matrix[i], index));
  }
  return rows;
}

final RegExp _splitListRe = RegExp(r'[、,，;；/\n]+');

List<String> _splitList(Object? value) {
  if (value is List) {
    return value
        .map(_plainText)
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return _plainText(value)
      .split(_splitListRe)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<Map<String, Object?>> _normalizeRows(
  List<Map<String, Object?>> rows,
  _RowKind kind,
  bool date1904,
) {
  return rows.map((row) {
    final next = Map<String, Object?>.from(row);
    switch (kind) {
      case _RowKind.injection:
        if (next.containsKey('injectedAt')) {
          next['injectedAt'] =
              _dateCellText(next['injectedAt'], date1904: date1904);
        }
        if (next.containsKey('site')) next['site'] = _plainText(next['site']);
        if (next.containsKey('status')) {
          next['status'] = _plainText(next['status']);
        }
        if (next.containsKey('lineLabel')) {
          next['lineLabel'] = _plainText(next['lineLabel']);
        }
      case _RowKind.symptom:
        if (next.containsKey('loggedAt')) {
          next['loggedAt'] =
              _dateCellText(next['loggedAt'], date1904: date1904);
        }
        if (next.containsKey('injectionAt')) {
          next['injectionAt'] =
              _dateCellText(next['injectionAt'], date1904: date1904);
        }
        if (next.containsKey('tags')) next['tags'] = _splitList(next['tags']);
      case _RowKind.medication:
        for (final key in [
          'name',
          'genericName',
          'route',
          'unit',
          'catalogKey',
        ]) {
          if (next.containsKey(key)) next[key] = _plainText(next[key]);
        }
        if (next.containsKey('brandNames')) {
          next['brandNames'] = _splitList(next['brandNames']);
        }
      case _RowKind.oral:
        if (next.containsKey('takenAt')) {
          next['takenAt'] = _dateCellText(next['takenAt'], date1904: date1904);
        }
        for (final key in [
          'medication',
          'status',
          'unit',
          'note',
          'lineLabel',
        ]) {
          if (next.containsKey(key)) next[key] = _plainText(next[key]);
        }
    }
    return next;
  }).toList();
}

SpreadsheetTable? _findSheet(
  SpreadsheetDecoder decoder,
  List<String> names,
) {
  for (final sheetName in decoder.tables.keys) {
    if (names.contains(sheetName.trim().toLowerCase())) {
      return decoder.tables[sheetName];
    }
  }
  return null;
}

bool _looksLikeInjection(List<List<dynamic>> matrix) {
  if (matrix.isEmpty) return false;
  final index = _buildIndex(matrix.first, _injectionAliases);
  return index.containsKey('injectedAt') && index.containsKey('medication');
}

bool _looksLikeInjectionOnly(List<List<dynamic>> matrix) {
  if (!_looksLikeInjection(matrix)) return false;
  final index = _buildIndex(matrix.first, _injectionAliases);
  if (index.containsKey('site') || index.containsKey('lotNumber')) return true;
  final oralIndex = _buildIndex(matrix.first, _oralAliases);
  return !oralIndex.containsKey('status') &&
      !oralIndex.containsKey('lineLabel');
}

bool _looksLikeSymptom(List<List<dynamic>> matrix) {
  if (matrix.isEmpty) return false;
  final index = _buildIndex(matrix.first, _symptomAliases);
  return index.containsKey('loggedAt') &&
      (index.containsKey('severity') ||
          index.containsKey('tags') ||
          index.containsKey('temperature') ||
          index.containsKey('painScore'));
}

bool _looksLikeOral(List<List<dynamic>> matrix) {
  if (matrix.isEmpty) return false;
  final index = _buildIndex(matrix.first, _oralAliases);
  return index.containsKey('takenAt') && index.containsKey('medication');
}

bool _looksLikeMedication(List<List<dynamic>> matrix) {
  if (matrix.isEmpty) return false;
  final index = _buildIndex(matrix.first, _medicationAliases);
  return index.containsKey('name');
}

bool _detectDate1904(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('xl/workbook.xml');
    if (file == null) return false;
    final content = utf8.decode(file.content as List<int>);
    final doc = XmlDocument.parse(content);
    for (final node in doc.findAllElements('workbookPr')) {
      final attr = node.getAttribute('date1904');
      if (attr == '1' || attr == 'true') return true;
    }
  } catch (_) {}
  return false;
}

bool _looksLikeLegacyXls(Uint8List bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0;
}

ImportPayload parseSpreadsheet(Uint8List bytes) {
  if (_looksLikeLegacyXls(bytes)) {
    throw const ImportValidationException(
      '暂不支持旧版 .xls 二进制格式，请用 Excel / WPS 另存为 .xlsx 后再导入',
    );
  }

  final SpreadsheetDecoder decoder;
  try {
    decoder = SpreadsheetDecoder.decodeBytes(bytes);
  } catch (_) {
    throw const ImportValidationException('无法读取表格文件，请确认文件是有效的 .xlsx 文件');
  }

  final date1904 = _detectDate1904(bytes);

  var injectionRows = <Map<String, Object?>>[];
  var symptomRows = <Map<String, Object?>>[];
  var medicationRows = <Map<String, Object?>>[];
  var oralRows = <Map<String, Object?>>[];

  final injectionSheet = _findSheet(decoder, _injectionSheetNames);
  final symptomSheet = _findSheet(decoder, _symptomSheetNames);
  final medicationSheet = _findSheet(decoder, _medicationSheetNames);
  final oralSheet = _findSheet(decoder, _oralSheetNames);

  if (injectionSheet != null) {
    injectionRows = _parseMatrix(
      injectionSheet.rows,
      _injectionAliases,
      'injectedAt',
      '注射记录缺少「注射时间」列',
    );
  }
  if (symptomSheet != null) {
    symptomRows = _parseMatrix(
      symptomSheet.rows,
      _symptomAliases,
      'loggedAt',
      '症状记录缺少「记录时间」列',
    );
  }
  if (medicationSheet != null) {
    medicationRows = _parseMatrix(
      medicationSheet.rows,
      _medicationAliases,
      'name',
      '药物缺少「药名」列',
    );
  }
  if (oralSheet != null) {
    oralRows = _parseMatrix(
      oralSheet.rows,
      _oralAliases,
      'takenAt',
      '口服打卡缺少「记录时间」列',
    );
  }

  if (injectionSheet == null &&
      symptomSheet == null &&
      medicationSheet == null &&
      oralSheet == null) {
    if (decoder.tables.isEmpty) {
      throw const ImportValidationException('工作簿里没有工作表');
    }
    final first = decoder.tables.values.first;
    final matrix = first.rows;
    if (_looksLikeInjectionOnly(matrix)) {
      injectionRows = _parseMatrix(
        matrix,
        _injectionAliases,
        'injectedAt',
        '注射记录缺少「注射时间」列',
      );
    } else if (_looksLikeSymptom(matrix)) {
      symptomRows = _parseMatrix(
        matrix,
        _symptomAliases,
        'loggedAt',
        '症状记录缺少「记录时间」列',
      );
    } else if (_looksLikeOral(matrix)) {
      oralRows = _parseMatrix(
        matrix,
        _oralAliases,
        'takenAt',
        '口服打卡缺少「记录时间」列',
      );
    } else if (_looksLikeMedication(matrix)) {
      medicationRows = _parseMatrix(
        matrix,
        _medicationAliases,
        'name',
        '药物缺少「药名」列',
      );
    } else {
      throw const ImportValidationException(
        '没找到可识别的表头：注射表需要「注射时间、药物」，症状表需要「记录时间、严重程度」，药物表需要「药名」',
      );
    }
  }

  return parseImportRows(
    _normalizeRows(medicationRows, _RowKind.medication, date1904),
    _normalizeRows(injectionRows, _RowKind.injection, date1904),
    _normalizeRows(oralRows, _RowKind.oral, date1904),
    _normalizeRows(symptomRows, _RowKind.symptom, date1904),
  );
}
