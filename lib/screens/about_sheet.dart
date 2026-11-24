import 'dart:io';

import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/schema.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String _repoUrl = 'https://github.com/KongValley/bioclock-flutter';
const String _repoDisplay = 'github.com/KongValley/bioclock-flutter';

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// 打开「关于 BioClock」详情弹窗。
Future<void> showAboutBioClockSheet(
  BuildContext context, {
  required String appVersion,
  required String buildNumber,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _AboutBioClockSheet(
      appVersion: appVersion,
      buildNumber: buildNumber,
    ),
  );
}

/// 打开完整免责声明与隐私说明弹窗。
Future<void> showDisclaimerSheet(
  BuildContext context, {
  int? acceptedAt,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _DisclaimerSheet(acceptedAt: acceptedAt),
  );
}

class _AboutBioClockSheet extends StatefulWidget {
  const _AboutBioClockSheet({
    required this.appVersion,
    required this.buildNumber,
  });

  final String appVersion;
  final String buildNumber;

  @override
  State<_AboutBioClockSheet> createState() => _AboutBioClockSheetState();
}

class _AboutBioClockSheetState extends State<_AboutBioClockSheet> {
  String? _dbPath;
  int? _dbSizeBytes;

  @override
  void initState() {
    super.initState();
    _loadDbInfo();
  }

  Future<void> _loadDbInfo() async {
    try {
      final path = await AppDatabase.resolveDatabasePath();
      int? size;
      if (path != ':memory:' && !path.startsWith('file:')) {
        final file = File(path);
        if (await file.exists()) {
          size = await file.length();
        }
      }
      if (!mounted) return;
      setState(() {
        _dbPath = path;
        _dbSizeBytes = size;
      });
    } catch (_) {
      // 测试环境或权限受限场景忽略文件大小探测
    }
  }

  Future<void> _copyText(String text, String toastMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    showToast(toastMessage);
  }

  String get _versionTag => widget.buildNumber.isNotEmpty
      ? 'v${widget.appVersion}+${widget.buildNumber}'
      : 'v${widget.appVersion}';

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    final acceptedRaw =
        int.tryParse(store.settings['disclaimer_accepted_at'] ?? '');

    final lineKinds = <String, LineKind>{
      for (final t in store.treatments)
        for (final l in t.lines) l.id: l.kind,
    };
    var injectionCount = 0;
    var oralCount = 0;
    for (final log in store.doseLogs) {
      if (lineKinds[log.lineId] == LineKind.oral) {
        oralCount += 1;
      } else {
        injectionCount += 1;
      }
    }
    final customMedCount =
        store.medications.where((m) => !m.isBuiltin).length;

    final dbSummary = _dbPath == null
        ? '读取中…'
        : _dbPath == ':memory:'
            ? '内存数据库（测试模式）'
            : _dbSizeBytes != null
                ? '$databaseName · ${_formatBytes(_dbSizeBytes!)}'
                : databaseName;

    return SheetScaffold(
      title: '关于 BioClock',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          theme.spacing.lg,
          theme.spacing.xs,
          theme.spacing.lg,
          theme.spacing.xl,
        ),
        children: [
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _AssetBadge(
                  assetPath: 'assets/images/icon.png',
                  size: 56,
                  radius: theme.radius.lg,
                  fallbackIcon: AppIconName.syringe,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            Zh.appName,
                            style: TextStyle(
                              color: theme.colors.text,
                              fontSize: theme.fontSize.xl,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _PillBadge(
                            label: '100% 本地离线',
                            background: theme.colors.primaryMuted,
                            foreground: theme.colors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '纯本地生物制剂注射记录与提醒工具',
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: theme.fontSize.sm,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_versionTag · 数据库 Schema v$schemaVersion',
                        style: TextStyle(
                          color: theme.colors.textTertiary,
                          fontSize: theme.fontSize.xs,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle(title: '作者与开发'),
          const SizedBox(height: 10),
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _AssetBadge(
                  assetPath: 'assets/images/author_avatar.png',
                  size: 54,
                  circular: true,
                  fallbackIcon: AppIconName.smile,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '宁波猪猪侠',
                            style: TextStyle(
                              color: theme.colors.text,
                              fontSize: theme.fontSize.lg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _PillBadge(
                            label: '独立开发',
                            background: theme.colors.primaryMuted,
                            foreground: theme.colors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'BioClock 作者 · GitHub @KongValley',
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: theme.fontSize.sm,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: '核心特性与隐私承诺',
            hint: '全部健康数据仅保留在你的设备本机',
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FeatureItem(
                  icon: AppIconName.lock,
                  title: '纯本地 SQLite 存储，零云端上传',
                  detail:
                      '治疗方案、打卡记录、症状、提醒规则均保存于本机数据库，无需登录账号，不采集任何远程遥测。',
                ),
                const SizedBox(height: 12),
                _FeatureItem(
                  icon: AppIconName.syringe,
                  title: '多阶段排程与部位轮换管理',
                  detail:
                      '支持负荷/维持多阶段周期、按实际或计划时间锚点推算下次注射、推荐注射部位轮换与停药线保留。',
                ),
                const SizedBox(height: 12),
                _FeatureItem(
                  icon: AppIconName.activity,
                  title: '趋势统计、多格式报告与换机迁移',
                  detail:
                      '内置依从性趋势、NRS 疼痛评分与疗效事件记录，支持导出 PDF 就诊报告、Excel、CSV、JSON 与完整换机包。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle(
            title: '本机数据概览',
            hint: '实时统计当前设备上的离线记录规模',
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: false,
            child: Column(
              children: [
                _KeyValueRow(
                  label: '治疗方案',
                  value: store.treatment != null
                      ? '${store.treatments.length} 套（启用：${store.treatment!.name}）'
                      : '${store.treatments.length} 套',
                ),
                _KeyValueRow(
                  label: '打卡记录',
                  value: '注射 $injectionCount 条 · 口服 $oralCount 条',
                ),
                _KeyValueRow(
                  label: '症状与疗效',
                  value:
                      '症状 ${store.symptoms.length} 条 · 疗效 ${store.efficacyEvents.length} 条',
                ),
                _KeyValueRow(
                  label: '药物目录',
                  value: customMedCount > 0
                      ? '${store.medications.length} 种（自定义 $customMedCount 种）'
                      : '${store.medications.length} 种',
                ),
                SettingRow(
                  label: '本机数据库',
                  hint: _dbPath == null || _dbPath == ':memory:' ? null : _dbPath,
                  value: dbSummary,
                  last: true,
                  onTap: _dbPath == null || _dbPath == ':memory:'
                      ? null
                      : () => _copyText(_dbPath!, '已复制数据库路径'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle(title: '项目与许可'),
          const SizedBox(height: 10),
          AppCard(
            padding: false,
            child: Column(
              children: [
                SettingRow(
                  label: '复制版本与环境信息',
                  hint: '用于反馈问题或核对构建版本',
                  value: _versionTag,
                  onTap: () => _copyText(
                    'BioClock $_versionTag (${Platform.operatingSystem}) · Schema v$schemaVersion',
                    '已复制版本信息',
                  ),
                ),
                SettingRow(
                  label: '开源仓库',
                  hint: _repoDisplay,
                  value: '复制链接',
                  onTap: () => _copyText(_repoUrl, '已复制开源仓库地址'),
                ),
                SettingRow(
                  label: '免责声明与隐私说明',
                  hint: acceptedRaw != null
                      ? '${Zh.disclaimer.acceptedAt}：${formatDateTime(acceptedRaw)}'
                      : Zh.disclaimer.short,
                  onTap: () => showDisclaimerSheet(
                    context,
                    acceptedAt: acceptedRaw,
                  ),
                ),
                SettingRow(
                  label: '开源组件许可',
                  hint: '查看 Flutter 与第三方依赖许可证',
                  last: true,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: Zh.appName,
                    applicationVersion: _versionTag,
                    applicationIcon: const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 8),
                      child: _AssetBadge(
                        assetPath: 'assets/images/icon.png',
                        size: 56,
                        radius: 14,
                        fallbackIcon: AppIconName.syringe,
                      ),
                    ),
                    applicationLegalese:
                        '© 2026 宁波猪猪侠 · BioClock 纯本地生物制剂注射记录与提醒工具',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerSheet extends StatelessWidget {
  const _DisclaimerSheet({this.acceptedAt});

  final int? acceptedAt;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    return SheetScaffold(
      title: '免责声明与隐私说明',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          theme.spacing.lg,
          theme.spacing.xs,
          theme.spacing.lg,
          theme.spacing.xl,
        ),
        children: [
          AppCard(
            tone: AppCardTone.primary,
            child: Text(
              Zh.disclaimer.short,
              style: TextStyle(
                color: theme.colors.text,
                fontSize: theme.fontSize.md,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  Zh.disclaimer.body,
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: theme.colors.border),
                const SizedBox(height: 14),
                Text(
                  '隐私与数据说明',
                  style: TextStyle(
                    color: theme.colors.text,
                    fontSize: theme.fontSize.md,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'BioClock 为纯本地离线工具，所有用药方案、注射记录、症状日记、本地通知排程与导出文件均在你的设备本机处理与保存，不会上传至任何第三方服务器。',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                    height: 1.6,
                  ),
                ),
                if (acceptedAt != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${Zh.disclaimer.acceptedAt}：${formatDateTime(acceptedAt!)}',
                    style: TextStyle(
                      color: theme.colors.textTertiary,
                      fontSize: theme.fontSize.xs,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetBadge extends StatelessWidget {
  const _AssetBadge({
    required this.assetPath,
    required this.size,
    required this.fallbackIcon,
    this.radius = 14,
    this.circular = false,
  });

  final String assetPath;
  final double size;
  final AppIconName fallbackIcon;
  final double radius;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colors.primaryMuted,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(radius),
        border: Border.all(
          color: theme.colors.border,
          width: circular ? 1.2 : 0.8,
        ),
      ),
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: AppIcon(
            fallbackIcon,
            size: size * 0.5,
            color: theme.colors.primary,
          ),
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(theme.radius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: theme.fontSize.xs,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final AppIconName icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colors.primaryMuted,
            borderRadius: BorderRadius.circular(theme.radius.sm),
          ),
          alignment: Alignment.center,
          child: AppIcon(
            icon,
            size: 18,
            color: theme.colors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  color: theme.colors.textSecondary,
                  fontSize: theme.fontSize.xs,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.lg,
        vertical: theme.spacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colors.border, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colors.text,
              fontSize: theme.fontSize.md,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
