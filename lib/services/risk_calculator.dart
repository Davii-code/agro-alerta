import '../models/mip_parameter_model.dart';

/// Risk bands shown to the producer as a traffic light (RF03).
///
/// The cut-offs are shared with pipeline/ingestion_pipeline.py so the score the
/// app computes locally and the score the pipeline writes to risk_scores land in
/// the same band. Before this existed the app used >=70/>=40 while the pipeline
/// could only ever emit 100 or a value capped at 70, so the two disagreed.
enum RiskBand { green, yellow, red }

const int kYellowThreshold = 40;
const int kRedThreshold = 70;

class RiskAssessment {
  /// 0-100. 100 means the pest count reached or passed the economic threshold.
  final int score;

  /// Economic Injury Level: the count at which control pays for itself.
  final double nde;

  /// Count that produced this assessment.
  final int observedCount;

  final String pestSpecies;
  final MipParameter parameters;

  /// Price per sack used as V in the formula.
  final double marketPrice;

  const RiskAssessment({
    required this.score,
    required this.nde,
    required this.observedCount,
    required this.pestSpecies,
    required this.parameters,
    required this.marketPrice,
  });

  RiskBand get band {
    if (score >= kRedThreshold) return RiskBand.red;
    if (score >= kYellowThreshold) return RiskBand.yellow;
    return RiskBand.green;
  }

  /// Wording aimed at a producer, not an agronomist.
  String get headline {
    switch (band) {
      case RiskBand.red:
        return 'APLICAR AGORA';
      case RiskBand.yellow:
        return 'FICAR DE OLHO';
      case RiskBand.green:
        return 'TUDO CERTO';
    }
  }

  String get advice {
    switch (band) {
      case RiskBand.red:
        return 'A praga passou do ponto em que o controle se paga. '
            'Fale com seu extensionista hoje.';
      case RiskBand.yellow:
        return 'A contagem está subindo. Refaça a contagem em 3 dias.';
      case RiskBand.green:
        return 'Nenhuma ação necessária. Continue monitorando toda semana.';
    }
  }

  /// One plain sentence explaining where the number came from.
  String get explanation =>
      'Você contou $observedCount. O prejuízo começa em ${nde.toStringAsFixed(0)}.';
}

/// Pure Economic Injury Level maths. No I/O, no Flutter, no Supabase - the whole
/// point of extracting it out of HomeScreen is that the formula can be reasoned
/// about and tested on its own.
class RiskCalculator {
  const RiskCalculator();

  /// NDE = (C x K) / (V x I)
  ///
  ///   C = control cost per hectare (R$)
  ///   K = expected efficacy of the control (0-1)
  ///   V = market value of one sack (R$)
  ///   I = injury coefficient (loss in sacks per pest unit per hectare)
  ///
  /// Returns the pest count above which spraying is cheaper than the loss.
  static double economicInjuryLevel({
    required double controlCost,
    required double efficacy,
    required double marketPrice,
    required double injuryFactor,
  }) {
    final denominator = marketPrice * injuryFactor;
    if (denominator <= 0) {
      // A missing or zero price would make the NDE infinite and paint every
      // field green. Refuse instead, so the caller can show "sem dados".
      return double.infinity;
    }
    return (controlCost * efficacy) / denominator;
  }

  /// Converts an observed count into the 0-100 score stored in risk_scores.
  ///
  /// The scale is linear up to the threshold and saturates at 100 once reached,
  /// so "100" always means exactly one thing: control is economically justified.
  static int scoreFor({required int count, required double nde}) {
    if (!nde.isFinite || nde <= 0) return 0;
    if (count <= 0) return 0;
    if (count >= nde) return 100;
    return ((count / nde) * 100).round().clamp(1, 99);
  }

  RiskAssessment assess({
    required int count,
    required String pestSpecies,
    required MipParameter parameters,
    required double marketPrice,
  }) {
    final nde = economicInjuryLevel(
      controlCost: parameters.controlCostPerHa,
      efficacy: parameters.efficacyFactor,
      marketPrice: marketPrice,
      injuryFactor: parameters.injuryFactor,
    );

    return RiskAssessment(
      score: scoreFor(count: count, nde: nde),
      nde: nde,
      observedCount: count,
      pestSpecies: pestSpecies,
      parameters: parameters,
      marketPrice: marketPrice,
    );
  }
}
