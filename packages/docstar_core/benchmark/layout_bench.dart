// Non-gating benchmark: layout of a generated 15-page statement-like document.
//   dart compile exe benchmark/layout_bench.dart -o /tmp/bench && /tmp/bench   (Mac, AOT)
// Android: the spike app runs the same layoutBench() in a release build with
//   --dart-define=BENCH=1 (see research/PROGRESS.md). Soft budget: < 300 ms on the emulator.
import 'package:docstar_core/testing.dart';

// ignore: avoid_print
void main() => print(layoutBench());
