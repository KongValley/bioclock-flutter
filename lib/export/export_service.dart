import 'dart:io';

import 'package:bioclock/export/csv_exporter.dart';
import 'package:bioclock/export/transfer_exporter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

export 'package:bioclock/export/csv_exporter.dart';
export 'package:bioclock/export/excel_exporter.dart';
export 'package:bioclock/export/json_exporter.dart';
export 'package:bioclock/export/pdf_exporter.dart';
export 'package:bioclock/export/transfer_exporter.dart';
export 'package:bioclock/export/transfer_schema.dart';

class ExportDeliveryResult {
  const ExportDeliveryResult({
    required this.completed,
    required this.filename,
    this.savedPath,
  });

  final bool completed;
  final String filename;
  final String? savedPath;
}

/// 跨平台交付导出文件：Windows/桌面使用系统「另存为」对话框，移动端调用系统分享面板。
Future<ExportDeliveryResult> shareOrSaveExportFile(
  ExportFileOutput file, {
  required String mimeType,
  String? dialogTitle,
}) async {
  if (Platform.isWindows || Platform.isLinux) {
    final bytes = await File(file.path).readAsBytes();
    final savedUri = await FilePicker.saveFile(
      fileName: file.filename,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: dialogTitle ?? '保存导出文件',
    );
    if (savedUri == null) {
      return ExportDeliveryResult(
        completed: false,
        filename: file.filename,
      );
    }
    final savedPath =
        savedUri.scheme == 'file' ? savedUri.toFilePath() : savedUri.toString();
    return ExportDeliveryResult(
      completed: true,
      filename: file.filename,
      savedPath: savedPath,
    );
  }

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: file.filename)],
      subject: file.filename,
    ),
  );
  return ExportDeliveryResult(
    completed: result.status != ShareResultStatus.dismissed,
    filename: file.filename,
    savedPath: file.path,
  );
}

Future<ExportDeliveryResult> shareOrSaveTransferFile(
  TransferExportResult transfer, {
  String? dialogTitle,
}) {
  return shareOrSaveExportFile(
    ExportFileOutput(path: transfer.path, filename: transfer.filename),
    mimeType: 'application/json',
    dialogTitle: dialogTitle ?? '保存换机备份',
  );
}
