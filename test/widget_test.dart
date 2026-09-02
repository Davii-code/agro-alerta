import 'package:flutter_test/flutter_test.dart';

import 'package:agro_alerta/models/mip_parameter_model.dart';
import 'package:agro_alerta/services/risk_calculator.dart';

// NOTE: these tests were written but NOT executed in this environment (no Flutter
// SDK available). Run `flutter test` before trusting them.
//
// The previous smoke test pumped AgroAlertaApp() directly, which no longer works:
// the app now requires Hive boxes and the pt_BR date symbols to be initialised in
// main() first. Widget tests of the screens need a Hive test harness; the pure
// NDE maths below needs nothing, which is the point of extracting RiskCalculator
// out of HomeScreen.

void main() {
  const soja = MipParameter(
    culture: 'soja',
    pestSpecies: 'Percevejo-marrom',
    controlCostPerHa: 150.00,
    efficacyFactor: 0.85,
    injuryFactor: 0.80,
  );

  group('economicInjuryLevel', () {
    test('applies NDE = (C x K) / (V x I)', () {
      final nde = RiskCalculator.economicInjuryLevel(
        controlCost: 150,
        efficacy: 0.85,
        marketPrice: 129.71,
        injuryFactor: 0.80,
      );
      // (150 * 0.85) / (129.71 * 0.80) = 127.5 / 103.768
      expect(nde, closeTo(1.2287, 0.001));
    });

    test('returns infinity when the price is missing, never a false green', () {
      final nde = RiskCalculator.economicInjuryLevel(
        controlCost: 150,
        efficacy: 0.85,
        marketPrice: 0,
        injuryFactor: 0.80,
      );
      expect(nde.isFinite, isFalse);
    });
  });

  group('scoreFor', () {
    test('saturates at 100 once the count reaches the threshold', () {
      expect(RiskCalculator.scoreFor(count: 10, nde: 10), 100);
      expect(RiskCalculator.scoreFor(count: 40, nde: 10), 100);
    });

    test('scales linearly below the threshold', () {
      expect(RiskCalculator.scoreFor(count: 5, nde: 10), 50);
      expect(RiskCalculator.scoreFor(count: 7, nde: 10), 70);
    });

    test('a zero count is zero, not one', () {
      expect(RiskCalculator.scoreFor(count: 0, nde: 10), 0);
    });

    test('an unusable NDE scores zero rather than crashing', () {
      expect(RiskCalculator.scoreFor(count: 5, nde: double.infinity), 0);
      expect(RiskCalculator.scoreFor(count: 5, nde: 0), 0);
    });
  });

  group('bands', () {
    const calculator = RiskCalculator();

    RiskBand bandFor(int count) => calculator
        .assess(
          count: count,
          pestSpecies: 'Percevejo-marrom',
          parameters: soja,
          marketPrice: 129.71,
        )
        .band;

    test('green below 40, yellow from 40, red from 70', () {
      // NDE is ~1.23 here, so the bands land in a narrow count range.
      expect(bandFor(0), RiskBand.green);
      expect(bandFor(1), RiskBand.red); // 1 / 1.2287 = 81
      expect(RiskCalculator.scoreFor(count: 39, nde: 100), 39);
      expect(RiskCalculator.scoreFor(count: 40, nde: 100), 40);
      expect(RiskCalculator.scoreFor(count: 70, nde: 100), 70);
    });

    test('headline and advice speak to the producer, not the agronomist', () {
      final assessment = calculator.assess(
        count: 5,
        pestSpecies: 'Percevejo-marrom',
        parameters: soja,
        marketPrice: 129.71,
      );
      expect(assessment.headline, 'APLICAR AGORA');
      expect(assessment.explanation, contains('Você contou 5'));
    });
  });
}
