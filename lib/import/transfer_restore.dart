import 'package:bioclock/db/repo.dart';
import 'package:bioclock/export/transfer_schema.dart';
import 'package:bioclock/import/import_service.dart';
import 'package:bioclock/import/transfer.dart';
import 'package:bioclock/store/app_store.dart';

class TransferRestoreOutcome {
  const TransferRestoreOutcome({
    required this.result,
    this.notifyWarning,
  });

  final ImportResult result;
  final String? notifyWarning;
}

/// 从换机快照完整恢复：先建出激活方案与用药线，再写入打卡/症状/疗效，最后恢复设置与提醒。
Future<TransferRestoreOutcome> restoreTransferBackup(
  AppStore store,
  String text,
) async {
  final summary = summarizeTransfer(text);
  await ensureTreatmentFromTransfer(text);

  final outcome = await store.importRecords(transferToImportPayload(text));
  final warnings = <String>[];
  if (outcome.notifyWarning != null) warnings.add(outcome.notifyWarning!);

  final safeSettings = Map<String, String>.from(summary.settings)
    ..remove('app_lock');
  if ((safeSettings['onboarded_at'] ?? '').isEmpty) {
    safeSettings['onboarded_at'] =
        DateTime.now().millisecondsSinceEpoch.toString();
  }
  final settingsResult = await store.updateSettings(safeSettings);
  if (settingsResult.notifyWarning != null) {
    warnings.add(settingsResult.notifyWarning!);
  }

  final active = store.treatment;
  if (active != null && summary.reminder != null) {
    final rem = summary.reminder!;
    final reminderResult = await store.updateReminder(
      ReminderRuleInput(
        treatmentId: active.id,
        offsets: rem.offsets,
        timeOfDay: rem.timeOfDay,
        snoozeMinutes: rem.snoozeMinutes,
        enabled: rem.enabled,
      ),
    );
    if (reminderResult.notifyWarning != null) {
      warnings.add(reminderResult.notifyWarning!);
    }
  }

  return TransferRestoreOutcome(
    result: outcome.result,
    notifyWarning: warnings.isNotEmpty ? warnings.join('；') : null,
  );
}
