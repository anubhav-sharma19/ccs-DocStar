import 'package:docstar_engine/src/lexicon.dart';
import 'package:test/test.dart';

void main() {
  test('norm folds accents, mojibake, compat forms and whitespace', () {
    expect(norm("  Sold  INIȚIAL `ăț "), 'sold initial aat'); // T3 RO mojibake
    expect(norm('Débit  Crédit'), 'debit credit');
    expect(norm('ﬁne ½ ²'), 'fine 1⁄2 2');
    expect(norm('é'), 'e'); // already-decomposed accent
    expect(squash('Des c ription (INR)'), 'descriptioninr'); // F7
  });

  group('headerRole', () {
    const cases = {
      'Date': 'date', 'Withdrawal Amt.': 'debit', 'Value Dt': 'vdate', 'Chq./Ref.No.': 'ref',
      'Closing Balance': 'balance', 'Deposits/Additions': 'credit', 'Debit (€)': 'debit',
      'Des c ription': 'desc', 'Libellé des opérations': 'desc', 'Descrierea tranzacției': 'desc',
      'Débit': 'debit', 'Montant': 'amount', 'Narration': 'desc', 'Dr': 'debit', 'Paid In': 'credit',
      'Withdrawals & Debits': 'debit', 'Datum': 'date', 'Solde': 'balance',
    };
    cases.forEach((t, r) => test(t, () => expect(headerRole(t), r)));
    test('unknown and glued words', () {
      expect(headerRole('Foo'), isNull);
      expect(headerRole('DateParticulars'), isNull); // split by layout._splitGlued, not here
    });
  });

  test('special-row, section and furniture patterns', () {
    // text -> [open, close, total, sectionCredit, sectionDebit, pageMarker, continued]
    final cases = <String, List<bool>>{
      'Opening Balance': [true, false, false, false, false, false, false],
      'Balance B/F': [true, false, false, false, false, false, false],
      'Ancien solde': [true, false, false, false, false, false, false],
      'Saldo Anterior': [true, true, false, false, false, false, false], // 'saldo' also matches the s a l d o closing form
      'TRANSACTION TOTAL': [false, false, true, false, false, false, false],
      'Totals at end of page': [false, false, true, false, false, false, false],
      'Closing balance': [false, true, false, false, false, false, false],
      'Deposits': [false, false, false, true, false, false, false],
      'Withdrawals (continued)': [false, false, false, false, true, false, true],
      'Page 2 of 5': [false, false, false, false, false, true, false], // F8
      '2/4': [false, false, false, false, false, true, false],
      'Pagina 1 di 8': [false, false, false, false, false, true, false],
      'Sheet 00001 of 00003': [false, false, false, false, false, true, false],
      'continued on next page': [false, false, false, false, false, false, true], // F9
    };
    cases.forEach((t, want) {
      final got = [
        openRx.hasMatch(t), closeRx.hasMatch(t), totalRx.hasMatch(t), sectionCreditRx.hasMatch(t),
        sectionDebitRx.hasMatch(t), pageMarkerRx.hasMatch(t), continuedRx.hasMatch(t),
      ];
      expect(got, want, reason: t);
    });
  });
}
