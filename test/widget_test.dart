import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/main.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/screens/tabs/settings_tab.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await AppDatabase.configureForTesting();
    await AppDatabase.initDatabase();
  });

  tearDown(() async {
    await AppDatabase.closeForTesting();
  });

  testWidgets('首次启动展示初始化引导与免责声明', (tester) async {
    final store = AppStore();
    await tester.runAsync(store.reload);

    await tester.pumpWidget(
      BioClockApp(store: store, skipNotifyInit: true),
    );
    await tester.pump();

    expect(find.text('选择病种（可多选）'), findsOneWidget);
    expect(find.text('第 1 步 / 共 4 步'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
  });

  testWidgets('已配置方案时渲染五个底部标签并支持切换与深浅色主题', (tester) async {
    final store = AppStore();
    await tester.runAsync(() async {
      final meds = await MedicationsRepo.list();
      final scMed = meds.firstWhere((m) => m.route == MedicationRoute.sc);

      final created = await TreatmentsRepo.create(
        TreatmentInput(
          name: '司库奇尤维持方案',
          lines: [
            TreatmentLineInput(
              medicationId: scMed.id,
              kind: LineKind.injection,
              label: scMed.name,
              isHost: true,
              phases: const [
                TreatmentPhaseInput(
                  orderIdx: 0,
                  kind: PhaseKind.maintenance,
                  intervalDays: 28,
                  repeatCount: 0,
                  dose: 300,
                  unit: 'mg',
                ),
              ],
            ),
          ],
        ),
      );
      await TreatmentsRepo.setActive(created.id, true);
      await ReminderRulesRepo.upsert(
        ReminderRuleInput(
          treatmentId: created.id,
          offsets: const [-1, 0],
          timeOfDay: '09:00',
          snoozeMinutes: 30,
          enabled: true,
        ),
      );
      await SettingsRepo.set(
        'onboarded_at',
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      await SettingsRepo.set('disease_ids', '["psoriasis"]');
      await store.reload();
    });

    await tester.pumpWidget(
      BioClockApp(store: store, skipNotifyInit: true),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('今天'), findsWidgets);
    expect(find.text('记录'), findsWidgets);
    expect(find.text('日历'), findsWidgets);
    expect(find.text('趋势'), findsWidgets);
    expect(find.text('设置'), findsWidgets);

    await tester.tap(find.text('设置').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('治疗方案'), findsOneWidget);
    expect(find.text('司库奇尤维持方案'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('深色'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsTab),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    await tester.tap(find.text('深色'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    expect(store.settings['theme_mode'], 'dark');
  });

  testWidgets('设置页展示关于入口并支持查看关于详情、复制版本与免责声明', (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        copiedText = args?['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      ToastController.instance.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final store = AppStore();
    await tester.runAsync(() async {
      final meds = await MedicationsRepo.list();
      final scMed = meds.firstWhere((m) => m.route == MedicationRoute.sc);

      final created = await TreatmentsRepo.create(
        TreatmentInput(
          name: '阿达木维持方案',
          lines: [
            TreatmentLineInput(
              medicationId: scMed.id,
              kind: LineKind.injection,
              label: scMed.name,
              isHost: true,
              phases: const [
                TreatmentPhaseInput(
                  orderIdx: 0,
                  kind: PhaseKind.maintenance,
                  intervalDays: 14,
                  repeatCount: 0,
                  dose: 40,
                  unit: 'mg',
                ),
              ],
            ),
          ],
        ),
      );
      await TreatmentsRepo.setActive(created.id, true);
      await SettingsRepo.set(
        'onboarded_at',
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      await SettingsRepo.set(
        'disclaimer_accepted_at',
        '${DateTime.now().millisecondsSinceEpoch}',
      );
      await store.reload();
    });

    await tester.pumpWidget(
      BioClockApp(store: store, skipNotifyInit: true),
    );
    await tester.pump();

    await tester.tap(find.text('设置').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final settingsScrollable = find
        .descendant(
          of: find.byType(SettingsTab),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('关于 BioClock'),
      300,
      scrollable: settingsScrollable,
    );
    await tester.pump();

    expect(find.text('关于 BioClock'), findsOneWidget);
    expect(find.text('免责声明与隐私说明'), findsOneWidget);

    await tester.tap(find.text('关于 BioClock'));
    await tester.pumpAndSettle();

    expect(find.text('100% 本地离线'), findsOneWidget);
    expect(find.textContaining('v1.1.2+2'), findsOneWidget);
    expect(find.text('宁波猪猪侠'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/author_avatar.png',
      ),
      findsOneWidget,
    );
    final sheetScrollable = find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('本机数据概览'),
      250,
      scrollable: sheetScrollable,
    );
    expect(find.text('本机数据概览'), findsOneWidget);
    expect(find.textContaining('阿达木维持方案'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('复制版本与环境信息'),
      250,
      scrollable: sheetScrollable,
    );
    await tester.tap(find.text('复制版本与环境信息'));
    await tester.pump();
    expect(copiedText, contains('BioClock v1.1.2+2'));
    expect(find.text('已复制版本信息'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('开源组件许可'),
      250,
      scrollable: sheetScrollable,
    );
    expect(find.text('开源仓库'), findsOneWidget);
    expect(find.text('开源组件许可'), findsOneWidget);

    await tester.tap(find.text('免责声明与隐私说明').last);
    await tester.pumpAndSettle();
    expect(find.text(Zh.disclaimer.short), findsOneWidget);
    expect(find.text(Zh.disclaimer.body), findsOneWidget);

    ToastController.instance.clear();
    await tester.pump();
  });
}
