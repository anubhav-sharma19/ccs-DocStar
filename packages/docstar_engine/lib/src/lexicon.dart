/// Multilingual vocabulary for column headers, special rows, stop markers and page furniture.
///
/// Name table (Python -> Dart): header_role -> headerRole, HEADER_ROLES -> headerRoles,
/// _PHRASES -> phrases, WEAK_TOKENS -> weakTokens; the `*_RX` constants become `*Rx`.
library;

import 'fold_table.dart';
import 'py.dart';

bool _isCombining(int c) =>
    (c >= 0x300 && c <= 0x36f) ||
    (c >= 0x1ab0 && c <= 0x1aff) ||
    (c >= 0x1dc0 && c <= 0x1dff) ||
    (c >= 0x20d0 && c <= 0x20ff) ||
    (c >= 0xfe20 && c <= 0xfe2f);

final _ws = RegExp(r'\s+');

/// Lower-case, strip accents and mojibake, collapse whitespace.
String norm(String s) {
  s = s.replaceAll('`', 'a').replaceAll(']', 't').replaceAll('[', 's'); // RO mojibake seen in Raiffeisen
  final b = StringBuffer();
  for (final r in s.runes) {
    if (_isCombining(r)) continue;
    b.write(foldTable[r] ?? String.fromCharCode(r));
  }
  // the fold can itself leave combining marks only if the table had them; it does not
  return b.toString().toLowerCase().replaceAll('­', '').replaceAll(_ws, ' ').trim();
}

final _notAlnum = RegExp(r'[^a-z0-9#]');

/// norm() then drop everything but letters/digits - for glued / letter-spaced headers.
String squash(String s) => norm(s).replaceAll(_notAlnum, '');

// ---------------------------------------------------------------- column header roles
/// Longest phrases first inside each role. Matching is done on squashed text.
const headerRoles = <String, List<String>>{
  'vdate': [
    'value date', 'value dt', 'valuedate', 'date valeur', 'valeur', 'valuta', 'effective date',
    'settlement date', 'date paid', 'data tranzactiei', 'val date', 'post date', 'posting date', 'value',
  ],
  'date': [
    'transaction date', 'tran date', 'txn date', 'trans date', 'trans. date', 'booking date',
    'date posted', 'date ope', 'date', 'dia', 'data', 'datum', 'fecha', 'data inregistrare',
  ],
  'desc': [
    'transaction details', 'transaction description', 'description of transaction',
    'payment type and details', 'nature de l operation', 'libelle des operations',
    'descrizione', 'descrierea tranzactiei', 'historico', 'narration', 'particulars',
    'description', 'details', 'remarks', 'libelle', 'transaction', 'transactions', 'activity',
    'item description', 'item', 'operation details', 'beneficiary name', 'memo', 'operation',
    'transaction detail', 'transaction type and details', 'description of transaction or credit',
  ],
  'ref': [
    'chq./ref.no.', 'chq/ref no', 'chq ref no', 'ref/cheque no.', 'ref cheque no', 'cheque no',
    'chq no', 'chq. no', 'instrument no', 'check number', 'check #', 'serial #', 'ref number',
    'bank reference number', 'reference', 'ref no', 'ref', 'tran id', 'transaction id',
    'skrill id', 'number', 'no.',
  ],
  'debit': [
    'withdrawal amt.', 'withdrawal amt', 'withdrawals (inr)', 'withdrawals', 'withdrawal',
    'amounts withdrawn', 'paid out', 'money out', 'funds out', 'pay out', 'payments', 'debits',
    'debit', 'withdrawn', 'uscite', 'suma debit', 'sum debit', 'deb amt', 'debit amt', 'out', 'dr', '(-)',
  ],
  'credit': [
    'deposit amt.', 'deposit amt', 'deposits (inr)', 'deposits', 'deposit', 'amounts deposited',
    'paid in', 'money in', 'funds in', 'pay in', 'receipts', 'credits', 'credit', 'entrate',
    'suma credit', 'sum credit', 'in', 'cr', '(+)',
  ],
  'amount': ['transaction amount', 'amount', 'valor', 'montant', 'betrag', 'importe', 'net amount'],
  'balance': [
    'end of day account balance', 'ending daily balance', 'running balance', 'closing balance',
    'balance in original currency', 'balance', 'available', 'solde', 'saldo', 'bal', 'totals',
  ],
  'type': ['transaction type', 'tran type', 'type', 'mode', 'code', 'channel', 'category', 'cat'],
  'branch': ['init. br', 'init br', 'init.', 'branch', 'br'],
  'fee': ['accrued bank charges', 'charges', 'fee', 'fees'],
  'other': ['status', 'ccy', 'fx rate', 'recipient', 'notes', 'no', 'sr. no', 'sr no'],
};

/// words that only qualify a neighbouring header word ("Amt.", "(INR)", "($)", "Dt")
final headerModifiers = RegExp(
    r'^(amt\.?|\(?(inr|rs\.?|usd|gbp|eur|aud|cad|zar|ngn|\$|£|€|r)\)?|dt\.?|no\.?|\(\$\)|\(£\)|\(r\)|#)$',
    caseSensitive: false);

/// squashed phrase -> role, longest first (stable, so role order breaks ties like Python)
final List<(String, String)> phrases = () {
  final l = [
    for (final e in headerRoles.entries) for (final p in e.value) (squash(p), e.key),
  ];
  stableSort(l, (a, b) => b.$1.length - a.$1.length);
  return l;
}();

/// short tokens that are only header words when the line already looks like a header
const weakTokens = {'in', 'out', 'dr', 'cr', 'no', 'br', 'ref', 'type', 'code', 'item', 'data', 'dia', 'bal', 'cat', 'init'};

/// Return the column role for a header cell text, or null.
String? headerRole(String text) {
  final s = squash(text);
  if (s.isEmpty) return null;
  for (final (p, r) in phrases) {
    if (s == p) return r;
  }
  // allow modifiers: 'withdrawalamtinr' etc.
  for (final (p, r) in phrases) {
    if (p.length >= 4 && s.startsWith(p) && s.length - p.length <= 6) return r;
  }
  // compound labels: 'Deposits/Additions', 'Debit (€)', 'Withdrawals & Debits'
  final parts = norm(text).split(RegExp(r'[/&(]|\band\b'));
  if (parts.length > 1) {
    final r = headerRole(parts[0]);
    if (r != null) return r;
  }
  return null;
}

const numericRoles = {'debit', 'credit', 'amount', 'balance', 'fee'};
const textRoles = {'desc', 'ref', 'type', 'branch', 'other'};
const dateRoles = {'date', 'vdate'};

RegExp _i(String p) => RegExp(p, caseSensitive: false);

// ---------------------------------------------------------------- special rows
final openRx = _i(
    r'^\s*(?:\d+\s+)?(opening\s+bal(ance)?|statement\s+opening\s+balance|balance\s+b(rought|right)\s+f(orwar)?d|brought\s+forward|'
    r'b\s*/\s*f\b|balance\s+b/f|balance\s+forward|previous\s+balance|beginning\s+balance|start(ing)?\s+balance|'
    r'balance\s+last\s+statement|balance\s*-\s*previous\s+statement|former\s+balance|total\s+opening\s+balance|'
    r'saldo\s+anterior|ancien\s+solde|solde\s+prec[ea]dent|saldo\s+iniziale|sold\s+initial|'
    r'balance\s+on\s+\d|your\s+opening\s+balance)');
final closeRx = _i(
    r'^\s*(closing\s+bal(ance)?|balance\s+carried\s+forward|carried\s+forward|c\s*/\s*f\b|ending\s+balance|'
    r'new\s+balance|end(ing)?\s+balance|end\s+balance|balance\s+this\s+statement|closing\s+available\s+balance|'
    r'nouveau\s+solde|saldo\s+finale|sold\s+final|s\s*a\s*l\s*d\s*o\b|your\s+new\s+balance|total\s+closing\s+balance|'
    r'your\s+closing\s+balance|balance\s+received\s+forward)');
final totalRx = _i(
    r'^\s*(transaction\s+total|totals?\b|grand\s+total|sub\s*-?\s*total|totaux|total\s+des\s+op|'
    r'totals?\s+at\s+end\s+of\s+(page|period)|total\s+movements|statement\s+summary|turnover|'
    r'total\s+(debits?|credits?|withdrawals?|deposits?)|total\s+transactions|statement\s+period\s+total|'
    r'(year|period)[\s-]+to[\s-]+date\s+total|.*\b(sub)?totals?\s*:?\s*$)');
final dailyRx = _i(r'(soldul\s+zilei|\*+\s*solde\s+au|daily\s+balance|end\s+of\s+day\s+balance)');

/// lines that end the transaction table (until a new column header appears)
final stopRx = _i(
    r'(charge\s+break\s*-?\s*up|statement\s+legends?|abbreviations?\b|transaction\s+types?\s+key|'
    r'important\s+(information|notes|notice|messages)|end\s+of\s+statement|computer\s+generated\s+statement|'
    r'this\s+is\s+a\s+(computer|system)\s+generated|in\s+case\s+of\s+errors|error\s+resolution|'
    r'checks?\s+(paid|by\s+serial|outstanding)|daily\s+(ending\s+)?balance\s+(summary|detail)|balance\s+summary|'
    r'fee\s+summary|fees\s+explained|interest\s+charge\s+calculation|worksheet|privacy\s+notice|'
    r'summary\s+of\s+(checks|overdraft|government)|reward\s+points|deposit\s+(guarantee|protection)|'
    r'transactions\s+not\s+yet\s+processed|overdraft\s+and\s+return(ed)?\s+item\s+fees|statement\s+summary|'
    r'generated\s+on\s*:|account\s+summary\s*$|balance\s+activity|interest\s+summary|check\s+images|'
    r'service\s+charge\s+(summary|explanation)|transaction\s+type\s+key)');

final pageMarkerRx = _i(
    r'^\s*(page\s*(no\.?)?\s*:?\s*\d+(\s*(of|/)\s*\(?\d+\)?)?|\d+\s*(of|/)\s*\d+|p\.\s*\d+\s*/\s*\d+|'
    r'pagina\s*\d+(\s*(di|/)\s*\d+)?|sheet\s+\d+\s+of\s+\d+|statement\s+page\s+\d+.*|envoi\s+n.*p\.\s*\d+/\d+)\s*$');
final continuedRx = _i(
    r"(continued\s+(on|over)\s+(the\s+)?next\s+page|statement\s+continued|\(cont(inued|'d|\.)\)|"
    r"\bcont'd\b|continued\.{2,}|continued\s*>+|please\s+turn\s+over|see\s+reverse|\(cont\.\))");
final synthWatermarkRx = _i(r'synthetic\s+sample');

/// section headings that set direction for single-amount layouts
final sectionCreditRx = _i(
    r'^\s*(?:\d+\s+)?(deposits?|deposits?\s+(and|&)\s+(other\s+)?(credits?|additions)|other\s+credits|electronic\s+deposits|credits?|money\s+in|additions|income)(\s*\(?\+\)?)?(\s*\(?continued\)?)?\s*:?\s*$');
final sectionDebitRx = _i(
    r'^\s*(?:\d+\s+)?(withdrawals?|withdrawals?\s+(and|&)\s+(other\s+)?(debits?|subtractions|deductions)|other\s+(debits|withdrawals|subtractions|deductions)|'
    r'electronic\s+(payments|withdrawals)|atm\s*(&|and)?\s*debit\s+card|debit\s+card\s+purchases|card\s+withdrawals|checks|'
    r'cheques|fees|service\s+fees|payments|purchases|money\s+out|subtractions|charges)(\s*(and|&)\s*(other\s+)?(debits|withdrawals|deductions|subtractions))?'
    r'(\s*\(?-\)?)?(\s*\(?continued\)?)?\s*:?\s*$');

/// Summary labels (statement-level totals, usually outside the table)
final summaryLabels = <String, RegExp>{
  'open': _i(r'(opening\s+bal(ance)?|beginning\s+balance|previous\s+balance|start\s+balance|balance\s+forward|ancien\s+solde|saldo\s+anterior|sold\s+initial|former\s+balance|balance\s+last\s+statement)'),
  'credits': _i(r'(total\s+credits?|credits?\s+(this\s+period)?|deposits?\s*(&|and)?\s*(other\s+)?(credits|additions)?|total\s+deposits|money\s+in|paid\s+in|payments\s+in|rulaj\s+creditor|total\s+money\s+in|entrate)'),
  'debits': _i(r'(total\s+debits?|debits?\s+(this\s+period)?|withdrawals?\s*(&|and)?\s*(other\s+)?(debits|subtractions|deductions)?|total\s+withdrawals|money\s+out|paid\s+out|withdrawn|payments\s+out|rulaj\s+debitor|total\s+money\s+out|uscite)'),
  'close': _i(r'(closing\s+bal(ance)?|ending\s+balance|new\s+balance|end\s+balance|closing\s+balance|nouveau\s+solde|sold\s+final|current\s+balance|balance\s+this\s+statement)'),
  'dr_count': _i(r'(dr\s+count|no\.?\s+debit\s+transactions|#\s*of\s+debit)'),
  'cr_count': _i(r'(cr\s+count|no\.?\s+credit\s+transactions|#\s*of\s+credit)'),
};

final reversalRx = _i(r'(^rev[-\s/]|reversal|reversed|\brev\b|cradj|refund|chargeback|charge\s+back)');
final cancelledRx = _i(r'\b(canceled|cancelled|failed|declined)\b');

const currencySymbols = {'₹': 'INR', r'$': 'USD', '£': 'GBP', '€': 'EUR', 'R': 'ZAR', '₦': 'NGN', '¥': 'JPY'};

const months = <String, int>{
  // en
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9,
  'oct': 10, 'nov': 11, 'dec': 12,
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'june': 6, 'july': 7, 'august': 8,
  'september': 9, 'october': 10, 'november': 11, 'december': 12,
  // fr
  'janv': 1, 'fevr': 2, 'fev': 2, 'mars': 3, 'avr': 4, 'avril': 4, 'mai': 5, 'juin': 6, 'juil': 7, 'aout': 8,
  'janvier': 1, 'fevrier': 2, 'juillet': 7, 'septembre': 9, 'octobre': 10, 'novembre': 11, 'decembre': 12,
  // es / pt / it / de / ro (short forms that don't collide)
  'ene': 1, 'abr': 4, 'ago': 8, 'dic': 12, 'dez': 12, 'gen': 1, 'giu': 6, 'lug': 7,
  'okt': 10, 'mrz': 3, 'iun': 6, 'iul': 7,
};
