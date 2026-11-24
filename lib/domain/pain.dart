/// 临床疼痛评分（NRS 0–10）分档工具，只用于展示与配色，不构成医学判断。
library;

enum PainBand {
  none('none'),
  mild('mild'),
  moderate('moderate'),
  severe('severe');

  const PainBand(this.wire);
  final String wire;
}

const int painMin = 0;
const int painMax = 10;

const List<PainBand> painBandValues = [
  PainBand.none,
  PainBand.mild,
  PainBand.moderate,
  PainBand.severe,
];

PainBand painBand(int score) {
  if (score <= 0) return PainBand.none;
  if (score <= 3) return PainBand.mild;
  if (score <= 6) return PainBand.moderate;
  return PainBand.severe;
}
