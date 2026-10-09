import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agro_alerta/models/field_model.dart';
import 'package:agro_alerta/models/mip_parameter_model.dart';
import 'package:agro_alerta/services/risk_calculator.dart';
import 'package:agro_alerta/widgets/counter_input.dart';
import 'package:agro_alerta/widgets/field_card.dart';
import 'package:agro_alerta/widgets/pest_selector.dart';

/// Layout checks at a real phone size.
///
/// The app is used on a phone in a field, and the widest strings - a long
/// talhão name, a long price source, the longest pest label - are the ones that
/// overflow. flutter_test turns a RenderFlex overflow into a test failure, so
/// pumping each widget at 412x915 with its worst-case text is enough to catch
/// the class of bug that only shows as a yellow-and-black bar on a device.
void main() {
  // Pixel 7 logical size, the reference phone for this app.
  const phone = Size(412, 915);

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.physicalSize = phone * view.devicePixelRatio;
    view.devicePixelRatio = view.devicePixelRatio;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      );

  FieldModel field(String name) => FieldModel(
        id: 'f1',
        producerId: 'p1',
        name: name,
        cropType: 'algodao',
        plantingDate: DateTime(2026, 1, 1),
        latitude: -16.32,
        longitude: -48.95,
        createdAt: DateTime(2026, 1, 1),
      );

  const parameters = MipParameter(
    culture: 'algodao',
    pestSpecies: 'Bicudo-do-algodoeiro',
    controlCostPerHa: 200.00,
    efficacyFactor: 0.85,
    injuryFactor: 2.50,
  );

  group('FieldCard at 412x915', () {
    testWidgets('fits with no sampling yet', (tester) async {
      await tester.pumpWidget(host(FieldCard(
        field: field('Talhão do fundo'),
        assessment: null,
        onCount: () {},
        onDelete: () {},
      )));

      expect(find.text('Talhão do fundo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits with a red assessment and the longest pest name',
        (tester) async {
      await tester.pumpWidget(host(FieldCard(
        field: field('Talhão do fundo'),
        assessment: const RiskAssessment(
          score: 100,
          nde: 0.83,
          observedCount: 12,
          pestSpecies: 'Bicudo-do-algodoeiro',
          parameters: parameters,
          marketPrice: 136.75,
        ),
        onCount: () {},
        onDelete: () {},
      )));

      expect(tester.takeException(), isNull);
    });

    testWidgets('fits with a name far longer than the card', (tester) async {
      await tester.pumpWidget(host(FieldCard(
        field: field(
          'Talhão da divisa com a fazenda do vizinho lá de cima do morro',
        ),
        assessment: null,
        onCount: () {},
        onDelete: () {},
      )));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the delete button is there and reports the tap',
        (tester) async {
      var deleted = false;
      await tester.pumpWidget(host(FieldCard(
        field: field('Talhão do fundo'),
        assessment: null,
        onCount: () {},
        onDelete: () => deleted = true,
      )));

      await tester.tap(find.byTooltip('Excluir talhão'));
      await tester.pump();

      expect(deleted, isTrue);
    });
  });

  group('CounterInput at 412x915', () {
    testWidgets('fits and the shortcuts add up', (tester) async {
      var value = 0;
      await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => CounterInput(
          value: value,
          unitLabel: 'insetos por planta',
          onChanged: (v) => setState(() => value = v),
        ),
      )));

      await tester.tap(find.text('+10'));
      await tester.pump();
      await tester.tap(find.text('+5'));
      await tester.pump();

      expect(value, 15);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a three-digit count still fits', (tester) async {
      await tester.pumpWidget(host(CounterInput(
        value: 999,
        unitLabel: 'insetos por planta',
        onChanged: (_) {},
      )));

      expect(find.text('999'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not go below the minimum', (tester) async {
      var value = 0;
      await tester.pumpWidget(host(CounterInput(
        value: value,
        unitLabel: 'insetos por planta',
        onChanged: (v) => value = v,
      )));

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(value, 0);
    });
  });

  group('PestSelector at 412x915', () {
    testWidgets('every option fits and the tap reports the species',
        (tester) async {
      String? picked;
      await tester.pumpWidget(host(PestSelector(
        selectedSpecies: 'Lagarta-da-soja',
        onChanged: (s) => picked = s,
      )));

      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Percevejo marrom'));
      await tester.pump();

      expect(picked, isNotNull);
    });
  });
}
