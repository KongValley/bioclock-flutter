import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/symptom_fields.dart';
import 'package:bioclock/ui/components/time_fields.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

Future<void> showSymptomModal(
  BuildContext context, {
  String? editingId,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _SymptomModalContent(editingId: editingId),
  );
}

class _SymptomModalContent extends StatefulWidget {
  const _SymptomModalContent({this.editingId});

  final String? editingId;

  @override
  State<_SymptomModalContent> createState() => _SymptomModalContentState();
}

class _SymptomModalContentState extends State<_SymptomModalContent> {
  int _loggedAt = DateTime.now().millisecondsSinceEpoch;
  int _severity = 3;
  int? _painScore;
  List<String> _tags = [];
  String _temperatureText = '';
  String _note = '';
  String? _injectionId;
  bool _managerOpen = false;
  bool _initialized = false;
  bool _saving = false;
  String? _formError;

  SymptomLog? _findEditing(AppStore store) {
    if (widget.editingId == null) return null;
    for (final s in store.symptoms) {
      if (s.id == widget.editingId) return s;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.store;
    if (!store.ready || _initialized) return;

    final editing = _findEditing(store);
    if (editing != null) {
      _loggedAt = editing.loggedAt;
      _severity = editing.severity;
      _painScore = editing.painScore;
      _tags = List<String>.from(editing.tags);
      _temperatureText =
          editing.temperature != null ? '${editing.temperature}' : '';
      _note = editing.note ?? '';
      _injectionId = editing.injectionId;
    }
    _initialized = true;
  }

  Future<void> _save() async {
    final store = context.store;
    final editing = _findEditing(store);
    setState(() => _formError = null);

    double? temp;
    if (_temperatureText.trim().isNotEmpty) {
      final parsed = double.tryParse(_temperatureText.trim());
      if (parsed == null || !parsed.isFinite || parsed < 30 || parsed > 45) {
        setState(() => _formError = '体温应在 30℃ 到 45℃ 之间。');
        return;
      }
      temp = (parsed * 10).round() / 10;
    }

    setState(() => _saving = true);
    try {
      final MutationResult result;
      if (editing != null) {
        result = await store.updateSymptom(
          editing.id,
          SymptomLogPatch(
            loggedAt: _loggedAt,
            severity: _severity,
            painScore: PatchValue(_painScore),
            tags: _tags,
            note: PatchValue(_note.trim().isEmpty ? null : _note.trim()),
            temperature: PatchValue(temp),
            injectionId: PatchValue(_injectionId),
          ),
        );
      } else {
        result = await store.addSymptom(
          SymptomLogInput(
            loggedAt: _loggedAt,
            severity: _severity,
            painScore: _painScore,
            tags: _tags,
            note: _note.trim().isEmpty ? null : _note.trim(),
            temperature: temp,
            injectionId: _injectionId,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(editing != null ? '症状记录已更新' : '症状已记录');
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      final msg = friendlyErrorMessage(err);
      if (mounted) {
        setState(() => _formError = msg);
        showToast(msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    final editing = _findEditing(store);
    final medNames = {for (final m in store.medications) m.id: m.name};
    final injLines = {
      for (final line in store.treatment?.lines ?? <TreatmentLine>[])
        if (line.kind == LineKind.injection) line.id: line.medicationId,
    };
    final recentInjections = [
      for (final log in store.doseLogs)
        if (injLines.containsKey(log.lineId))
          (
            log: log,
            at: log.takenAt ?? log.scheduledAt ?? log.createdAt,
            medId: injLines[log.lineId],
          ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    final top5 = recentInjections.take(5).toList();

    final tagNames = [for (final t in store.symptomTags) t.name];
    final tagOptions = [
      ...tagNames,
      for (final t in _tags)
        if (!tagNames.contains(t)) t,
    ];

    final severities = [
      (1, Zh.form.severity1, theme.colors.success),
      (2, Zh.form.severity2, theme.colors.primary),
      (3, Zh.form.severity3, theme.colors.warning),
      (4, Zh.form.severity4, theme.colors.danger),
      (5, Zh.form.severity5, theme.colors.danger),
    ];

    return SheetScaffold(
      title: editing != null ? Zh.history.editSymptom : Zh.history.addSymptom,
      heightFactor: 0.94,
      body: !store.ready
          ? const LoadingView()
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                theme.spacing.lg,
                0,
                theme.spacing.lg,
                theme.spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DateTimeField(
                    label: Zh.form.loggedAt,
                    value: _loggedAt,
                    onChanged: (v) => setState(() => _loggedAt = v),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Zh.form.severity,
                    style: TextStyle(
                      color: theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < severities.length; i += 1) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: () {
                            final (val, label, color) = severities[i];
                            final selected = _severity == val;
                            return Semantics(
                              button: true,
                              selected: selected,
                              label: '严重程度 $val，$label',
                              child: Material(
                                color: selected ? color : theme.colors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(theme.radius.md),
                                  side: BorderSide(
                                    color:
                                        selected ? color : theme.colors.border,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(theme.radius.md),
                                  onTap: () => setState(() => _severity = val),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 62),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 8,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '$val',
                                            style: TextStyle(
                                              color: selected
                                                  ? theme.colors.onPrimary
                                                  : theme.colors.text,
                                              fontSize: theme.fontSize.lg,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: selected
                                                  ? theme.colors.onPrimary
                                                  : theme.colors.textTertiary,
                                              fontSize: theme.fontSize.xs,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        Zh.form.symptomTags,
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: theme.fontSize.sm,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        button: true,
                        label: Zh.form.manageTags,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(theme.radius.pill),
                          onTap: () =>
                              setState(() => _managerOpen = !_managerOpen),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon(
                                  _managerOpen
                                      ? AppIconName.close
                                      : AppIconName.settings,
                                  size: 14,
                                  color: theme.colors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  Zh.form.manageTags,
                                  style: TextStyle(
                                    color: theme.colors.primary,
                                    fontSize: theme.fontSize.xs,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tagOptions)
                        AppChip(
                          label: tag,
                          selected: _tags.contains(tag),
                          onPressed: () {
                            setState(() {
                              if (_tags.contains(tag)) {
                                _tags = _tags.where((t) => t != tag).toList();
                              } else {
                                _tags = [..._tags, tag];
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  if (tagOptions.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      Zh.form.tagEmpty,
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                  if (_managerOpen) ...[
                    const SizedBox(height: 10),
                    SymptomTagManager(
                      onAdded: (name) {
                        if (!_tags.contains(name)) {
                          setState(() => _tags = [..._tags, name]);
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  PainScale(
                    value: _painScore,
                    onChanged: (v) => setState(() => _painScore = v),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '${Zh.form.temperature}（${Zh.common.optional}）',
                    value: _temperatureText,
                    onChanged: (v) => _temperatureText = v,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    placeholder: '36.8',
                    suffix: '℃',
                    semanticLabel: '体温',
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '${Zh.form.note}（${Zh.common.optional}）',
                    value: _note,
                    onChanged: (v) => _note = v,
                    multiline: true,
                    placeholder: '症状出现的时间、持续多久、是否缓解…',
                    semanticLabel: '症状备注',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Zh.form.relatedInjection,
                    style: TextStyle(
                      color: theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppChip(
                        label: '不关联',
                        selected: _injectionId == null,
                        semanticLabel: '不关联注射记录',
                        onPressed: () => setState(() => _injectionId = null),
                      ),
                      for (final item in top5)
                        AppChip(
                          label:
                              '${formatDate(item.at)} · ${item.medId != null ? (medNames[item.medId] ?? Zh.common.unknown) : Zh.common.unknown}',
                          selected: _injectionId == item.log.id,
                          semanticLabel: '关联 ${formatDate(item.at)} 的注射',
                          onPressed: () => setState(
                            () => _injectionId =
                                _injectionId == item.log.id ? null : item.log.id,
                          ),
                        ),
                    ],
                  ),
                  if (top5.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '还没有注射记录可关联。',
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    InlineError(message: _formError!),
                  ],
                ],
              ),
            ),
      footer: Row(
        children: [
          Expanded(
            child: AppButton(
              label: Zh.common.cancel,
              onPressed: () => Navigator.of(context).pop(),
              variant: AppButtonVariant.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AppButton(
              label: editing != null ? Zh.common.save : '保存记录',
              onPressed: _save,
              loading: _saving,
              disabled: !store.ready,
            ),
          ),
        ],
      ),
    );
  }
}
