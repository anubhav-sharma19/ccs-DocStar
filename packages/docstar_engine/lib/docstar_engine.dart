/// Dart port of the DocStar Python statement engine. See docs/PORT_PLAN.md.
library;

export 'src/dec.dart' show Dec;
export 'src/engine.dart' show parseDocument, Banks;
export 'src/extract.dart' show Document, Page, Line, Word, loadWords, dumpWords, buildLines, makeDocument, unreadable, noOcrNotice;
