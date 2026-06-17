import 'package:math_expressions/math_expressions.dart';
import 'dart:math' as math;

/// 사용자가 입력한 수학적 표현식을 파싱하고 계산하는 클래스입니다.
class FunctionParser {
  final ShuntingYardParser _parser;
  final ContextModel _contextModel;
  final Variable _x;

  FunctionParser()
    : _parser = ShuntingYardParser(),
      _contextModel = ContextModel(),
      _x = Variable('x');

  String _preprocessExpression(String expression) {
    String processed = expression; // 원본 수식 보존을 위해 공백 제거를 뒤로 미룸!

    // ⭐️ [대대수적 연산 완치 핵심 알고리즘]
    if (!processed.contains(';')) {
      processed = processed.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+)'),
        (Match m) => '^(${m.group(1)})',
      );
    } else {
      processed = processed.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+);'),
        (Match m) => '^(${m.group(1)})',
      );
      processed = processed.replaceAllMapped(
        RegExp(r'\^(?!\()([^;^]+)'),
        (Match m) => '^(${m.group(1)})',
      );
      processed = processed.replaceAll(';', '');
    }

    // 1. 특수기호 및 y= 제거
    processed = processed.replaceAll(r'\', '');
    processed = processed.replaceAll(RegExp(r'y_{?\d?}?\s*='), '');

    // 2. 절댓값 처리 (|x| -> abs(x))
    processed = processed.replaceAllMapped(
      RegExp(r'\|(.*?)\|'),
      (m) => 'abs(${m.group(1)})',
    );

    // ⭐️ [신설 UI/UX 보정 A]: 사용자가 괄호 없이 'sqrtx' 또는 'sqrt5' 라고만 쳤을 때
    // 'sqrt(x)', 'sqrt(5)'로 강제 괄호 매핑을 수행합니다. (sin, cos, tan, ln 등도 일괄 적용)
    processed = processed.replaceAllMapped(
      RegExp(r'(sqrt|sin|cos|tan|ln|log)(x|a|pi|e|\d+)'),
      (m) => '${m.group(1)}(${m.group(2)})',
    );

    // ★ 3. math_expressions가 모르는 고급 삼각함수 치환 (매우 중요!) ★
    processed = processed.replaceAll('csc', '1/sin');
    processed = processed.replaceAll('sec', '1/cos');
    processed = processed.replaceAll('cot', '1/tan');

    // 4. 숫자 뒤에 문자/괄호: "9x" -> "9*x", "3(" -> "3*("
    processed = processed.replaceAllMapped(
      RegExp(r'([\d.]+)([a-zA-Z(])'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );
    // 5. 닫는 괄호 뒤에 문자/숫자/괄호: ")x" -> ")*x"
    processed = processed.replaceAllMapped(
      RegExp(r'(\))([a-zA-Z\d.(])'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );
    // 6. 문자 뒤에 숫자: "x2" -> "x*2"
    processed = processed.replaceAllMapped(
      RegExp(r'([a-zA-Z])([\d.]+)'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );
    // 7. x 변수 뒤 괄호: "x(" -> "x*("
    processed = processed.replaceAllMapped(
      RegExp(r'(x)(\()'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );

    // 8. 변수(x, a) 및 상수(pi, e) 끼리 붙어있는 경우 (예: ax -> a*x, xpi -> x*pi, pie -> pi*e)
    // ★ 핵심: axpi 처럼 3개 이상 뭉쳐있는 경우(a*x*pi)를 완벽히 떼어내기 위해 2번 반복 실행합니다.
    for (int i = 0; i < 2; i++) {
      processed = processed.replaceAllMapped(
        RegExp(r'(x|a|pi|e)(x|a|pi|e)'),
        (m) => '${m.group(1)}*${m.group(2)}',
      );
    }

    // 9. 변수/상수 뒤에 괄호나 함수가 올 때 (예: xsin -> x*sin, pi( -> pi*(, eln -> e*ln)
    processed = processed.replaceAllMapped(
      RegExp(r'(x|a|pi|e)(\(|sin|cos|tan|log|ln|sqrt|abs)'),
      (m) => '${m.group(1)}*${m.group(2)}',
    );

    // 10. 상용로그(log)를 밑이 10인 로그로 변환
    processed = processed.replaceAll('log(', 'log(10,');

    // 11단계: 나눗셈 괄호 강제 묶기
    processed = processed.replaceAllMapped(
      RegExp(r'/([\d.]+(?:\*(?:x|a|pi|e))+)'),
      (m) => '/(${m.group(1)})',
    );

    return processed;
  }

  double evaluate(
    String expression,
    double xValue, {
    Map<String, double>? params,
  }) {
    if (expression.trim().isEmpty) return double.nan;

    try {
      final processedExpression = _preprocessExpression(expression);

      // 💡 여기서 에러의 원인을 찾을 수 있습니다! (디버그 콘솔 창을 보세요)
      // print('입력된 수식: $expression  ====>  변환된 수식: $processedExpression');

      Expression exp = _parser.parse(processedExpression);

      _contextModel.bindVariable(_x, Number(xValue));
      _contextModel.bindVariable(Variable('e'), Number(math.e));
      _contextModel.bindVariable(Variable('pi'), Number(math.pi));

      if (params != null) {
        params.forEach((name, value) {
          _contextModel.bindVariable(Variable(name), Number(value));
        });
      }

      // ignore: deprecated_member_use
      return exp.evaluate(EvaluationType.REAL, _contextModel);
    } catch (e) {
      // 💡 문법이 틀렸을 때 강제 종료되는 대신 로그를 남깁니다.
      // print('수식 파싱 에러 발생: $e');
      return double.nan;
    }
  }
}
