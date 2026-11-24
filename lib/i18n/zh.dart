import 'package:bioclock/models/types.dart';

/// 首次启动时写入症状标签表的默认项；之后以数据库为准，用户可增删。
const List<String> defaultSymptomTags = [
  '注射部位红肿',
  '注射部位硬结',
  '发热',
  '乏力',
  '皮疹',
  '关节痛',
  '头痛',
  '恶心',
  '腹泻',
  '瘙痒',
];

abstract final class Zh {
  static const String appName = 'BioClock';

  static const tabs = _Tabs();
  static const calendar = _Calendar();
  static const common = _Common();
  static const empty = _Empty();
  static const today = _Today();
  static const history = _History();
  static const trends = _Trends();
  static const settings = _Settings();
  static const onboarding = _Onboarding();
  static const form = _Form();
  static const sites = _Sites();
  static const status = _Status();
  static const doseStatus = _DoseStatus();
  static const report = _Report();
  static const disclaimer = _Disclaimer();
  static const notify = _Notify();
  static const errors = _Errors();

  static String siteLabel(InjectionSite site) => switch (site) {
        InjectionSite.abdomenUl => sites.abdomenUl,
        InjectionSite.abdomenUr => sites.abdomenUr,
        InjectionSite.abdomenLl => sites.abdomenLl,
        InjectionSite.abdomenLr => sites.abdomenLr,
        InjectionSite.thighL => sites.thighL,
        InjectionSite.thighR => sites.thighR,
        InjectionSite.armL => sites.armL,
        InjectionSite.armR => sites.armR,
      };

  static String doseStatusLabel(DoseStatus s) => switch (s) {
        DoseStatus.done => doseStatus.done,
        DoseStatus.skipped => doseStatus.skipped,
        DoseStatus.missed => doseStatus.missed,
      };
}

class _Tabs {
  const _Tabs();
  final String today = '今天';
  final String history = '记录';
  final String calendar = '日历';
  final String trends = '趋势';
  final String settings = '设置';
}

class _Calendar {
  const _Calendar();
  final String title = '日历';
  final String hint = '查看未来的注射日程';
  final String today = '今天';
  final String prevMonth = '上个月';
  final String nextMonth = '下个月';
  final List<String> weekdays = const ['一', '二', '三', '四', '五', '六', '日'];
  final String selectedDay = '当天安排';
  final String emptyDay = '这天没有注射安排';
  final String emptyMonth = '本月没有注射安排';
  final String noTreatment = '还没有治疗方案';
  final String noInjectionLines = '当前方案没有注射线';
  final String countSuffix = '针';
  final String phaseLoading = '负荷';
  final String phaseMaintenance = '维持';
  final String statusDone = '已完成';
  final String statusDue = '今天';
  final String statusOverdue = '已逾期';
  final String statusUpcoming = '计划';
  final String statusMissed = '已跳过';
  final String legend = '圆点表示当天有注射计划，选中日期可查看药名和剂量。';
  final String footerNote = '日历只展示计划，不替代医嘱；实际注射时间以登记记录为准。';
}

class _Common {
  const _Common();
  final String appTitle = 'BioClock';
  final String loading = '正在加载…';
  final String loadFailed = '数据加载失败';
  final String retry = '重试';
  final String save = '保存';
  final String cancel = '取消';
  final String confirm = '确定';
  final String delete = '删除';
  final String edit = '编辑';
  final String close = '关闭';
  final String back = '返回';
  final String next = '下一步';
  final String previous = '上一步';
  final String done = '完成';
  final String add = '新增';
  final String unknown = '未知';
  final String optional = '选填';
  final String notSet = '未设置';
  final String unitMg = 'mg';
  final String unitMl = 'ml';
  final String unitDay = '天';
  final String unitWeek = '周';
}

class _Empty {
  const _Empty();
  final String todayNoRegimen = '还没有用药方案，先去设置里添加一个';
  final String todayNoInjection = '还没有注射记录，打完针后在这里登记';
  final String historyNoInjection = '暂无注射记录';
  final String historyNoSymptom = '暂无症状记录';
  final String trendsNoData = '记录满两次注射后，这里会显示趋势';
  final String settingsNoReminder = '尚未设置提醒';
}

class _Today {
  const _Today();
  final String title = '今天';
  final String countdownPrefix = '距下次注射还有';
  final String countdownToday = '今天该注射了';
  final String overduePrefix = '已逾期';
  final String lastInjection = '上次注射';
  final String nextInjection = '下次注射';
  final String registerInjection = '登记注射';
  final String recommendedSite = '推荐注射部位';
  final String rotateHint = '建议轮换注射部位，腹部需距脐 5cm 以上';
  final String quickLogSymptom = '记录症状';
  final String noSchedule = '暂无排程';
}

class _History {
  const _History();
  final String title = '记录';
  final String injectionTab = '注射';
  final String oralTab = '口服';
  final String symptomTab = '症状';
  final String addInjection = '新增注射';
  final String addSymptom = '新增症状';
  final String editSymptom = '编辑症状';
  final String painLabel = '疼痛';
  final String deleteInjectionTitle = '删除这条注射记录？';
  final String deleteInjectionMessage = '删除后下次注射时间会重新计算，此操作不可恢复。';
  final String deleteOralTitle = '删除这条口服记录？';
  final String deleteOralMessage = '此操作不可恢复。';
  final String deleteSymptomTitle = '删除这条症状记录？';
  final String deleteSymptomMessage = '此操作不可恢复。';
}

class _Trends {
  const _Trends();
  final String title = '趋势';
  final String adherence = '依从性';
  final String onTime = '按时';
  final String early = '提前';
  final String late = '延迟';
  final String avgDeviation = '平均偏差';
  final String currentStreak = '连续按时';
  final String symptomTimeline = '症状与注射时间线';
  final String correlationNote = '仅用于自我观察，不构成因果判断。';
}

class _Settings {
  const _Settings();
  final String title = '设置';
  final String regimenSection = '用药方案';
  final String regimenName = '方案名称';
  final String medication = '药物';
  final String anchor = '排程锚点';
  final String anchorActual = '按实际注射时间（推荐）';
  final String anchorPlanned = '按计划时间';
  final String windowDays = '按时窗口（±天）';
  final String phases = '剂量阶段';
  final String addPhase = '添加阶段';
  final String phaseKind = '阶段类型';
  final String phaseLoading = '负荷剂量';
  final String phaseMaintenance = '维持剂量';
  final String intervalDays = '间隔天数';
  final String repeatCount = '重复次数（0 表示无限）';
  final String dose = '剂量';
  final String reminderSection = '提醒';
  final String reminderEnabled = '开启提醒';
  final String reminderOffsets = '提前提醒天数';
  final String reminderTime = '提醒时间';
  final String snoozeMinutes = '稍后提醒（分钟）';
  final String securitySection = '隐私与安全';
  final String appLock = '应用锁';
  final String appLockHint = '使用指纹、面容或系统凭据解锁 BioClock';
  final String theme = '外观';
  final String themeSystem = '跟随系统';
  final String themeLight = '浅色';
  final String themeDark = '深色';
  final String exportSection = '数据';
  final String exportCsv = '导出 CSV';
  final String exportPdf = '导出 PDF 就诊报告';
  final String clearData = '清空全部数据';
  final String clearDataTitle = '清空全部数据？';
  final String clearDataMessage =
      '注射、口服打卡、症状、疗效记录、提醒、方案和自定义药物都会被删除，且无法恢复。内置药物会保留。';
  final String aboutSection = '关于';
  final String disclaimer = '免责声明';
  final String version = '版本';
}

class _Onboarding {
  const _Onboarding();
  final String welcomeTitle = '欢迎使用 BioClock';
  final String welcomeSubtitle = '记录每一次注射，按时提醒，不再靠记忆。';
  final String start = '开始设置';
  final String chooseMedication = '选择你正在使用的药物';
  final String customMedication = '自定义药物';
  final String medicationName = '药物名称';
  final String genericName = '通用名';
  final String defaultDose = '默认剂量';
  final String unit = '单位';
  final String regimenName = '给方案起个名字';
  final String intervalTitle = '注射间隔';
  final String intervalHint = '按医嘱填写，例如每 4 周一次';
  final String loadingDoseTitle = '是否有负荷剂量？';
  final String loadingDoseHint = '例如第 0、1、2 周各一次，之后每 12 周维持';
  final String reminderTitle = '设置提醒时间';
  final String reminderHint = '到点前会发一条本地通知，不会联网。';
  final String restoreTitle = '已经换设备？';
  final String restoreHint = '选择旧设备导出的 BioClock 换机备份（.json），会恢复方案、提醒和全部记录。';
  final String restoreAction = '从备份恢复';
  final String finish = '完成';
}

class _Form {
  const _Form();
  final String injectedAt = '注射时间';
  final String loggedAt = '记录时间';
  final String medicationName = '药物';
  final String dose = '剂量';
  final String unit = '单位';
  final String site = '注射部位';
  final String lotNumber = '批次号';
  final String note = '备注';
  final String severity = '严重程度';
  final String severity1 = '很轻';
  final String severity2 = '较轻';
  final String severity3 = '中等';
  final String severity4 = '较重';
  final String severity5 = '严重';
  final String pain = '疼痛评分';
  final String painHint = 'NRS 0–10：0 为无痛，10 为能想象的最剧烈疼痛。不填表示本次未评估。';
  final String painNone = '无痛';
  final String painMild = '轻度疼痛';
  final String painModerate = '中度疼痛';
  final String painSevere = '重度疼痛';
  final String painClear = '不记录疼痛';
  final String symptomTags = '症状';
  final String manageTags = '管理';
  final String tagManagerTitle = '症状标签';
  final String tagManagerHint = '删除只影响以后的选择，已有记录里的文字不会改变。';
  final String tagAddPlaceholder = '输入症状名称，如 咳嗽';
  final String tagAdd = '添加';
  final String tagDelete = '删除';
  final String tagEmpty = '还没有可选症状，先添加一个。';
  final String tagDuplicate = '这个症状已经存在';
  final String temperature = '体温（℃）';
  final String relatedInjection = '关联注射';
  final String patientName = '姓名';
  final String patientBirthYear = '出生年份';
  final String rangeDays = '时间范围';
}

class _Sites {
  const _Sites();
  final String abdomenUl = '腹部左上';
  final String abdomenUr = '腹部右上';
  final String abdomenLl = '腹部左下';
  final String abdomenLr = '腹部右下';
  final String thighL = '左大腿';
  final String thighR = '右大腿';
  final String armL = '左上臂';
  final String armR = '右上臂';
}

class _Status {
  const _Status();
  final String done = '已完成';
  final String due = '该注射了';
  final String upcoming = '待注射';
  final String overdue = '已逾期';
  final String onTime = '按时';
  final String early = '提前';
  final String late = '延迟';
}

class _DoseStatus {
  const _DoseStatus();
  final String done = '已用';
  final String skipped = '跳过';
  final String missed = '漏用';
}

class _Report {
  const _Report();
  final String status = '状态';
  final String adherenceAllHistory = '依从性统计（全部历史）';
}

class _Disclaimer {
  const _Disclaimer();
  final String title = '免责声明';
  final String short = '本应用仅用于个人记录与提醒，不提供诊断、治疗或用药建议。';
  final String body =
      'BioClock 是一个个人健康记录工具，用于记录注射时间、提醒下次注射并整理症状。\n\n'
      '本应用不提供任何医学诊断、治疗方案、剂量调整或用药建议。所有用药方案、剂量与注射间隔均应由你与医生共同确定，并严格遵照医嘱执行。\n\n'
      '应用内的时间推算与提醒仅供参考，可能因设备时间、系统限制或设置变更而出现偏差。请勿仅依据本应用决定是否用药。\n\n'
      '如有任何身体不适或用药疑问，请及时咨询专业医疗人员。';
  final String accept = '我已阅读并理解';
  final String acceptedAt = '免责声明确认时间';
  final String exportWarning = '该文件包含你的健康信息，请谨慎分享。';
}

class _Notify {
  const _Notify();
  final String channelName = '用药提醒';
  final String refreshFailed = '提醒更新失败，请到设置中检查通知权限并重新保存提醒。';
  final String prepareHint = '请提前 30 分钟取出冷藏药，回温后再注射。';
  final String dueToday = '今天该注射了';
  final String dueTomorrow = '明天该注射了，别忘了提前取出冷藏药';
  final String supplement = '今天还没登记注射，别忘了';
}

class _Errors {
  const _Errors();
  final String generic = '操作失败，请稍后再试';
  final String notFound = '记录不存在';
  final String invalidInput = '输入内容不合法';
  final String database = '数据库操作失败';
}
