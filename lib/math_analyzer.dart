import 'dart:math' as math;
import 'package:math_expressions/math_expressions.dart';
import 'package:flutter/material.dart';

class MathAnalyzer {
  /// 특정 수식의 화면 내 x절편(근)들을 찾아내는 함수 (기울기 연동형 초정밀 버전)
  /// 특정 수식의 화면 내 x절편(근)들을 찾아내는 함수 (초정밀 & 성능 최적화 하이브리드 버전)
  static List<double> findXIntercepts({
    required Expression expression,
    required double startX,
    required double endX,
    required double paramA,
    required double currentScale,
  }) {
    List<double> roots = [];
    final ContextModel context = ContextModel();
    context.bindVariable(Variable('a'), Number(paramA));

    final Expression derivExp = expression.derive('x');

    // ⭐️ [성능 최적화의 핵심]
    // 수식 문자열을 파악하여 탄젠트(tan)나 고주파 진동 함수(sin(1/x) 등)가 아닌
    // 일반적인 다항식 기반의 함수라면, 전체 구간 스캔 스텝을 굳이 쪼개지 않고 원래의 효율적인 속도(baseStep)를 유지합니다.
    // 어차피 구간만 발견하면 우리가 만든 기호미분 뉴턴-랩슨이 1e-15 레벨로 정밀하게 쪼여주기 때문입니다!
    String exprStr = expression.toString().replaceAll(
      ' ',
      '',
    ); // // [cite: 729]
    bool isComplexOscillation =
        exprStr.contains('tan') ||
        exprStr.contains('sin(') ||
        exprStr.contains('cos('); // // [cite: 730, 731]

    double baseStep = (2.0 / currentScale).clamp(0.01, 0.5); // // [cite: 731]
    double step = baseStep; // // [cite: 731]

    if (isComplexOscillation) {
      context.bindVariable(Variable('x'), Number(0.0)); // // [cite: 731]
      double slopeSample = 1.0; // // [cite: 731]
      try {
        // 💥 [대완치 가드]: abs나 sqrt가 엮여 미분 계수가 부호 폭주를 일으킬 때
        // NaN이나 예외로 인해 전체 루프 오프셋이 -1로 오염되는 현상을 완벽하게 방어합니다.
        var evaluatedSample = derivExp.evaluate(EvaluationType.REAL, context);
        if (evaluatedSample != null &&
            !evaluatedSample.isNaN &&
            !evaluatedSample.isInfinite) {
          slopeSample = evaluatedSample.abs();
          if (slopeSample > 1.0) {
            step = (baseStep / slopeSample).clamp(
              0.00005,
              0.5,
            ); // // [cite: 732]
          }
        }
      } catch (_) {
        step = baseStep; // 에러 발생 시 안전하게 기본 스텝으로 폴백하여 싱크홀 차단
      }
    }

    // 극단적인 삼각함수 고주파 진동이 일어날 때만 동적 스텝을 발동시켜 연산 낭비를 막습니다.
    if (isComplexOscillation) {
      context.bindVariable(Variable('x'), Number(0.0));
      double slopeSample = 1.0;
      try {
        slopeSample = derivExp.evaluate(EvaluationType.REAL, context).abs();
        if (!slopeSample.isNaN &&
            !slopeSample.isInfinite &&
            slopeSample > 1.0) {
          step = (baseStep / slopeSample).clamp(0.00005, 0.5); // 하한선을 현실적으로 조정
        }
      } catch (_) {}
    }

    double prevX = startX;
    double? prevY = _evaluate(expression, prevX, context);
    double? prevDeriv = _evaluate(derivExp, prevX, context);

    for (double x = startX + step; x <= endX; x += step) {
      double? currentY = _evaluate(expression, x, context);
      double? currentDeriv = _evaluate(derivExp, x, context);

      if (prevY != null && currentY != null && (prevY * currentY) <= 0) {
        double? exactRoot = _bisectionMethod(
          expression: expression,
          context: context,
          leftX: prevX,
          rightX: x,
        );
        if (exactRoot != null && !exactRoot.isNaN) {
          if (roots.isEmpty || (roots.last - exactRoot).abs() > 0.01) {
            roots.add(exactRoot);
          }
        }
      } else if (prevDeriv != null &&
          currentDeriv != null &&
          (prevDeriv * currentDeriv) <= 0) {
        double? potentialRootX = _bisectionDerivative(
          expression: expression,
          context: context,
          leftX: prevX,
          rightX: x,
        );
        if (potentialRootX != null) {
          double? yAtExtremum = _evaluate(expression, potentialRootX, context);
          if (yAtExtremum != null && yAtExtremum.abs() < 0.01) {
            if (roots.isEmpty || (roots.last - potentialRootX).abs() > 0.01) {
              roots.add(potentialRootX);
            }
          }
        }
      }

      prevX = x;
      prevY = currentY;
      prevDeriv = currentDeriv;
    }

    return roots;
  }

  /// 내부 헬퍼: 이분법 알고리즘 (x 구간 오차를 극도로 좁힌 버전)
  static double? _bisectionMethod({
    required Expression expression,
    required ContextModel context,
    required double leftX,
    required double rightX,
  }) {
    double left = leftX;
    double right = rightX;
    // y값 기준(tolerance)을 없애고, x구간 기준 오차를 타이트하게 잡습니다.
    final double xTolerance = 0.0000001;
    final int maxIterations = 60; // 반복 횟수 넉넉하게 증가

    for (int i = 0; i < maxIterations; i++) {
      double mid = (left + right) / 2.0;
      double midY = _evaluate(expression, mid, context) ?? 0.0;

      // y가 완벽한 0이거나, x구간이 극한으로 좁혀질 때만 종료! (게으름 방지)
      if (midY == 0.0 || (right - left) / 2.0 < xTolerance) {
        return mid;
      }

      double leftY = _evaluate(expression, left, context) ?? 0.0;
      if ((leftY * midY) < 0) {
        right = mid;
      } else {
        left = mid;
      }
    }
    return (left + right) / 2.0;
  }

  /// 내부 헬퍼: 수식 안전하게 계산하기
  static double? _evaluate(Expression exp, double x, ContextModel ctx) {
    ctx.bindVariable(Variable('x'), Number(x));
    try {
      double res = exp.evaluate(EvaluationType.REAL, ctx);
      if (res.isNaN || res.isInfinite) return null;
      return res;
    } catch (e) {
      return null;
    }
  }

  /// 특정 수식의 y절편 (x=0 일 때의 y값)을 찾는 함수
  static double? findYIntercept({
    required Expression expression,
    required double paramA,
  }) {
    final ContextModel context = ContextModel();
    context.bindVariable(Variable('a'), Number(paramA));

    // x에 0.0을 대입하여 계산
    return _evaluate(expression, 0.0, context);
  }

  // ==========================================================
  // [추가할 극점 분석 로직]
  // ==========================================================

  /// 특정 수식의 극점(극대/극소)의 x좌표들을 찾아내는 함수
  static List<double> findExtrema({
    required Expression expression,
    required double startX,
    required double endX,
    required double paramA,
    required double currentScale, // 👈 화면 스케일 추가
  }) {
    List<double> extrema = [];
    final ContextModel context = ContextModel();
    context.bindVariable(Variable('a'), Number(paramA));

    // ⭐️ 줌 상태에 따라 계산 정밀도를 유동적으로 조절 (2~4픽셀당 1회 계산)
    double step = (2.0 / currentScale).clamp(0.01, 0.5);

    double prevX = startX;
    double? prevDeriv = _evaluateDerivative(expression, prevX, context);

    for (double x = startX + step; x <= endX; x += step) {
      double? currentDeriv = _evaluateDerivative(expression, x, context);

      // 기울기의 부호가 바뀌었다면? (올라가다 내려감 OR 내려가다 올라감) -> 극점 존재!
      if (prevDeriv != null &&
          currentDeriv != null &&
          (prevDeriv * currentDeriv) <= 0) {
        // 기울기가 정확히 0이 되는 x좌표 추적
        double? exactExtremum = _bisectionDerivative(
          expression: expression,
          context: context,
          leftX: prevX,
          rightX: x,
        );

        if (exactExtremum != null && !exactExtremum.isNaN) {
          // 점근선(예: 1/x^2)에서 기울기가 부호가 바뀌는 가짜 극점 걸러내기
          double? validY = _evaluate(expression, exactExtremum, context);
          if (validY != null) {
            if (extrema.isEmpty ||
                (extrema.last - exactExtremum).abs() > 0.01) {
              extrema.add(exactExtremum);
            }
          }
        }
      }
      prevX = x;
      prevDeriv = currentDeriv;
    }
    return extrema;
  }

  /// 내부 헬퍼: 특정 x 지점의 미분계수(기울기) 계산 (중앙차분법)
  static double? _evaluateDerivative(
    Expression exp,
    double x,
    ContextModel ctx,
  ) {
    final double h = 0.0001; // 미세한 x 변화량
    double? yPlus = _evaluate(exp, x + h, ctx);
    double? yMinus = _evaluate(exp, x - h, ctx);
    if (yPlus == null || yMinus == null) return null;
    return (yPlus - yMinus) / (2 * h);
  }

  // 🛠️ math_analyzer.txt - _bisectionDerivative 함수 전체 교체 (Line 634 부근)
  static double? _bisectionDerivative({
    required Expression expression,
    required ContextModel context,
    required double leftX,
    required double rightX,
  }) {
    double left = leftX;
    double right = rightX;
    final double xTolerance = 1e-15;
    final int maxIterations = 60;

    // [Step 1] 이분법으로 안전하게 미분계수(기울기)가 0이 되는 근의 범위를 타이트하게 좁힙니다.
    double mid = (left + right) / 2.0;
    for (int i = 0; i < maxIterations; i++) {
      mid = (left + right) / 2.0;

      // ⭐️ [대완치 핵심]: f(x)의 y값 대신, _evaluateDerivative 함수를 사용하여
      // 해당 지점의 진짜 '기울기'가 0에 수렴하는지를 실시간으로 추적합니다!
      double midDeriv = _evaluateDerivative(expression, mid, context) ?? 0.0;

      if (midDeriv == 0.0 || (right - left) / 2.0 < 1e-5) {
        break; // 뉴턴-랩슨이 바통을 이어받을 수 있는 거리까지 오면 탈출
      }

      double leftDeriv = _evaluateDerivative(expression, left, context) ?? 0.0;
      if ((leftDeriv * midDeriv) < 0) {
        right = mid;
      } else {
        left = mid;
      }
    }

    // [Step 2] 뉴턴-랩슨 법으로 단숨에 도함수의 근을 정밀하게 수렴시킵니다.
    double xNew = mid;
    for (int j = 0; j < 10; j++) {
      // ⭐️ 극점 추적을 위한 뉴턴-랩슨 공식 개정: x_{n+1} = x_n - f'(x_n)/f''(x_n)
      // f'(x)의 근을 구해야 하므로 중앙차분법으로 1계도함수(y)와 2계도함수(dY)를 정밀하게 유도합니다.
      double? y = _evaluateDerivative(expression, xNew, context);

      // 미세 간격 h를 이용해 2계 미분계수(f''(x)) 산출
      double h = 0.0001;
      double? yPlus = _evaluateDerivative(expression, xNew + h, context);
      double? yMinus = _evaluateDerivative(expression, xNew - h, context);
      double? dY =
          (yPlus != null && yMinus != null) ? (yPlus - yMinus) / (2 * h) : null;

      if (y == null || dY == null || dY.abs() < 1e-12) break;

      double step = y / dY;
      xNew = xNew - step;

      if (step.abs() < xTolerance) break;
    }

    return xNew;
  }

  // ----------------------------------------------------------
  // [교점 찾기 핵심 로직 - 수정됨]
  // ----------------------------------------------------------

  // 🛠️ math_analyzer.txt - findIntersections 함수 내부 수정 (Line 651 부근)
  static List<Offset> findIntersections({
    required String f,
    required String g,
    required double minX,
    required double maxX,
    required double paramA,
  }) {
    List<Offset> points = [];
    final Parser p = Parser();

    if (f.trim().isEmpty || g.trim().isEmpty) return points;

    // ⭐️ [교점 엔진 대완치 레이어]:
    // function_parser.txt 단에서 지수 괄호를 보정하기 위해 사용했던 규칙과 100% 동일한 전처리를
    // 교점용 문자열 f와 g에 선행 적용하여 백엔드 연산 레이어 간 엇박자를 완전히 소멸시킵니다.
    String processedF = f;
    String processedG = g;

    // (A) 세미콜론 탈출 마커가 없는 연속 입력 지수 보정
    if (!processedF.contains(';')) {
      processedF = processedF.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+)'),
        (Match m) => '^(${m.group(1)})',
      );
    } else {
      processedF = processedF.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+);'),
        (Match m) => '^(${m.group(1)})',
      );
      processedF = processedF.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+)'),
        (Match m) => '^(${m.group(1)})',
      );
      processedF = processedF.replaceAll(';', '');
    }

    if (!processedG.contains(';')) {
      processedG = processedG.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+)'),
        (Match m) => '^(${m.group(1)})',
      );
    } else {
      processedG = processedG.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+);'),
        (Match m) => '^(${m.group(1)})',
      );
      processedG = processedG.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+)'),
        (Match m) => '^(${m.group(1)})',
      );
      processedG = processedG.replaceAll(';', '');
    }

    // ⭐️ [암시적 곱셈 보정 규칙 적용]
    String safeF = processedF.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z])'),
      (Match m) => '${m[1]}*${m[2]}',
    );
    String safeG = processedG.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z])'),
      (Match m) => '${m[1]}*${m[2]}',
    );

    Expression expF;
    Expression expH;
    try {
      expF = p.parse(safeF); // 👈 전처리가 완비된 수식 주입
      expH = p.parse("($safeF) - ($safeG)"); // 👈 완벽한 차함수 결합 완료
    } catch (e) {
      return points;
    }

    final ContextModel context = ContextModel();
    context.bindVariable(Variable('a'), Number(paramA));

    // ⭐️ [중요] 완벽한 정수 해(0, 1, 2 등)나 주요 지점을 먼저 다이렉트로 검사합니다.
    // 수학교육용 프로그램에서 가장 많이 등장하는 정수 근처 예외를 완벽히 해결합니다.
    List<double> criticalPoints = [0.0, 1.0, -1.0, 2.0, -2.0];
    for (double cx in criticalPoints) {
      if (cx >= minX && cx <= maxX) {
        double? cy = _evaluate(expH, cx, context);
        if (cy != null && cy.abs() < 1e-7) {
          // 거의 완벽한 0
          double? rootY = _evaluate(expF, cx, context);
          if (rootY != null && rootY.isFinite) {
            points.add(Offset(cx, cx.abs() < 1e-4 ? 0.0 : rootY));
          }
        }
      }
    }

    // 일반적인 관통 교점을 찾기 위한 스캔 (오차 범위를 다시 타이트하게 조입니다)
    int steps = 1000;
    double stepSize = (maxX - minX) / steps;

    for (int i = 0; i < steps; i++) {
      double x1 = minX + i * stepSize;
      double x2 = x1 + stepSize;

      double? y1 = _evaluate(expH, x1, context);
      double? y2 = _evaluate(expH, x2, context);

      // 어느 한쪽이라도 계산이 불가능하면 다음 스텝으로 패스
      if (y1 == null ||
          y1.isNaN ||
          y1.isInfinite ||
          y2 == null ||
          y2.isNaN ||
          y2.isInfinite)
        continue;

      // 사이값 정리 (부호 변화 발생)
      if (y1 * y2 <= 0) {
        double rootX = _bisectionForString(expH, context, x1, x2);

        // 정수 필터링과 중복되지 않게 검사
        if (points.where((p) => (p.dx - rootX).abs() < 0.05).isEmpty) {
          double? rootY = _evaluate(expF, rootX, context);
          if (rootY != null && rootY.isFinite) {
            // -0.0 방지 보정
            double displayX = rootX.abs() < 1e-3 ? 0.0 : rootX;
            double displayY = rootY.abs() < 1e-3 ? 0.0 : rootY;
            points.add(Offset(displayX, displayY));
          }
        }
      }
      // 접하는 케이스 스캔 (오차 범위를 0.0001 수준으로 극도로 좁혀 가짜 점 전면 차단)
      else {
        double midX = (x1 + x2) / 2;
        double? yMid = _evaluate(expH, midX, context);

        if (yMid != null && yMid.abs() < 0.0005) {
          // ⭐️ 가짜 점이 통과할 수 없게 바운더리 축소
          if (points.where((p) => (p.dx - midX).abs() < 0.05).isEmpty) {
            double? rootY = _evaluate(expF, midX, context);
            if (rootY != null && rootY.isFinite) {
              double displayX = midX.abs() < 1e-3 ? 0.0 : midX;
              double displayY = rootY.abs() < 1e-3 ? 0.0 : rootY;
              points.add(Offset(displayX, displayY));
            }
          }
        }
      }
    }

    // x축 기준으로 예쁘게 정렬
    points.sort((a, b) => a.dx.compareTo(b.dx));
    return points;
  }

  /// 차함수 전용 이분법 helper
  static double _bisectionForString(
    Expression exp,
    ContextModel ctx,
    double low,
    double high,
  ) {
    double left = low;
    double right = high;
    for (int i = 0; i < 60; i++) {
      double mid = (left + right) / 2;
      double? yLeft = _evaluate(exp, left, ctx) ?? 0;
      double? yMid = _evaluate(exp, mid, ctx) ?? 0;

      if ((yLeft * yMid) <= 0) {
        right = mid;
      } else {
        left = mid;
      }
    }
    return (left + right) / 2;
  }
}
