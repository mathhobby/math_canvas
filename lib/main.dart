import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import 'dart:math' as math;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'function_parser.dart';
import 'math_analyzer.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart' as google_api;
import 'firebase_options.dart'; // [cite: 2, 10]
import 'package:flutter/services.dart'; // 👈 [추가]: 클립보드 복사 기능을 위해 필요

// --- ▼▼▼ 수식 상태 데이터 모델 ▼▼▼ ---
class GraphItem {
  String text;
  TextEditingController controller;
  Color color;
  bool isExpanded;

  String? errorMessage; // 👈 [신설]: 수식 문법 오류 메시지를 저장할 변수!

  bool showDerivative;
  bool showInverse;
  bool showIntegral;

  bool showXIntercepts;
  bool showYIntercepts;
  bool showExtrema;

  double integralA;
  double integralB;

  bool isSelectedForIntersection; // 교점 계산을 위해 선택되었는지 여부
  List<Offset> intersectionPoints = []; // 계산된 교점 저장

  GraphItem({
    required this.text,
    required this.color,
    this.errorMessage, // 👈 생성자 추가
    this.isExpanded = false,
    this.showDerivative = false,
    this.showInverse = false,
    this.showIntegral = false,
    this.showXIntercepts = false,
    this.showYIntercepts = false,
    this.showExtrema = false,
    this.integralA = 0.0,
    this.integralB = 2.0,
    this.isSelectedForIntersection = false,
    this.intersectionPoints = const [],
  }) : controller = TextEditingController(text: text);

  // Firestore 저장을 위한 변환 (ID는 제외하고 저장)
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'color': color.value,
      'showDerivative': showDerivative,
      'showInverse': showInverse,
      'showIntegral': showIntegral,
      'showXIntercepts': showXIntercepts,
      'showYIntercepts': showYIntercepts,
      'showExtrema': showExtrema,
      'integralA': integralA,
      'integralB': integralB,
      'isSelectedForIntersection': isSelectedForIntersection,
    };
  }

  // Firestore에서 가져온 데이터를 객체로 복구 (안전성 강화 버전)
  factory GraphItem.fromMap(Map<String, dynamic> map) {
    // ⭐️ 색상 값이 int나 String 어떤 형태로 오든 안전하게 보존하도록 파싱합니다.
    final dynamic colorValue = map['color'];
    Color parsedColor = Colors.blue[700]!; // 기본 폴백 색상

    if (colorValue is int) {
      parsedColor = Color(colorValue);
    } else if (colorValue is String) {
      parsedColor = Color(int.parse(colorValue));
    }

    return GraphItem(
      text: map['text'] ?? '',
      color: parsedColor, // ⭐️ 오염되지 않은 고유 색상 주입
      showDerivative: map['showDerivative'] ?? false,
      showInverse: map['showInverse'] ?? false,
      showIntegral: map['showIntegral'] ?? false,
      showXIntercepts: map['showXIntercepts'] ?? false,
      showYIntercepts: map['showYIntercepts'] ?? false,
      showExtrema: map['showExtrema'] ?? false,
      integralA: (map['integralA'] ?? 0.0).toDouble(),
      integralB: (map['integralB'] ?? 2.0).toDouble(),
      isSelectedForIntersection: map['isSelectedForIntersection'] ?? false,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
} // [cite: 8, 9]

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Math Canvas',
      home: MyGraphScreen(),
    );
  }
}

class MyGraphScreen extends StatefulWidget {
  const MyGraphScreen({super.key});

  @override
  State<MyGraphScreen> createState() => _MyGraphScreenState();
}

class _MyGraphScreenState extends State<MyGraphScreen> {
  // 💥 [추가 1]: 사용자 연령대 상태 관리 변수
  String _selectedLevel = '고등';
  bool _isLevelSelected = false;

  final GlobalKey _canvasKey = GlobalKey();

  Matrix4 matrix = Matrix4.identity();
  Matrix4 baseMatrix = Matrix4.identity();
  Offset baseFocalPoint = Offset.zero;
  bool _isInitialized = false;

  // _MyGraphScreenState 클래스 상단 변수 선언부에 추가
  List<Map<String, dynamic>> _projectList = []; // ⭐️ 사이드바에 띄울 프로젝트 목록 변수
  String _currentProjectTitle = ""; // 현재 열려있는 프로젝트 이름

  // ⭐️ 프로젝트 저장 시 이름을 입력받는 팝업창 UI
  void _showSaveDialog() {
    if (_user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요한 기능입니다.')));
      return;
    }

    final titleController = TextEditingController(text: _currentProjectTitle);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            '프로젝트 저장',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: '프로젝트 제목',
              hintText: '예: 이차함수와 삼차함수의 교점 탐구',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(context);
                  await _saveProject(title); // 아까 만든 저장 함수 호출
                  _currentProjectTitle = title;
                  _refreshProjectList(); // ⭐️ 저장 후 사이드바 목록 갱신
                }
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
  }

  // ⭐️ 사이드바 목록을 동적으로 새로고침하는 헬퍼 함수
  Future<void> _refreshProjectList() async {
    final list = await _getProjectList();
    setState(() {
      _projectList = list;
    });
  }

  final FunctionParser _parser = FunctionParser();

  final List<GraphItem> _graphItems = [];
  int _focusedIndex = 0;

  bool _isKeyboardVisible = false;
  int _keyboardTabIndex = 0;

  double _parameterA = 1.0;
  double _minA = -5.0;
  double _maxA = 5.0;
  bool _isVariablePanelVisible = false;

  final List<Color> graphColors = [
    Colors.blue[700]!,
    Colors.red[700]!,
    Colors.green[700]!,
    Colors.orange[700]!,
    Colors.purple[700]!,
  ];

  @override
  void initState() {
    super.initState();
    _graphItems.add(GraphItem(text: "", color: graphColors[0]));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetView();
      _checkDeepLink(); // 👈 [이곳에 추가!] 화면이 그려지자마자 링크 스캔 시작
    });
  }

  // 💥 [추가 2]: 앱 실행 시 가장 먼저 보여질 학년 선택 화면
  Widget _buildLevelSelectionScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // 깔끔한 연한 배경색
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '내 학년에 맞는 수학 캔버스 시작하기',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '선택한 학년에 맞춰 키보드와 기능이 최적화됩니다.',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 50),

            // 1. 초등학생 버튼
            _levelButton(title: '🌱 초등학교', levelStr: '초등', color: Colors.green),
            const SizedBox(height: 20),

            // 2. 중학생 버튼
            _levelButton(title: '🌿 중학교', levelStr: '중등', color: Colors.blue),
            const SizedBox(height: 20),

            // 3. 고등학생 버튼
            _levelButton(
              title: '🌳 고등학교 이상',
              levelStr: '고등',
              color: Colors.deepPurple,
            ),
          ],
        ),
      ),
    );
  }

  // 버튼 디자인 컴포넌트
  Widget _levelButton({
    required String title,
    required String levelStr,
    required Color color,
  }) {
    return SizedBox(
      width: 350,
      height: 70,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
        onPressed: () {
          setState(() {
            _selectedLevel = levelStr;
            _isLevelSelected = true; // 선택 완료! 메인 캔버스로 이동
          });
          // 💥 [추가]: 캔버스가 화면에 '최초로' 나타난 직후(PostFrame)에 크기를 재고 중앙으로 워프!
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _resetView();
          });
        },
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _resetView();
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    for (var item in _graphItems) {
      item.controller.dispose();
    }
    super.dispose();
  }

  void _showVariableDialog() {
    final minController = TextEditingController(text: _minA.toString());
    final maxController = TextEditingController(text: _maxA.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('범위를 입력하세요'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minController,
                decoration: const InputDecoration(labelText: '최솟값'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
              TextField(
                controller: maxController,
                decoration: const InputDecoration(labelText: '최댓값'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _minA = double.tryParse(minController.text) ?? _minA;
                  _maxA = double.tryParse(maxController.text) ?? _maxA;

                  // --- ▼ 추가된 방어 로직 (거꾸로 입력하면 스왑!) ▼ ---
                  if (_minA > _maxA) {
                    final temp = _minA;
                    _minA = _maxA;
                    _maxA = temp;
                  }
                  // --- ▲ 추가된 방어 로직 ▲ ---

                  if (_parameterA < _minA) _parameterA = _minA;
                  if (_parameterA > _maxA) _parameterA = _maxA;
                  _isVariablePanelVisible = true;
                });
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _editIntegralBound(GraphItem item, bool isStart) {
    // 현재 값으로 텍스트 컨트롤러 초기화
    final controller = TextEditingController(
      text: (isStart ? item.integralA : item.integralB).toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isStart ? '적분 시작점 (a) 입력' : '적분 끝점 (b) 입력',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            autofocus: true, // 팝업이 뜨면 바로 키보드가 올라오게
            decoration: InputDecoration(
              hintText: '숫자를 입력하세요',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                final val = double.tryParse(controller.text);
                if (val != null) {
                  setState(() {
                    if (isStart) {
                      item.integralA = val; // 시작점 업데이트
                    } else {
                      item.integralB = val; // 끝점 업데이트
                    }
                  });
                }
                Navigator.pop(context); // 팝업 닫기
              },
              child: const Text('확인', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _addExpressionField() {
    setState(() {
      // ⭐️ [색상 중복 방어]: 현재 리스트에 이미 존재하는 색상들을 파악합니다.
      List<Color> currentColors =
          _graphItems.map((item) => item.color).toList();
      Color nextColor = graphColors[0]; // 기본값

      // graphColors 배열을 순회하며 현재 필드에 쓰이지 않은 첫 번째 색상을 찾아냅니다.
      for (var color in graphColors) {
        //
        if (!currentColors.contains(color)) {
          nextColor = color;
          break;
        }
      }

      _graphItems.add(
        GraphItem(
          text: '',
          color: nextColor, // ⭐️ 오염되지 않은 고유한 새 색상 부여
        ),
      );
      _focusedIndex = _graphItems.length - 1;
      _isKeyboardVisible = true;
    });
  }

  // 🛠️ main.dart - _removeExpressionField 함수 전체 교체
  // ⭐️ [고스트 교점 제거 마스터피스]: 삭제 시 파트너의 상태까지 완벽하게 초기화합니다.
  void _removeExpressionField(int index) {
    if (_graphItems.length <= 1) return;

    setState(() {
      _graphItems[index].controller.dispose();
      _graphItems.removeAt(index);

      // 포커스 인덱스가 유효 범위를 벗어나지 않도록 방어
      if (_focusedIndex >= _graphItems.length) {
        _focusedIndex = _graphItems.length - 1;
      }

      // 💥 [대완치 핵심 레이어]: 수식을 삭제한 직후, 교점 모드 상태를 재점검합니다.
      var selectedItems =
          _graphItems.where((item) => item.isSelectedForIntersection).toList();

      // 만약 교점 파트너 중 하나가 지워져서 혼자 남았다면 (길이가 2 미만이라면)
      if (selectedItems.length < 2) {
        for (var item in _graphItems) {
          item.isSelectedForIntersection = false; // 노란색 활성화 테두리 끄기
          item.intersectionPoints = const []; // 화면에 남은 유령 교점 데이터 날리기
        }
      } else {
        // (만약 3개 중 1개를 지워서 다시 2개가 남는 구조라면 실시간 재계산 트리거)
        _triggerIntersectionRecalculation();
      }
    });
  }

  // ⭐️ [PC/모바일 하이브리드 중앙 정렬 완치본]
  void _resetView() {
    // 💥 [핵심]: 캔버스가 화면에 렌더링되어 실제 크기를 알 수 있을 때
    if (_canvasKey.currentContext != null) {
      final RenderBox renderBox =
          _canvasKey.currentContext!.findRenderObject() as RenderBox;
      final Size canvasSize = renderBox.size;

      setState(() {
        // PC든 모바일이든 '순수하게 캔버스가 차지하는 영역'의 정중앙을 계산합니다.
        double centerX = canvasSize.width / 2;
        double centerY = canvasSize.height / 2;

        matrix =
            Matrix4.identity()
              ..translate(centerX, centerY)
              ..scale(35.0, 35.0, 1.0);
      });
    } else {
      // (보험용 가드) 앱이 최초로 켜지는 찰나의 1프레임 동안 에러를 막기 위한 기존 코드
      setState(() {
        final double totalWidth = MediaQuery.of(context).size.width;
        final double totalHeight = MediaQuery.of(context).size.height;
        bool isWeb = totalWidth >= 800;
        double sidebarWidth = isWeb ? 380.0 : 0.0;
        double centerX = (totalWidth - sidebarWidth) / 2;
        double centerY = totalHeight / 2;

        matrix =
            Matrix4.identity()
              ..translate(centerX, centerY)
              ..scale(35.0, 35.0, 1.0);
      });
    }
  }

  // 🛠️ main.dart - _moveCursor 함수 전체 교체
  // ⭐️ [지수방 탈출 및 커서 증발 대완치 알고리즘]
  void _moveCursor(bool toLeft) {
    final controller = _focusedController;
    if (controller == null) return;
    final text = controller.text;
    final selection = controller.selection;
    int start = selection.start;
    if (start < 0) start = text.length;

    setState(() {
      int newOffset = start;

      if (toLeft) {
        // ◀ 왼쪽 방향키를 눌렀을 때
        if (newOffset > 0) {
          if (newOffset >= 4 &&
              text.substring(newOffset - 4, newOffset) == 'sqrt')
            newOffset -= 4;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'csc')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'sec')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'cot')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'sin')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'cos')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'tan')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'abs')
            newOffset -= 3;
          else if (newOffset >= 3 &&
              text.substring(newOffset - 3, newOffset) == 'log')
            newOffset -= 3;
          else if (newOffset >= 2 &&
              text.substring(newOffset - 2, newOffset) == 'ln')
            newOffset -= 2;
          else if (newOffset >= 2 &&
              text.substring(newOffset - 2, newOffset) == 'pi')
            newOffset -= 2;
          else {
            newOffset -= 1;
          }
        }
      } else {
        // ▶ 오른쪽 방향키를 눌렀을 때
        if (newOffset < text.length) {
          if (newOffset <= text.length - 4 &&
              text.substring(newOffset, newOffset + 4) == 'sqrt')
            newOffset += 4;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'csc')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'sec')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'cot')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'sin')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'cos')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'tan')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'abs')
            newOffset += 3;
          else if (newOffset <= text.length - 3 &&
              text.substring(newOffset, newOffset + 3) == 'log')
            newOffset += 3;
          else if (newOffset <= text.length - 2 &&
              text.substring(newOffset, newOffset + 2) == 'ln')
            newOffset += 2;
          else if (newOffset <= text.length - 2 &&
              text.substring(newOffset, newOffset + 2) == 'pi')
            newOffset += 2;
          else {
            newOffset += 1;
          }
        }
        // 지수방 탈출 조건 유지
        else if (newOffset == text.length && text.contains('^')) {
          if (!text.endsWith(';')) {
            controller.text = '$text;';
            newOffset = text.length + 1;
          }
        }
      }

      if (newOffset < 0) newOffset = 0;
      if (newOffset > controller.text.length)
        newOffset = controller.text.length;

      controller.value = TextEditingValue(
        text: controller.text,
        selection: TextSelection.collapsed(offset: newOffset),
      );

      // 💥 [커서 증발 완벽 해결]: 변경된 최신 텍스트 상태를 화면 렌더러 바구니에 확실하게 동기화합니다!
      _graphItems[_focusedIndex].text = controller.text;
    });
  }

  // 🛠️ main.txt - _zoom 함수 전체 교체 (Line 72 부근)
  // ⭐️ [대수적 원점 축 고정형 초정밀 줌 알고리즘]
  void _zoom(double scale) {
    setState(() {
      // 💥 [대완치 핵심 레이어]: 화면 중앙 픽셀 대신, 현재 매트릭스가 가리키고 있는
      // 진짜 대수학적 원점 (0, 0, 0)의 실시간 스크린 픽셀 좌표(Offset)를 역추적하여 추출합니다!
      final vector_math.Vector3 originScreenVector = matrix.transform3(
        vector_math.Vector3(0, 0, 0),
      );
      final Offset originFocalPoint = Offset(
        originScreenVector.x,
        originScreenVector.y,
      );

      // 완벽하게 획득한 원점의 위치를 중심축으로 삼아 아핀 변환(Affine Transformation) 매트릭스를 조립합니다.
      final scaleMatrix =
          Matrix4.identity()
            ..translate(
              originFocalPoint.dx,
              originFocalPoint.dy,
            ) // 원점 자리로 공간 워프
            ..scale(scale, scale) // 원점을 축으로 정밀 배율 조절
            ..translate(-originFocalPoint.dx, -originFocalPoint.dy); // 공간 복귀

      matrix = scaleMatrix * matrix; // 최종 매트릭스 결합
    });
  }

  TextEditingController? get _focusedController {
    if (_graphItems.isNotEmpty && _focusedIndex < _graphItems.length) {
      return _graphItems[_focusedIndex].controller;
    }
    return null;
  }

  // ⭐️ [보존 필수]: 다글자 토큰 내부 역추적 및 인덱스 패닉 방어선 가드가 완비된 최종본
  void _onKeyPressed(String value) {
    final controller = _focusedController;
    if (controller == null) return;

    final text = controller.text;
    final selection = controller.selection;
    int start = selection.start;
    int end = selection.end;

    if (start < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, value);

    // 기본 타겟 오프셋 설정
    int targetOffset = start + value.length;

    // 합성함수 내부 착지점 뒤틀림 방지용 후방 인덱스 검색 엔진
    int searchStartIndex = start + value.length;
    if (searchStartIndex <= newText.length && newText.contains(value, start)) {
      targetOffset = newText.indexOf(value, start) + value.length;
    }

    // 최종 안전 바운더리 검증 후 원자적 트랜잭션 주입
    if (targetOffset >= 0 && targetOffset <= newText.length) {
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: targetOffset),
      );

      setState(() {
        _graphItems[_focusedIndex].text = newText;
      });
    }
  }

  // 🛠️ main.txt - _onBackspacePressed 함수 전체 최종본 교체
  // ⭐️ [함수 껍데기(경계선) 정밀 타격 & 내용물 수호형 삭제 알고리즘]
  void _onBackspacePressed() {
    final controller = _focusedController; //
    if (controller == null) return; //

    final text = controller.text; //
    if (text.isEmpty) return; //

    final selection = controller.selection; //
    int start = selection.start; //
    int end = selection.end; //

    if (start < 0) {
      //
      start = text.length; //
      end = text.length; //
    }

    setState(() {
      //
      String newText;
      int newCursorOffset;

      if (start != end) {
        //
        newText = text.replaceRange(start, end, ''); //
        newCursorOffset = start; //
      } else {
        if (start == 0) return; //

        int targetStart = start - 1;
        int targetEnd = start;
        bool isStructureDeleted = false;

        if (start >= 2 && text.substring(start - 2, start) == 'pi') {
          targetStart = start - 2;
          targetEnd = start;
          isStructureDeleted = true;
        } else {
          final List<String> functions = [
            'sqrt',
            'abs',
            'sin',
            'cos',
            'tan',
            'csc',
            'sec',
            'cot',
            'log',
            'ln',
          ];

          // 역방향으로 1칸씩 짚어 올라가며 가장 밀착된 함수 껍데기 탐색
          for (int pos = start - 1; pos >= 0; pos--) {
            for (var func in functions) {
              int funcLen = func.length;

              if (pos + funcLen + 1 <= text.length &&
                  text.substring(pos, pos + funcLen + 1) == '$func(') {
                int openBracket = pos + funcLen;

                // 💥 [안전 보강]: 중첩 괄호까지 완벽하게 고려하여 '진짜 짝꿍 닫는 괄호'의 위치를 찾습니다.
                int closeBracket = -1;
                int depth = 0;
                for (int i = openBracket; i < text.length; i++) {
                  if (text[i] == '(')
                    depth++;
                  else if (text[i] == ')') {
                    depth--;
                    if (depth == 0) {
                      closeBracket = i;
                      break;
                    }
                  }
                }

                if (closeBracket != -1) {
                  // 🎯 [핵심 1. 우측 껍데기 폭파]: 커서가 닫는 괄호 ')' 바로 우측 뒤에 있을 때
                  if (start == closeBracket + 1) {
                    targetStart = pos;
                    targetEnd = closeBracket + 1;
                    isStructureDeleted = true;
                    break;
                  }
                  // 🎯 [핵심 2. 좌측 껍데기 폭파]: 커서가 여는 괄호 '(' 바로 뒤나 함수명 사이에 있을 때
                  else if (start > pos && start <= openBracket + 1) {
                    targetStart = pos;
                    targetEnd = closeBracket + 1;
                    isStructureDeleted = true;
                    break;
                  }
                  // 🎯 [핵심 3. 내용물 수호]: 그 외의 경우(커서가 괄호 내용물 'x' 뒤 등에 있다면)
                  // isStructureDeleted를 true로 만들지 않고 방관합니다! (아래의 일반 1글자 삭제로 넘어감)
                }
              }
            }
            if (isStructureDeleted) break;
          }
        }
        // [최종 실행]: 껍데기 폭파 조건이 달성되었을 때만 전체 삭제, 아니면 일반 1글자 삭제
        if (isStructureDeleted) {
          newText = text.replaceRange(targetStart, targetEnd, '');
          newCursorOffset = targetStart;
        } else {
          newText = text.replaceRange(start - 1, start, ''); //
          newCursorOffset = start - 1; //
        }
      }

      // 안전하게 트랜잭션 주입
      if (newCursorOffset >= 0 && newCursorOffset <= newText.length) {
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newCursorOffset), //
        ); //
        _graphItems[_focusedIndex].text = newText; //
      }
    });
  }

  // 1. 변수 선언부 (최신 패키지는 기본 생성자 GoogleSignIn()을 지원합니다)
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final google_api.GoogleSignIn _googleSignIn = google_api
      .GoogleSignIn.standard(scopes: <String>['email']);
  User? _user;
  // 2. 구글 로그인 함수 수정 버전 (Mobile, Web, Windows 3대 플랫폼 완벽 호환본)
  Future<void> _handleSignIn() async {
    try {
      UserCredential userCredential;

      // ⭐️ [1순위 판정]: '웹이 아닌 모바일 네이티브 환경(핸드폰)'인지 가장 먼저 체크합니다.
      if (!kIsWeb &&
          (Theme.of(context).platform == TargetPlatform.android ||
              Theme.of(context).platform == TargetPlatform.iOS)) {
        // 기존에 핸드폰에서 완벽하게 잘 작동하던 구글 네이티브 로그인 API를 호출합니다. [cite: 72]
        final google_api.GoogleSignInAccount? googleUser =
            await _googleSignIn.signIn(); //
        if (googleUser == null) return; // [cite: 73]

        final google_api.GoogleSignInAuthentication googleAuth =
            await googleUser.authentication; // [cite: 74]
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ); // [cite: 75]

        userCredential = await _auth.signInWithCredential(
          credential,
        ); // [cite: 76]
      }
      // ⭐️ [2순위 판정]: 웹 브라우저(GitHub Pages) 또는 Windows 데스크톱 환경일 때
      else {
        // 브라우저 팝업창을 띄우는 웹 전용 파이어베이스 인증 엔진을 구동합니다.
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');

        userCredential = await _auth.signInWithPopup(googleProvider);
      }

      // 로그인 성공 후 전천후 데이터 세팅 및 서랍장 동기화 [cite: 77]
      setState(() {
        _user = userCredential.user; // [cite: 77]
      });

      await _refreshProjectList(); // [cite: 78]

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_user?.displayName}님 환영합니다!'),
          ), // [cite: 79]
        );
      }
    } catch (e) {
      print("로그인 복합 에러: $e"); // [cite: 80]
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
      }
    }
  }

  // =========================================================================
  // 🛠️ [최종 교정본] Firebase 프로젝트 관리 (C.R.U.D) 및 상태 동기화 로직
  // =========================================================================

  // ⭐️ 1. 프로젝트 저장하기 (최종 정돈 완료 버전)
  Future<void> _saveProject(String projectTitle) async {
    if (_user == null) return;
    try {
      final userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid);

      // 상위 프로젝트 문서 등록 (merge 옵션으로 안전하게 덮어쓰기)
      final projectDocRef = userDocRef.collection('projects').doc(projectTitle);
      await projectDocRef.set({
        'title': projectTitle,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final graphsCollectionRef = projectDocRef.collection('graphs');
      final batch = FirebaseFirestore.instance.batch();

      // 기존 하위 문서들 깔끔하게 선행 삭제
      final existingDocs = await graphsCollectionRef.get();
      for (var doc in existingDocs.docs) {
        batch.delete(doc.reference);
      }

      // 현재 화면의 수식 데이터를 차곡차곡 배치를 통해 빌드
      for (var item in _graphItems) {
        batch.set(graphsCollectionRef.doc(), item.toMap());
      }

      // 서버에 완벽하게 커밋이 완료될 때까지 await
      await batch.commit();

      // 저장 완료 후 왼쪽 사이드바 목록 새로고침
      await _refreshProjectList();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$projectTitle" 프로젝트가 성공적으로 저장되었습니다! 🎉')),
        );
      }
    } catch (e) {
      print("프로젝트 저장 에러: $e");
    }
  }

  // 💥 [추가]: 현재 캔버스 상태를 클라우드에 박제하고 공유 링크를 생성하는 엔진
  Future<void> _shareProject() async {
    if (_graphItems.isEmpty) return;

    try {
      // 1. 'shared_projects' 라는 공유 전용 컬렉션에 임의의 고유 ID(문서)를 생성합니다.
      final docRef =
          FirebaseFirestore.instance.collection('shared_projects').doc();

      // 2. 현재 화면의 모든 수식 데이터를 Map 리스트로 변환합니다.
      List<Map<String, dynamic>> graphData =
          _graphItems.map((item) => item.toMap()).toList();

      // 3. 서버에 업로드!
      await docRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'creatorId': _user?.uid ?? 'guest', // 비회원도 공유 가능하게 하려면 이렇게 둡니다.
        'graphs': graphData,
      });

      // 4. 현재 접속 중인 웹 주소를 기반으로 공유 링크를 조립합니다.
      String baseUrl = "https://mathhobby.github.io/math_canvas/"; // 배포된 깃허브 주소
      if (kIsWeb) {
        baseUrl = Uri.base.origin + Uri.base.path; // 로컬 테스트 시에는 로컬 주소 사용
      }

      // 완성된 링크 형태: https://.../?share=알파벳문서ID
      final shareUrl = '$baseUrl?share=${docRef.id}';

      // 5. 사용자의 클립보드에 링크 자동 복사
      await Clipboard.setData(ClipboardData(text: shareUrl));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ 공유 링크가 생성되어 클립보드에 복사되었습니다!'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: '확인', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      print("공유 링크 생성 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('공유 링크 생성 실패: $e')));
      }
    }
  }

  // ⭐️ 2. 저장된 프로젝트 목록 불러오기 (Read List) [cite: 493, 494, 495]
  Future<List<Map<String, dynamic>>> _getProjectList() async {
    if (_user == null) return []; // [cite: 493]
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_user!.uid)
              .collection('projects')
              .orderBy('updatedAt', descending: true)
              .get(); // [cite: 494]
      return snapshot.docs.map((doc) => doc.data()).toList(); // [cite: 495]
    } catch (e) {
      print("프로젝트 목록 로드 에러: $e");
      return [];
    }
  }

  // ⭐️ 3. 특정 프로젝트의 수식 데이터 불러오기 (Read Content) - 강제 동기화 추가 [cite: 496, 497, 498]
  Future<void> _loadProjectData(String projectTitle) async {
    if (_user == null) return; // [cite: 496]
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(_user!.uid)
              .collection('projects')
              .doc(projectTitle)
              .collection('graphs')
              .get(); // [cite: 497, 498]

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _graphItems.clear(); //
          for (var doc in snapshot.docs) {
            _graphItems.add(GraphItem.fromMap(doc.data())); //
          }
        });

        // 🚨 핵심 수정: 불러오기가 완료된 직후, 활성화된 교점 모드를 추적하여 실시간 연산 가동
        _triggerIntersectionRecalculation();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('"$projectTitle" 서랍을 열었습니다.')));
        }
      }
    } catch (e) {
      print("프로젝트 데이터 로드 에러: $e"); // [cite: 501]
    }
  }

  // ⭐️ [신설 방어 코드] 불러오기/수정 시 교점 실시간 백업 계산용 엔진
  void _triggerIntersectionRecalculation() {
    var selectedList =
        _graphItems.where((item) => item.isSelectedForIntersection).toList();

    if (selectedList.length == 2) {
      final viewportWidth = MediaQuery.of(context).size.width;
      final invertedMatrix = Matrix4.inverted(matrix);
      final double minX =
          invertedMatrix.transform3(vector_math.Vector3(0, 0, 0)).x - 1.0;
      final double maxX =
          invertedMatrix
              .transform3(vector_math.Vector3(viewportWidth, 0, 0))
              .x +
          1.0;

      final points = MathAnalyzer.findIntersections(
        f: selectedList[0].text,
        g: selectedList[1].text,
        minX: minX,
        maxX: maxX,
        paramA: _parameterA,
      );

      setState(() {
        for (var item in _graphItems) {
          if (item.isSelectedForIntersection) {
            item.intersectionPoints = points;
          } else {
            item.intersectionPoints = const []; // 👈 선택되지 않은 그래프의 잔상 차단
          }
        }
      });
    } else {
      // 💥 [이중 안전장치]: 2개가 선택된 게 아니라면 모든 교점 좌표를 즉시 백지화합니다.
      setState(() {
        for (var item in _graphItems) {
          item.intersectionPoints = const [];
        }
      });
    }
  }

  // ⭐️ 4. 프로젝트 삭제하기 (Delete) [cite: 501, 502, 503, 505]
  Future<void> _deleteProject(String projectTitle) async {
    if (_user == null) return; // [cite: 501]
    try {
      final projectDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('projects')
          .doc(projectTitle); // [cite: 502]

      final graphsSnapshot =
          await projectDocRef.collection('graphs').get(); // [cite: 503]
      final batch = FirebaseFirestore.instance.batch(); // [cite: 503]
      for (var doc in graphsSnapshot.docs) {
        batch.delete(doc.reference); // [cite: 504]
      }

      batch.delete(projectDocRef); // [cite: 505]
      await batch.commit(); // [cite: 505]

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$projectTitle" 서랍의 연구 자료를 파쇄했습니다.')),
        );
      }
    } catch (e) {
      print("프로젝트 삭제 에러: $e"); // [cite: 508]
    }
  }

  // 💥 [추가]: 앱 실행 시 URL을 읽어 공유된 프로젝트를 자동으로 불러오는 엔진
  Future<void> _checkDeepLink() async {
    if (kIsWeb) {
      final uri = Uri.base;

      // 주소에 ?share= 파라미터가 있다면 작동!
      if (uri.queryParameters.containsKey('share')) {
        final shareId = uri.queryParameters['share']!;

        try {
          // 공유 데이터베이스에서 해당 ID의 문서를 찾아옵니다.
          final docSnapshot =
              await FirebaseFirestore.instance
                  .collection('shared_projects')
                  .doc(shareId)
                  .get();

          if (docSnapshot.exists) {
            final data = docSnapshot.data();
            if (data != null && data.containsKey('graphs')) {
              final List<dynamic> graphsList = data['graphs'];

              setState(() {
                _graphItems.clear(); // 기존 화면 비우기

                // 클라우드에서 가져온 데이터로 수식 카드 재생성
                for (var g in graphsList) {
                  _graphItems.add(
                    GraphItem.fromMap(Map<String, dynamic>.from(g)),
                  );
                }

                _focusedIndex = _graphItems.length - 1;

                // 누군가의 링크를 타고 왔으므로 연령 선택 화면을 패스시키고 바로 캔버스를 띄움
                _selectedLevel = '고등';
                _isLevelSelected = true;
              });

              // 교점 모드가 켜져 있었다면 실시간 재계산 트리거
              _triggerIntersectionRecalculation();

              // 💥 [추가]: 공유 링크로 들어와서 캔버스가 열린 직후에도 중앙 정렬!
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _resetView();
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✨ 공유된 수학 캔버스를 불러왔습니다.')),
                );
              }
            }
          } else {
            // 문서가 존재하지 않는 경우
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('❌ 만료되거나 존재하지 않는 공유 링크입니다.')),
              );
            }
          }
        } catch (e) {
          print("공유 링크 로드 에러: $e");
        }
      }
    }
  }

  // 🛠️ [main.txt] _toLatex 함수 전체 최종 완치본 (Line 182 부근)
  // ⭐️ [인덱스 역추적 점프 및 abs 양방향 바 스냅 알고리즘]
  String _toLatex(String expression, {int? cursorOffset}) {
    if (expression.isEmpty) {
      return cursorOffset != null
          ? r'{\color{blue}{\mathbf{\vert}}}'
          : ' '; // // [cite: 183]
    }

    String latex = expression; // // [cite: 183]
    latex = latex.replaceAllMapped(
      RegExp(r'a(sin|cos|tan|csc|sec|cot|ln|log|sqrt|abs)'),
      (Match m) => 'a ${m.group(1)}',
    ); // // [cite: 184]

    latex = latex.replaceAll('pix', 'pi x'); // // [cite: 185]
    latex = latex.replaceAll('xpi', 'x pi'); // // [cite: 185]
    latex = latex.replaceAll('ex', 'e x'); // // [cite: 185]
    latex = latex.replaceAll('xe', 'x e'); // // [cite: 185]
    latex = latex.replaceAll(RegExp(r'\be\('), r'e * ('); // // [cite: 186]
    latex = latex.replaceAll(RegExp(r'\bpi\('), r'pi * ('); // // [cite: 186]

    latex = latex
        .replaceAll(RegExp(r'\bsin\b'), r'\sin')
        .replaceAll(RegExp(r'\bcos\b'), r'\cos')
        .replaceAll(RegExp(r'\btan\b'), r'\tan')
        .replaceAll(RegExp(r'\bln\b'), r'\ln')
        .replaceAll(RegExp(r'\blog\b'), r'\log'); // // [cite: 186]

    latex = latex.replaceAllMapped(
      RegExp(r'abs\(([^)]*)\)'),
      (Match m) => '\\left|${m.group(1)}\\right|', // // [cite: 187]
    );

    latex = latex.replaceAllMapped(
      RegExp(r'sqrt\(([^)]*)\)'),
      (Match m) => '\\sqrt{${m.group(1)}}', // // [cite: 187]
    );

    if (!expression.contains('sqrt') &&
        !expression.contains('abs') && // // [cite: 187]
        !expression.contains('sin') && // // [cite: 188]
        !expression.contains('cos') && // // [cite: 188]
        !expression.contains('tan')) {
      // // [cite: 188]
      latex = latex.replaceAllMapped(
        RegExp(r'\(([^()]+)\)/\(([^()]+)\)'),
        (Match m) =>
            r'\frac{' +
            m.group(1)! +
            r'}{' +
            m.group(2)! +
            r'}', // // [cite: 188, 189]
      );
      latex = latex.replaceAllMapped(
        RegExp(r'([\w\d.]+)/\(([^()]+)\)'),
        (Match m) =>
            r'\frac{' +
            m.group(1)! +
            r'}{' +
            m.group(2)! +
            r'}', // // [cite: 190]
      );
      latex = latex.replaceAllMapped(
        RegExp(r'([\w\d.]+)/([\w\d.]+)'),
        (Match m) =>
            r'\frac{' +
            m.group(1)! +
            r'}{' +
            m.group(2)! +
            r'}', // // [cite: 191]
      );
    }

    latex = latex.replaceAll('pi', r'\pi'); // // [cite: 192]
    latex = latex.replaceAll('e', r'e'); // // [cite: 193]
    latex = latex.replaceAll('*', r'\cdot '); // // [cite: 193]

    // [Step 6]: 거듭제곱(지수) 수동 마커 세미콜론 정돈
    // 💥 [궁극의 정규식 + 방어막]: 이미 묶인 지수방은 건드리지 않도록 부정 전방탐색(Negative Lookahead) 추가!
    if (!expression.contains(';')) {
      latex = latex.replaceAllMapped(
        RegExp(r'\^(?!\{)([^;^]+)'),
        (Match m) => '^{${m.group(1)}}',
      );
    } else {
      latex = latex.replaceAllMapped(
        RegExp(r'\^(?!\{)([^;^]+);'),
        (Match m) => '^{${m.group(1)}}',
      );
      // 다중 지수 입력 시 남아있는 활성 지수방 마저 처리 (방어막 발동!)
      latex = latex.replaceAllMapped(
        RegExp(r'\^(?!\{)([^;^]+)'),
        (Match m) => '^{${m.group(1)}}',
      );
      latex = latex.replaceAll(';', ''); //
    }
    // 💥 [최종 대완치 마법 핵심 구역]: 지수 및 모든 괄호의 오차 마진이 완벽히 고정된 인덱스 추적 파이프라인 [cite: 194]
    if (cursorOffset != null &&
        cursorOffset >= 0 &&
        cursorOffset <= expression.length) {
      // [cite: 194]
      int latexOffset = 0; // [cite: 194]
      int textOffset = 0; // [cite: 195]

      while (textOffset < cursorOffset && latexOffset < latex.length) {
        // [cite: 195]
        // 1. sqrt
        if (expression.startsWith('sqrt', textOffset)) {
          // [cite: 195]
          int nextBrace = latex.indexOf('{', latexOffset); // [cite: 195]
          latexOffset =
              (nextBrace != -1)
                  ? nextBrace + 1
                  : latexOffset + 6; // [cite: 195]
          textOffset += 4; // [cite: 196]
          continue; // [cite: 196]
        }
        // 2. abs
        else if (expression.startsWith('abs', textOffset)) {
          // [cite: 196]
          int nextLeftBar = latex.indexOf(
            '\\left|',
            latexOffset,
          ); // [cite: 196]
          latexOffset =
              (nextLeftBar != -1)
                  ? nextLeftBar + 6
                  : latexOffset + 6; // [cite: 196]
          textOffset += 3; // [cite: 197]
          continue; // [cite: 197]
        }
        // 3. 삼각함수 및 로그
        else if (expression.startsWith('csc', textOffset) || // [cite: 197]
            expression.startsWith('sec', textOffset) || // [cite: 198]
            expression.startsWith('cot', textOffset) || // [cite: 198]
            expression.startsWith('sin', textOffset) || // [cite: 198]
            expression.startsWith('cos', textOffset) || // [cite: 198]
            expression.startsWith('tan', textOffset) || // [cite: 198]
            expression.startsWith('log', textOffset)) {
          // [cite: 198]
          int nextSpace = latex.indexOf(' ', latexOffset); // [cite: 198]
          latexOffset =
              (nextSpace != -1 && nextSpace < latexOffset + 6)
                  ? nextSpace + 1
                  : latexOffset + 4; // [cite: 198]
          textOffset += 3; // [cite: 200]
          continue; // [cite: 200]
        }
        // 4. ln
        else if (expression.startsWith('ln', textOffset)) {
          // [cite: 201]
          int nextSpace = latex.indexOf(' ', latexOffset); // [cite: 201]
          latexOffset =
              (nextSpace != -1 && nextSpace < latexOffset + 5)
                  ? nextSpace + 1
                  : latexOffset + 3; // [cite: 202]
          textOffset += 2; // [cite: 204]
          continue; // [cite: 204]
        }
        // 5. pi
        else if (expression.startsWith('pi', textOffset)) {
          // [cite: 205]
          latexOffset +=
              latex.startsWith(r'\pi', latexOffset) ? 3 : 2; // [cite: 205]
          textOffset += 2; // [cite: 206]
          continue; // [cite: 206]
        }

        // 6. ⭐️ 지수(^) 진입 동기화
        if (expression.startsWith('^', textOffset)) {
          if (latex.startsWith('^{', latexOffset)) {
            latexOffset += 2;
            textOffset += 1;
            continue;
          }
        }

        // 7. ⭐️ 세미콜론(;) 탈출 기호 동기화
        if (expression.startsWith(';', textOffset)) {
          if (latex.startsWith('}', latexOffset)) {
            latexOffset += 1;
          }
          textOffset += 1;
          continue;
        }

        // 8. 닫는 기호 및 일반 문자 정밀 추적
        if (latex.startsWith('\\left|', latexOffset)) {
          // [cite: 207]
          latexOffset += 6; // [cite: 207]
          textOffset++; // [cite: 208]
        } else if (latex.startsWith('\\right|', latexOffset)) {
          // [cite: 209]
          latexOffset += 7; // [cite: 209]
          textOffset++; // [cite: 210]
        } else if (latex.startsWith('}', latexOffset) &&
            !expression.startsWith('}', textOffset)) {
          // 지수 괄호를 탈출할 때 인덱스 싱크홀을 방지합니다.
          latexOffset++;
        } else {
          latexOffset++; // [cite: 211]
          textOffset++; // [cite: 212]
        }
      }

      if (latexOffset <= latex.length) {
        // [cite: 213]
        latex = latex.replaceRange(
          latexOffset,
          latexOffset,
          r'{\color{blue}{\mathbf{\vert}}}',
        ); // [cite: 213]
      }
    }
    return latex; // [cite: 214]
  }

  String _doubleToFractionLatex(double value, {double tolerance = 1e-4}) {
    if (value.isNaN || value.isInfinite) return r"\text{Error}";
    if (value == 0 || value.abs() < tolerance) return "0";

    bool isNegative = value < 0;
    value = value.abs();

    int whole = value.floor();
    double decimal = value - whole;

    // 정수에 아주 가까운 경우 (예: 2.00001 -> 2)
    if (decimal < tolerance) return "${isNegative ? '-' : ''}$whole";
    if (1 - decimal < tolerance) return "${isNegative ? '-' : ''}${whole + 1}";

    // 연분수(Continued Fraction) 알고리즘으로 분수 찾기
    int h1 = 1, h2 = 0, k1 = 0, k2 = 1;
    double b = decimal;

    int i = 0;
    do {
      int a = b.floor();
      int auxH = h1;
      h1 = a * h1 + h2;
      h2 = auxH;
      int auxK = k1;
      k1 = a * k1 + k2;
      k2 = auxK;

      if (b - a < 1e-10) break;
      b = 1 / (b - a);
      i++;
    } while ((decimal - h1 / k1).abs() > tolerance && i < 50);

    int numerator = whole * k1 + h1;
    int denominator = k1;

    // ★ 스마트 폴백(Smart Fallback) 기능 ★
    // 분모가 100을 넘어가는 지저분한 숫자면 무리수(예: e, pi 관련)일 확률이 높으므로
    // 억지로 이상한 분수로 만들지 않고 소수점 둘째 자리까지만 보여줍니다.
    if (denominator > 100) {
      return (isNegative ? -value : value).toStringAsFixed(2);
    }

    // LaTeX 형태의 아름다운 분수 문자열로 반환
    String latex =
        r"\frac{" + numerator.toString() + "}{" + denominator.toString() + "}";
    return isNegative ? "-$latex" : latex;
  }

  String _calculateIntegral(GraphItem item) {
    if (item.text.isEmpty) return "-";

    final double a = item.integralA;
    final double b = item.integralB;

    // 구간이 같으면 넓이는 0
    if (a == b) return "0.00";

    final int n = 500; // 구간을 500개의 사다리꼴로 쪼갭니다 (숫자가 클수록 정밀해짐)
    final double dx = (b - a) / n;
    double area = 0.0;

    for (int i = 0; i < n; i++) {
      double x1 = a + i * dx;
      double x2 = a + (i + 1) * dx;

      // 진짜 수학 엔진을 이용해 두 지점의 y값을 구합니다.
      double y1 = _parser.evaluate(item.text, x1, params: {'a': _parameterA});
      double y2 = _parser.evaluate(item.text, x2, params: {'a': _parameterA});

      // 무한대로 발산하는 점근선이 구간에 포함되어 있으면 에러 처리
      if (y1.isNaN || y2.isNaN || y1.isInfinite || y2.isInfinite) {
        return "발산(Error)";
      }

      // 사다리꼴 넓이 공식: (윗변 + 아랫변) * 높이 / 2
      area += (y1 + y2) * dx / 2.0;
    }

    return _doubleToFractionLatex(area);
  }

  @override
  Widget build(BuildContext context) {
    // 💥 [추가 3]: 학년 선택을 아직 안 했다면 캔버스 대신 선택 화면을 강제로 띄웁니다!
    if (!_isLevelSelected) {
      return _buildLevelSelectionScreen();
    }
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      // ⭐️ [추가] 왼쪽에서 열리는 "나만의 수학 서랍" 위젯 구성
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              // ⭐️ backgroundColor 대신 decoration을 사용하여 배경색을 지정합니다.
              decoration: BoxDecoration(color: Colors.blue[600]),
              currentAccountPicture: CircleAvatar(
                backgroundImage:
                    _user != null && _user!.photoURL != null
                        ? NetworkImage(_user!.photoURL!)
                        : const AssetImage('assets/default_user.png')
                            as ImageProvider,
              ),
              accountName: Text(
                _user?.displayName ?? '게스트 사용자',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              accountEmail: Text(_user?.email ?? '로그인 후 클라우드를 이용하세요.'),
            ),
            Expanded(
              child:
                  _user == null
                      ? const Center(child: Text('로그인 후 프로젝트를 관리해보세요.'))
                      : _projectList.isEmpty
                      ? const Center(child: Text('저장된 프로젝트가 없습니다.'))
                      : ListView.builder(
                        itemCount: _projectList.length,
                        itemBuilder: (context, index) {
                          final project = _projectList[index];
                          final String title = project['title'] ?? '무제 프로젝트';
                          final bool isCurrent = _currentProjectTitle == title;

                          return ListTile(
                            leading: Icon(
                              Icons.functions_rounded,
                              color: isCurrent ? Colors.blue : Colors.grey,
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight:
                                    isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                color:
                                    isCurrent
                                        ? Colors.blue[700]
                                        : Colors.black87,
                              ),
                            ),
                            selected: isCurrent,
                            // 클릭 시 해당 프로젝트 불러오기
                            onTap: () async {
                              Navigator.pop(context); // 사이드바 닫기
                              await _loadProjectData(title);
                              setState(() {
                                _currentProjectTitle = title;
                              });
                            },
                            // 우측에 삭제(휴지통) 버튼 배치
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () {
                                // 삭제 확인 팝업
                                showDialog(
                                  context: context,
                                  builder:
                                      (ctx) => AlertDialog(
                                        title: const Text('프로젝트 삭제'),
                                        content: Text(
                                          '"$title" 프로젝트를 정말 삭제하시겠습니까?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('취소'),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              Navigator.pop(ctx);
                                              await _deleteProject(title);
                                              if (_currentProjectTitle ==
                                                  title) {
                                                _currentProjectTitle = "";
                                              }
                                              _refreshProjectList(); // 삭제 후 목록 리프레시
                                            },
                                            child: const Text(
                                              '삭제',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                );
                              },
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text(
          'Math Canvas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // 1. 로그인 상태에 따른 버튼 분기 처리
          _user == null
              ? TextButton.icon(
                onPressed: _handleSignIn, // 우리가 만든 로그인 함수 호출
                icon: const Icon(Icons.login),
                label: const Text('로그인'),
              )
              : Row(
                children: [
                  // ⭐️ [추가]: 공유 버튼 (초록색 아이콘)
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.green),
                    onPressed: _shareProject,
                    tooltip: '현재 캔버스 공유 링크 만들기',
                  ),
                  // 2. 로그인 시 저장 버튼 표시
                  IconButton(
                    icon: const Icon(Icons.save_rounded, color: Colors.blue),
                    onPressed: _showSaveDialog, // 우리가 만든 저장 함수 호출
                    tooltip: '프로젝트 저장',
                  ),
                  // 3. 사용자 프로필 이미지 표시
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0, left: 8.0),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(_user!.photoURL ?? ''),
                    ),
                  ),
                ],
              ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey[200], height: 1.0),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // ⭐️ [반응형 분기점]: 가로 너비가 800픽셀 이상이면 데스크톱/웹 레이아웃 가동
            bool isWebLayout = constraints.maxWidth >= 800;

            // --- 공통 위젯 A: 그래프 캔버스 영역 ---
            Widget canvasArea = Expanded(
              child: widgets.Stack(
                children: [
                  GestureDetector(
                    key: _canvasKey,
                    onTap: () => setState(() => _isKeyboardVisible = false),
                    onScaleStart: (details) {
                      baseMatrix = matrix.clone(); //
                      baseFocalPoint = details.focalPoint; //
                    },
                    onScaleUpdate: (details) {
                      setState(() {
                        final panDelta = details.focalPoint - baseFocalPoint; //
                        final panMatrix =
                            Matrix4.identity()
                              ..translate(panDelta.dx, panDelta.dy); //
                        final scale = details.scale; //
                        final focalPoint = details.localFocalPoint; //
                        final scaleMatrix =
                            Matrix4.identity() //
                              ..translate(focalPoint.dx, focalPoint.dy) //
                              ..scale(scale, scale) //
                              ..translate(-focalPoint.dx, -focalPoint.dy); //
                        matrix = panMatrix * scaleMatrix * baseMatrix; //
                      });
                    },
                    child: ClipRect(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: CoordinatePainter(
                          matrix: matrix, //
                          parser: _parser, //
                          graphItems: _graphItems, //
                          parameterA: _parameterA, //
                        ),
                      ),
                    ),
                  ),
                  if (_isVariablePanelVisible) //
                    Positioned(
                      left: 16,
                      top: 16,
                      right: 80, //
                      child: Container(
                        padding: const EdgeInsets.all(8), //
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9), //
                          borderRadius: BorderRadius.circular(12), //
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4),
                          ], //
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end, //
                          children: [
                            GestureDetector(
                              onTap:
                                  () => setState(
                                    () => _isVariablePanelVisible = false,
                                  ), //
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.grey,
                              ), //
                            ),
                            Row(
                              children: [
                                Text(
                                  'a = ${_parameterA.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ), //
                                Expanded(
                                  child: Slider(
                                    value: _parameterA,
                                    min: _minA,
                                    max: _maxA, //
                                    onChanged:
                                        (value) => setState(
                                          () =>
                                              _parameterA =
                                                  (value * 20).round() / 20.0,
                                        ), //
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      children: [
                        // 💥 [추가]: 초등학생이 아닐 때(중/고등)만 'a' 변수 버튼을 보여줍니다!
                        if (_selectedLevel != '초등') ...[
                          FloatingActionButton(
                            mini: true,
                            heroTag: "btn1",
                            onPressed: _showVariableDialog,
                            child: const Text(
                              'a',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ), //
                          ),
                          const SizedBox(height: 8),
                        ],
                        FloatingActionButton(
                          mini: true,
                          heroTag: "btn2",
                          onPressed: () => _zoom(1.5),
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton(
                          mini: true,
                          heroTag: "btn3",
                          onPressed: () => _zoom(1 / 1.5),
                          child: const Icon(Icons.remove),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton(
                          mini: true,
                          heroTag: "btn4",
                          onPressed: _resetView,
                          child: const Icon(Icons.home),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            // --- 공통 위젯 B: 제어 카드 리스트 ---
            Widget controlListArea = Container(
              color: Colors.grey[50], //
              child: ListView.builder(
                shrinkWrap: true, //
                itemCount: _graphItems.length, //
                itemBuilder:
                    (context, index) => _buildGraphControlCard(index), //
              ),
            );

            // --- 공통 위젯 C: 수식 추가 버튼과 키보드 패널 ---
            Widget inputControls = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0), //
                  child: IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: Colors.blue,
                      size: 36,
                    ), //
                    onPressed: _addExpressionField, //
                  ),
                ),
                if (_isKeyboardVisible) _buildKeyboard(), //
              ],
            );

            // ⭐️ [반응형 레이아웃 조립식 설계]
            if (isWebLayout) {
              // 🖥️ 1. 웹 레이아웃: 화면을 좌우(Row)로 찢어 왼쪽 패널, 오른쪽 그래프 배치
              return Row(
                children: [
                  // 왼쪽 수식 제어 사이드바 (가로 폭 380px 고정)
                  Container(
                    width: 380,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(child: controlListArea), // 수식 카드 리스트
                        inputControls, // 추가 버튼 및 가상 키보드
                      ],
                    ),
                  ),
                  // 오른쪽 광활한 캔버스 영역
                  canvasArea,
                ],
              );
            } else {
              // 📱 2. 핸드폰 레이아웃: 기존 구조 그대로 상하(Column) 배치
              return Column(
                children: [
                  canvasArea, // 상단 그래프 캔버스
                  Flexible(child: controlListArea), // 하단 수식 제어 카드
                  inputControls, // 추가 버튼 및 키보드
                ],
              );
            }
          },
        ),
      ),
    );
  }

  // --- 확장형 제어 카드 위젯 ---
  Widget _buildGraphControlCard(int index) {
    final item = _graphItems[index];
    final isFocused = (index == _focusedIndex) && _isKeyboardVisible;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      elevation: isFocused ? 2 : 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          // ⭐️ 수정 포인트 1: 교점 모드로 선택되면 노란색, 아니면 기존 포커스 색상 적용
          color:
              item.isSelectedForIntersection
                  ? Colors
                      .yellow
                      .shade700 // 교점 선택 시 노란색
                  : (isFocused ? Colors.blue : Colors.grey[300]!),
          width: (item.isSelectedForIntersection || isFocused) ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        // ⭐️ 수정 포인트 2: 카드 전체 클릭 시 교점 모드 토글을 위해 InkWell 추가
        borderRadius: BorderRadius.circular(16),
        onLongPress: () {
          // 길게 누르면 교점 모드 토글 (짧게 누르는 것과 충돌을 피하고 싶을 때 추천)
          _toggleIntersectionMode(index);
        },
        onDoubleTap: () {
          // 또는 더블 탭으로 설정 가능
          _toggleIntersectionMode(index);
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // ⭐️ 수정 포인트 3: 교점 모드일 때 번호 대신 아이콘을 보여주면 더 직관적입니다 (선택 사항)
                  item.isSelectedForIntersection
                      ? const Icon(
                        Icons.gps_fixed,
                        color: Colors.yellow,
                        size: 20,
                      )
                      : Math.tex(
                        r'y_{' + (index + 1).toString() + r'} =',
                        textStyle: TextStyle(
                          fontSize: 18,
                          color: item.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  const SizedBox(width: 8),
                  // 🛠️ [main.txt] 교정 후 코드 - 수식창 카드 에러 실시간 피드백 디자인
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          () => setState(() {
                            _focusedIndex = index;
                            _isKeyboardVisible = true;
                          }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          // ⭐️ [UX 스케일 업]: 에러가 있을 때는 배경을 연한 붉은색(Colors.red[50])으로 경고를 줍니다!
                          color:
                              item.errorMessage != null
                                  ? Colors.red[50]
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          // 테두리도 에러 시 붉은색으로 강조하여 교사/학생이 직관적으로 인지하게 만듭니다.
                          border: Border.all(
                            color:
                                item.errorMessage != null
                                    ? Colors.red.shade300
                                    : Colors.grey[300]!,
                            width: item.errorMessage != null ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          // 수식과 에러 메시지가 상하로 정렬되도록 Column을 배치하고 왼쪽 정렬을 강제합니다.
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // (1) 기존 수식 렌더링 영역
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Math.tex(
                                _toLatex(
                                  item.text.isEmpty ? ' ' : item.text,
                                  cursorOffset:
                                      isFocused
                                          ? _focusedController?.selection.start
                                          : null,
                                ),
                                textStyle: const TextStyle(fontSize: 18),
                              ),
                            ),

                            // ⭐️ [대완치 핵심 레이어]: 이 카드에 문법 에러 메시지가 등록되어 있다면 실시간 가이드를 출력합니다!
                            if (item.errorMessage != null) ...[
                              const SizedBox(
                                height: 6,
                              ), // 수식과 메시지 사이 숨통을 틔워주는 간격
                              Row(
                                children: [
                                  // 느낌표 에러 아이콘 배치
                                  const Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.red,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      item.errorMessage!,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 💥 [추가]: 초등학생은 고급 설정 탭(튜닝 아이콘) 자체를 숨깁니다!
                  if (_selectedLevel != '초등')
                    IconButton(
                      icon: Icon(
                        item.isExpanded ? Icons.tune : Icons.tune_outlined,
                        color: item.isExpanded ? Colors.blue : Colors.grey[600],
                      ),
                      onPressed:
                          () => setState(
                            () => item.isExpanded = !item.isExpanded,
                          ),
                    ),
                  if (_graphItems.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _removeExpressionField(index),
                    ),
                ],
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _buildAdvancedTools(index),
              crossFadeState:
                  item.isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  // --- ▼▼▼ 가로/세로 정중앙 정렬 및 오버플로우 해결본 ▼▼▼ ---
  Widget _buildAdvancedTools(int index) {
    final item = _graphItems[index];

    // ⭐️ 6개 버튼의 규격을 통일하고 상하좌우 중앙 정렬을 강제하는 공통 함수
    Widget buildUniformToggleBtn({
      required String labelText,
      required bool isSelected,
      required Color selectedColor,
      required Color checkmarkColor,
      required VoidCallback onTap,
      bool isLaTeX = false,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 92, // ⭐️ 가로를 92로 늘려 '\int f(x)dx'가 터지지 않게 방어합니다.
          height: 42, // ⭐️ 세로 크기도 넉넉하고 일관되게 고정합니다.
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? checkmarkColor : Colors.grey[300]!,
              width: 1,
            ),
          ),
          // ⭐️ 핵심: Container 내부에서 가로 및 세로 무조건 정중앙 정렬을 수행합니다.
          alignment: Alignment.center,
          child:
              isLaTeX
                  ? Math.tex(
                    labelText,
                    textStyle: TextStyle(
                      fontSize: 14,
                      color: isSelected ? checkmarkColor : Colors.black87,
                    ),
                  )
                  : Text(
                    labelText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? checkmarkColor : Colors.black87,
                    ),
                  ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const Divider(),
          const SizedBox(height: 8),

          // ⭐️ 6개의 고급 기능 제어 버튼들을 하나의 Wrap 안에 깔끔하게 배치하여 일관성을 줍니다.
          Wrap(
            spacing: 12, // 버튼 사이의 가로 여백
            runSpacing: 12, // 줄바꿈 시 세로 여백
            alignment: WrapAlignment.center, // 전체 행 가로 가운데 정렬
            children: [
              // 1. f'(x) 도함수 버튼 (고등학생 전용)
              if (_selectedLevel == '고등')
                buildUniformToggleBtn(
                  labelText: r"f'(x)",
                  isLaTeX: true,
                  isSelected: item.showDerivative,
                  selectedColor: Colors.red[50]!,
                  checkmarkColor: Colors.red[700]!,
                  onTap:
                      () => setState(
                        () => item.showDerivative = !item.showDerivative,
                      ),
                ),

              // 2. f^-1(x) 역함수 버튼 (고등학생 전용)
              if (_selectedLevel == '고등')
                buildUniformToggleBtn(
                  labelText: r"f^{-1}(x)",
                  isLaTeX: true,
                  isSelected: item.showInverse,
                  selectedColor: Colors.blue[50]!,
                  checkmarkColor: Colors.blue[700]!,
                  onTap:
                      () =>
                          setState(() => item.showInverse = !item.showInverse),
                ),

              // 3. ∫dx 정적분 버튼 (고등학생 전용)
              if (_selectedLevel == '고등')
                buildUniformToggleBtn(
                  labelText: r"\int f(x)dx",
                  isLaTeX: true,
                  isSelected: item.showIntegral,
                  selectedColor: Colors.green[50]!,
                  checkmarkColor: Colors.green[700]!,
                  onTap:
                      () => setState(
                        () => item.showIntegral = !item.showIntegral,
                      ),
                ),

              // 4. x절편 버튼 (중등, 고등 모두 허용)
              if (_selectedLevel == '중등' || _selectedLevel == '고등')
                buildUniformToggleBtn(
                  labelText: 'x절편',
                  isSelected: item.showXIntercepts,
                  selectedColor: Colors.purple[50]!,
                  checkmarkColor: Colors.purple[700]!,
                  onTap:
                      () => setState(
                        () => item.showXIntercepts = !item.showXIntercepts,
                      ),
                ),

              // 5. y절편 버튼 (중등, 고등 모두 허용)
              if (_selectedLevel == '중등' || _selectedLevel == '고등')
                buildUniformToggleBtn(
                  labelText: 'y절편',
                  isSelected: item.showYIntercepts,
                  selectedColor: Colors.orange[50]!,
                  checkmarkColor: Colors.orange[700]!,
                  onTap:
                      () => setState(
                        () => item.showYIntercepts = !item.showYIntercepts,
                      ),
                ),

              // 6. 극점 버튼 (고등학생 전용 - 극대/극소는 미적분 개념)
              if (_selectedLevel == '고등')
                buildUniformToggleBtn(
                  labelText: '극점',
                  isSelected: item.showExtrema,
                  selectedColor: Colors.amber[50]!,
                  checkmarkColor: Colors.amber[700]!,
                  onTap:
                      () =>
                          setState(() => item.showExtrema = !item.showExtrema),
                ),
            ],
          ),

          // ⭐️ 적분 버튼이 활성화되었을 때 아래로 독립적인 적분 구간 제어 패널 배치
          if (item.showIntegral) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.linear_scale,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '구간:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildIntegralInput(
                          r'a',
                          item.integralA,
                          () => _editIntegralBound(item, true),
                        ),
                        Math.tex(r'\sim'),
                        _buildIntegralInput(
                          r'b',
                          item.integralB,
                          () => _editIntegralBound(item, false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[500],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'S = ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Math.tex(
                          _calculateIntegral(item),
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  // --- ▲▲▲ 여기까지 덮어씌우기 ▲▲▲ ---

  // 🚨 [핵심 변경] 기존의 단순 Container를 InkWell(터치 반응)로 감쌌습니다!
  Widget _buildIntegralInput(String label, double value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap, // 터치 이벤트 연결
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.orange[300]!,
            width: 1.5,
          ), // 누를 수 있다는 걸 강조하기 위해 테두리 살짝 진하게
        ),
        child: Math.tex(
          '$label = ${value.toStringAsFixed(1)}',
          textStyle: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
  // --- ▲▲▲ 여기까지 복사 ▲▲▲ ---

  // --- 통합 2-탭 키보드 ---
  Widget _buildKeyboard() {
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabButton(0, '기본 (123 & x)', Icons.calculate_outlined),
                _buildTabButton(1, '함수 f(x)', Icons.functions),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),
          Padding(
            padding: const EdgeInsets.all(4.0),
            child:
                _keyboardTabIndex == 0 ? _buildBasicPad() : _buildFunctionPad(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _keyboardTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _keyboardTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.blue[700] : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.blue[700] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicPad() {
    // ⭐️ [핵심 컴공 매직]: 현재 키보드가 처한 가로 너비를 실시간으로 측정합니다.
    // 웹 사이드바 내부라면 constraints.maxWidth가 380 근처일 것입니다.
    return LayoutBuilder(
      builder: (context, constraints) {
        // 가로 폭이 400 미만(웹 사이드바 환경)이면 컴팩트 모드를 발동합니다.
        bool isCompact = constraints.maxWidth < 400;

        // 환경에 따른 부드러운 패딩 및 크기 스케일링 세팅
        double verticalPadding = isCompact ? 8.0 : 14.0;
        double iconSize = isCompact ? 18.0 : 22.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1단: 기능 제어 및 특수 기호 라인
            Row(
              children: [
                _buildKey(
                  'x',
                  bgColor: Colors.blue[50],
                  allowedLevels: ['중등', '고등'],
                ), // 방정식 변수 x
                _buildKey(
                  'a',
                  bgColor: Colors.blue[50],
                  allowedLevels: ['중등', '고등'],
                ), // 변수 a
                _buildKey('('),
                _buildKey(')'),
                _buildMathKey(
                  r'\Box^{\Box}',
                  '^',
                  allowedLevels: ['중등', '고등'],
                ), // 거듭제곱
                _buildMathKey(
                  r'\sqrt{\quad}',
                  'sqrt(',
                  allowedLevels: ['중등', '고등'],
                ), // 루트
                _buildMathKey(
                  r'|\Box|',
                  'abs(',
                  allowedLevels: ['중등', '고등'],
                ), // 절댓값
                // ◀ 왼쪽 이동 방향키 (반응형 크기 적용)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: verticalPadding,
                        ), // 👈 동적 패딩
                      ),
                      onPressed: () => _moveCursor(true),
                      child: Icon(
                        Icons.arrow_left,
                        color: Colors.indigo,
                        size: iconSize,
                      ), // 👈 동적 아이콘 크기
                    ),
                  ),
                ),
                // ▶ 오른쪽 이동 방향키 (반응형 크기 적용)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: verticalPadding,
                        ), // 👈 동적 패딩
                      ),
                      onPressed: () => _moveCursor(false),
                      child: Icon(
                        Icons.arrow_right,
                        color: Colors.indigo,
                        size: iconSize,
                      ), // 👈 동적 아이콘 크기
                    ),
                  ),
                ),

                // 백스페이스
                _buildActionKey(
                  Icons.backspace_outlined,
                  _onBackspacePressed,
                  bgColor: Colors.red[50],
                  iconColor: Colors.red,
                ),
              ],
            ),

            // 2단: 숫자 상단부 + 상수 + 연산자 2x2 상단
            Row(
              children: [
                _buildKey('7'),
                _buildKey('8'),
                _buildKey('9'),
                _buildKey('0'),
                _buildKey('.'),
                _buildMathKey(
                  r'e',
                  'e',
                  bgColor: Colors.green[50],
                  allowedLevels: ['고등'],
                ), // 자연상수
                _buildMathKey(
                  r'\pi',
                  'pi',
                  bgColor: Colors.green[50],
                  allowedLevels: ['중등', '고등'],
                ), // 파이
                const Spacer(),
                _buildKey('+', bgColor: Colors.orange[50]),
                _buildKey('-', bgColor: Colors.orange[50]),
              ],
            ),

            // 3단: 숫자 하단부 + 연산자 2x2 하단
            Row(
              children: [
                _buildKey('4'),
                _buildKey('5'),
                _buildKey('6'),
                _buildKey('1'),
                _buildKey('2'),
                _buildKey('3'),
                const Spacer(),
                const Spacer(),
                _buildMathKey(r'\times', '*', bgColor: Colors.orange[50]),
                _buildMathKey(r'\div', '/', bgColor: Colors.orange[50]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildFunctionPad() {
    return Column(
      children: [
        Row(
          children: [
            // sin, cos, tan는 초등학생에게는 숨김 (중등, 고등만 허용)
            _buildMathKey(r'\sin', 'sin(', allowedLevels: ['중등', '고등']),
            _buildMathKey(r'\cos', 'cos(', allowedLevels: ['중등', '고등']),
            _buildMathKey(r'\tan', 'tan(', allowedLevels: ['중등', '고등']),
          ],
        ),
        Row(
          children: [
            // csc, sec, cot, ln, log 등은 고등학생에게만 허용
            _buildMathKey(r'\csc', 'csc(', allowedLevels: ['고등']),
            _buildMathKey(r'\sec', 'sec(', allowedLevels: ['고등']),
            _buildMathKey(r'\cot', 'cot(', allowedLevels: ['고등']),
          ],
        ),
        Row(
          children: [
            _buildMathKey(r'\ln', 'ln(', allowedLevels: ['고등']),
            _buildMathKey(r'\log', 'log(', allowedLevels: ['고등']),
            _buildActionKey(
              // 백스페이스는 항상 보여야 함
              Icons.backspace_outlined,
              _onBackspacePressed,
              bgColor: Colors.red[50],
              iconColor: Colors.red,
            ),
          ],
        ),
      ],
    );
  }

  // 파라미터에 allowedLevels 추가
  Widget _buildKey(
    String label, {
    Color? bgColor,
    List<String>? allowedLevels,
  }) {
    // 💥 [권한 검사]
    bool isDisabled =
        allowedLevels != null && !allowedLevels.contains(_selectedLevel);

    return Expanded(
      child: Opacity(
        opacity: isDisabled ? 0.0 : 1.0,
        child: IgnorePointer(
          ignoring: isDisabled,
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: bgColor ?? Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 0,
                ),
              ),
              // 💥 [대완치 핵심]: _onKeyPressed를 단순히 호출하던 구조를 버리고,
              // 단추 터치 시점에 컨트롤러의 가상 커서 인덱스를 정밀하게 동적 역추적하여 묶어버립니다!
              onPressed: () {
                final controller = _focusedController;
                if (controller == null) return;

                final text = controller.text;
                final selection = controller.selection;
                int start = selection.start;
                int end = selection.end;

                if (start < 0) {
                  start = text.length;
                  end = text.length;
                }

                // 문자를 주입한 가공 텍스트 생성
                final newText = text.replaceRange(start, end, label);

                // ⭐️ [자석 스냅]: 입력된 글자(label)의 바로 뒷공간부터 인덱스를 검색하도록 오프셋 마진을 계산합니다.
                int targetOffset = start + label.length;
                int searchStartIndex = start + label.length;

                if (searchStartIndex <= newText.length &&
                    newText.contains(label, start)) {
                  targetOffset = newText.indexOf(label, start) + label.length;
                }

                // 유효성 바운더리 체크 후 단 한 번의 트랜잭션으로 주입!
                if (targetOffset >= 0 && targetOffset <= newText.length) {
                  controller.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(
                      offset: targetOffset,
                    ), // 👈 무조건 문자 '오른쪽 뒤'에 커서 스냅!
                  );

                  setState(() {
                    _graphItems[_focusedIndex].text = newText;
                  });
                }
              },
              child: Text(
                label,
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 파라미터에 allowedLevels 추가
  Widget _buildMathKey(
    String tex,
    String insertText, {
    Color? bgColor,
    List<String>? allowedLevels,
  }) {
    // 💥 [권한 검사]
    bool isDisabled =
        allowedLevels != null && !allowedLevels.contains(_selectedLevel);
    return Expanded(
      // ⭐️ [복구 완료]: Opacity와 IgnorePointer 추가!
      child: Opacity(
        opacity: isDisabled ? 0.0 : 1.0,
        child: IgnorePointer(
          ignoring: isDisabled,
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: bgColor ?? Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 0,
                ),
              ),
              onPressed: () {
                final controller = _focusedController;
                if (controller == null) return;

                final text = controller.text;
                final selection = controller.selection;
                int start = selection.start;
                int end = selection.end;

                if (start < 0) {
                  start = text.length;
                  end = text.length;
                }

                // 💥 [대완치 커널 레이어]: 괄호 엄밀성과 다글자 토큰 붕괴를 막기 위해
                // 주입 문자열과 전진할 커서의 상대 길이를 단 하나의 트랜잭션 안에서 연산합니다.
                String textToInsert = insertText;
                int cursorShift = insertText.length;

                if (insertText == 'sqrt(') {
                  textToInsert = 'sqrt()';
                  cursorShift = 5; // 'sqrt(' 안쪽 정중앙에 커서를 정확히 스냅하기 위한 오프셋
                } else if (insertText == 'abs(') {
                  textToInsert = 'abs()';
                  cursorShift = 4; // 'abs(' 안쪽 정중앙에 커서를 정확히 스냅하기 위한 오프셋
                }

                final newText = text.replaceRange(start, end, textToInsert);
                final int targetOffset = start + cursorShift;

                // 🛡️ 철벽 경계선 마진 가드: 계산된 최종 타겟 인덱스가 유효 범위를 절대 탈출하지 못하게 물리적으로 묶어둡니다.
                if (targetOffset >= 0 && targetOffset <= newText.length) {
                  controller.value = TextEditingValue(
                    text: newText,
                    selection: TextSelection.collapsed(offset: targetOffset),
                  );

                  setState(() {
                    _graphItems[_focusedIndex].text = newText;
                  });
                }
              },
              child: Math.tex(
                tex,
                textStyle: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🛠️ main.txt - Line 482~484 부근 _buildActionKey 함수 전체 Overwrite 교체본
  // ⭐️ [이중 터치 이벤트 전면 제거 및 레드스크린 영원한 박멸 마스터피스]
  Widget _buildActionKey(
    IconData icon,
    VoidCallback onPressed, {
    Color? bgColor,
    Color? iconColor,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(
          2.0,
        ), // 다른 단추들과 정갈하게 패딩 여백 맞춤 (4.0 -> 2.0)
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: bgColor ?? Colors.white, //
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8), // 둥근 테두리 반경 일치 (12 -> 8)
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 12.0,
              horizontal: 0,
            ), // 높이 스케일 완전 동기화
          ),
          onPressed: onPressed, // 🎯 오직 이 정석 루트로만 단 한 번 깨끗하게 실행!
          // 💥 [대완치 핵심]: 중복 탭을 유발하여 시스템 인덱스를 파괴하던
          // 불필요한 자식 InkWell 위젯 레이어를 완벽하게 도려냈습니다!
          child: Icon(
            icon,
            color: iconColor ?? Colors.black54,
            size: 22, // 삼각함수 단추 아이콘들과 크기 밸런스 매칭 (24 -> 22)
          ),
        ),
      ),
    );
  }

  void _toggleIntersectionMode(int index) {
    setState(() {
      // 1. 선택 상태 토글
      _graphItems[index].isSelectedForIntersection =
          !_graphItems[index].isSelectedForIntersection;

      // 2. 선택된 아이템만 추출
      var selectedItems =
          _graphItems.where((item) => item.isSelectedForIntersection).toList();

      if (selectedItems.length == 2) {
        final double viewportWidth = MediaQuery.of(context).size.width;
        final invertedMatrix = Matrix4.inverted(matrix);

        final double minX =
            invertedMatrix.transform3(vector_math.Vector3(0, 0, 0)).x - 1.0;
        final double maxX =
            invertedMatrix
                .transform3(vector_math.Vector3(viewportWidth, 0, 0))
                .x +
            1.0;

        final points = MathAnalyzer.findIntersections(
          f: selectedItems[0].text,
          g: selectedItems[1].text,
          minX: minX,
          maxX: maxX,
          paramA: _parameterA,
        );

        // ⭐️ [안전한 교체]: 각 아이템의 본래 color를 절대 건드리지 않고,
        // 오직 교점 좌표 배열(intersectionPoints) 데이터만 갱신하도록 분리합니다.
        for (int i = 0; i < _graphItems.length; i++) {
          if (_graphItems[i].isSelectedForIntersection) {
            _graphItems[i].intersectionPoints = List.from(points); // 깊은 복사로 격리
          } else {
            _graphItems[i].intersectionPoints = const [];
          }
        }
      } else {
        // 2개가 아닐 때는 안전하게 좌표만 초기화 (색상은 보존)
        for (var item in _graphItems) {
          item.intersectionPoints = const [];
        }
      }
    });
  }
}

// --- 그래프 렌더링 엔진 ---
class CoordinatePainter extends CustomPainter {
  final Matrix4 matrix;
  final FunctionParser parser;
  final List<GraphItem> graphItems;
  final double parameterA;

  CoordinatePainter({
    required this.matrix,
    required this.parser,
    required this.graphItems,
    required this.parameterA,
  });

  int _getDecimalPlaces(double value) {
    if (value.abs() >= 1.0) return 0;
    if (value.abs() < 1e-10) return 10;
    final places = (-math.log(value.abs()) / math.ln10).ceil();
    return places > 10 ? 10 : places;
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    TextAlign align = TextAlign.left,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black, fontSize: 10.0),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(minWidth: 0, maxWidth: 100);
    Offset effectiveOffset;
    if (align == TextAlign.center) {
      effectiveOffset = Offset(offset.dx - textPainter.width / 2, offset.dy);
    } else if (align == TextAlign.right) {
      effectiveOffset = Offset(
        offset.dx - textPainter.width,
        offset.dy - textPainter.height / 2,
      );
    } else {
      effectiveOffset = Offset(offset.dx, offset.dy);
    }
    textPainter.paint(canvas, effectiveOffset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    final Matrix4 invertedMatrix = Matrix4.inverted(matrix);
    final Rect viewBounds = Rect.fromPoints(
      invertedMatrix.transform3(vector_math.Vector3(0, 0, 0)).toOffset(),
      invertedMatrix
          .transform3(vector_math.Vector3(size.width, size.height, 0))
          .toOffset(),
    );
    final double currentScale = matrix.row0.x;
    final double targetPixelsPerTick = 80.0;
    final double desiredTickUnit = targetPixelsPerTick / currentScale;
    final double power =
        math
            .pow(10.0, (math.log(desiredTickUnit) / math.ln10).floor())
            .toDouble();
    final double normalizedTick = desiredTickUnit / power;
    double tickUnit;
    if (normalizedTick < 1.5)
      tickUnit = 1.0 * power;
    else if (normalizedTick < 3.5)
      tickUnit = 2.0 * power;
    else if (normalizedTick < 7.5)
      tickUnit = 5.0 * power;
    else
      tickUnit = 10.0 * power;
    final double minorTickUnit = tickUnit / 5.0;

    final axisPaint =
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1.0;
    final gridPaint =
        Paint()
          ..color = const Color.fromRGBO(158, 158, 158, 0.4)
          ..strokeWidth = 0.5;
    final minorGridPaint =
        Paint()
          ..color = const Color.fromRGBO(158, 158, 158, 0.2)
          ..strokeWidth = 0.5;

    final int startGridXIndex = (viewBounds.left / minorTickUnit).floor();
    final int endGridXIndex = (viewBounds.right / minorTickUnit).ceil();
    for (int i = startGridXIndex; i <= endGridXIndex; i++) {
      final double x = i * minorTickUnit;
      final bool isMajorGrid =
          (x / tickUnit).remainder(1.0).abs() < 1e-9 ||
          (x / tickUnit).remainder(1.0).abs() > (1 - 1e-9);
      final screenStart = matrix.transform3(
        vector_math.Vector3(x, viewBounds.top, 0),
      );
      final screenEnd = matrix.transform3(
        vector_math.Vector3(x, viewBounds.bottom, 0),
      );
      canvas.drawLine(
        screenStart.toOffset(),
        screenEnd.toOffset(),
        isMajorGrid ? gridPaint : minorGridPaint,
      );
      if (isMajorGrid) {
        double displayX = x;
        if (x.abs() < 1e-9) displayX = 0;
        if (displayX != 0) {
          final screenPoint = matrix.transform3(vector_math.Vector3(x, 0, 0));
          _drawText(
            canvas,
            displayX.toStringAsFixed(_getDecimalPlaces(tickUnit)),
            Offset(screenPoint.x, screenPoint.y + 4),
            align: TextAlign.center,
          );
        }
      }
    }
    final int startGridYIndex = (viewBounds.top / minorTickUnit).floor();
    final int endGridYIndex = (viewBounds.bottom / minorTickUnit).ceil();
    for (int i = startGridYIndex; i <= endGridYIndex; i++) {
      final double y = i * minorTickUnit;
      if (y.abs() < 1e-9) continue;
      final bool isMajorGrid =
          (y / tickUnit).remainder(1.0).abs() < 1e-9 ||
          (y / tickUnit).remainder(1.0).abs() > (1 - 1e-9);
      final screenStart = matrix.transform3(
        vector_math.Vector3(viewBounds.left, y, 0),
      );
      final screenEnd = matrix.transform3(
        vector_math.Vector3(viewBounds.right, y, 0),
      );
      canvas.drawLine(
        screenStart.toOffset(),
        screenEnd.toOffset(),
        isMajorGrid ? gridPaint : minorGridPaint,
      );
      if (isMajorGrid) {
        final screenPoint = matrix.transform3(vector_math.Vector3(0, y, 0));
        _drawText(
          canvas,
          (-y).toStringAsFixed(_getDecimalPlaces(tickUnit)),
          Offset(screenPoint.x - 4, screenPoint.y),
          align: TextAlign.right,
        );
      }
    }
    final xStart = matrix.transform3(
      vector_math.Vector3(viewBounds.left, 0, 0),
    );
    final xEnd = matrix.transform3(vector_math.Vector3(viewBounds.right, 0, 0));
    canvas.drawLine(xStart.toOffset(), xEnd.toOffset(), axisPaint);
    final yStart = matrix.transform3(vector_math.Vector3(0, viewBounds.top, 0));
    final yEnd = matrix.transform3(
      vector_math.Vector3(0, viewBounds.bottom, 0),
    );
    canvas.drawLine(yStart.toOffset(), yEnd.toOffset(), axisPaint);
    final originPoint = matrix.transform3(vector_math.Vector3(0, 0, 0));
    _drawText(
      canvas,
      "0",
      Offset(originPoint.x + 4, originPoint.y + 4),
      align: TextAlign.left,
    );

    // 🛠️ [main.txt] Line 479번 부근 최상단 1차 가드 구역 전체 교체
    // ⭐️ [asin, asec 등 6대 초월함수 묵시적 곱셈 최상단 가드 마스터피스]
    for (int i = 0; i < graphItems.length; i++) {
      final item = graphItems[i];
      if (item.text.isEmpty) {
        item.errorMessage = null;
        continue;
      }

      String validationTarget = item.text.replaceAll(' ', '');

      // 💥 [최상단 완치 핵심]: 문법 검증용 파서에 들어가기 '가장 먼저'
      // 6대 삼각함수 및 고급 예약어와 변수 a의 밀착 결합을 정밀하게 타격하여 a*f(x) 포맷으로 강제 분리합니다!
      validationTarget = validationTarget.replaceAllMapped(
        RegExp(r'a(sin|cos|tan|csc|sec|cot|ln|log|sqrt|abs)'),
        (Match m) => 'a*${m.group(1)}',
      );

      // csc, sec, cot 삼형제를 수치해석 분수식 구조로 치환 동기화
      validationTarget = validationTarget.replaceAll('csc', '1/sin');
      validationTarget = validationTarget.replaceAll('sec', '1/cos');
      validationTarget = validationTarget.replaceAll('cot', '1/tan');

      if (!validationTarget.contains(';')) {
        validationTarget = validationTarget.replaceAllMapped(
          RegExp(r'\^(?!\()([^;^]+)'), // 여기는 렌더링이 아니라 연산이므로 ( 를 방어합니다!
          (Match m) => '^(${m.group(1)})',
        );
      } else {
        validationTarget = validationTarget.replaceAllMapped(
          RegExp(r'\^(?!\()([^;^]+);'),
          (Match m) => '^(${m.group(1)})',
        );
        validationTarget = validationTarget.replaceAllMapped(
          RegExp(r'\^(?!\()([^;^]+)'),
          (Match m) => '^(${m.group(1)})',
        );
        validationTarget = validationTarget.replaceAll(';', '');
      }

      validationTarget = validationTarget.replaceAllMapped(
        RegExp(r'(sqrt|sin|cos|tan|ln|log|abs)(?!\()([xa\d]+|pi|e)'),
        (m) => '${m[1]}(${m[2]})',
      );

      String finalSafeCheckStr = validationTarget.replaceAllMapped(
        RegExp(r'(\d)([a-zA-Z])'),
        (Match m) => '${m[1]}*${m[2]}',
      );

      // 변수와 변수끼리 연속 뭉침 현상 최종 제거 (ax -> a*x)
      for (int b = 0; b < 2; b++) {
        finalSafeCheckStr = finalSafeCheckStr.replaceAllMapped(
          RegExp(r'(x|a|pi|e)(x|a|pi|e)'),
          (m) => '${m[1]}*${m[2]}',
        );
      }

      // 💥 [추가 2]: 파서가 문법을 검증할 때 e를 지수 표기법으로 오독하지 않도록 안전한 상수로 선행 치환!
      finalSafeCheckStr = finalSafeCheckStr.replaceAll('pi', '3.14');
      finalSafeCheckStr = finalSafeCheckStr.replaceAll('e', '2.71');

      try {
        Parser().parse(finalSafeCheckStr);
        item.errorMessage = null;
      } catch (e) {
        String msg = "올바르지 않은 수식입니다.";
        if (item.text.contains('(') && !item.text.contains(')')) {
          msg = "열린 괄호 '(' 에 대응하는 닫는 괄호 ')'가 없습니다.";
        } else if (item.text.endsWith('+') ||
            item.text.endsWith('-') ||
            item.text.endsWith('*') ||
            item.text.endsWith('/')) {
          msg = "수식이 연산자('${item.text[item.text.length - 1]}')로 끝날 수 없습니다.";
        } else if (item.text.contains('^') &&
            item.text.split('^').last.isEmpty) {
          msg = "거듭제곱(^) 뒤에 지수 값이 입력되지 않았습니다.";
        } else if (item.text.contains('/0')) {
          msg = "수학적으로 분모는 0이 될 수 없습니다. (Zero Division)";
        }

        item.errorMessage = msg;
        continue;
      }

      // ⭐️ [이 구역 전체를 아래 코드로 정밀 교체합니다]
      String expression = item.text;

      // ⭐️ [신설]: 백엔드 연산 레이어 가동 전, sec, csc, cot를 파서 엔진과 일치하게 1/cos, 1/sin, 1/tan로 쪼개어 동기화합니다.
      expression = expression.replaceAll('csc', '1/sin');
      expression = expression.replaceAll('sec', '1/cos');
      expression = expression.replaceAll('cot', '1/tan');

      // (1) 연속으로 입력된 무리수 상수 패턴 사이에 곱하기(*) 기호를 강제 주입하여 독립 토큰화합니다.
      expression = expression.replaceAllMapped(
        RegExp(r'(pi|e)(?=(pi|e))'),
        (Match m) => '${m.group(1)} * ',
      );

      // (2) 모든 결합 방향의 묵시적 곱셈 패턴 완벽 분리
      expression = expression.replaceAll('ex', 'e * x');
      expression = expression.replaceAll('xe', 'x * e');
      expression = expression.replaceAll('pix', 'pi * x');
      expression = expression.replaceAll('xpi', 'x * pi');
      expression = expression.replaceAll('e(', 'e * (');
      expression = expression.replaceAll('pi(', 'pi * (');

      // (3) ⭐️ [백엔드 연산 핵심]: 컴퓨터가 식을 계산하기 직전에 로그함수 예약어들을
      // 임시 캐릭터 문자인 대문자 'LN', 'LOG' 형태로 변환하여 대수적 대피(격리)를 시켜둡니다!
      expression = expression
          .replaceAll('sin', 'SIN')
          .replaceAll('cos', 'COS')
          .replaceAll('tan', 'TAN')
          .replaceAll('ln', 'LN')
          .replaceAll('log', 'LOG')
          .replaceAll('abs', 'ABS')
          .replaceAll('sqrt', 'SQRT');

      // (4) 방해꾼들이 모두 대피했으므로, 단어 족쇄(\b) 없이 모든 e와 pi를
      // 순수 실수 무리수 값 데이터로 완벽하고 깔끔하게 1대1 치환합니다!
      expression = expression.replaceAll('pi', '3.14159265359');
      expression = expression.replaceAll(
        'e',
        '2.71828182846',
      ); // 👈 이제 ee든 xe든 100% 연산 성공

      // (5) 무리수 변환이 끝났으므로 대피해 두었던 함수 이름들을 원래 소문자로 안전하게 원상복구합니다.
      expression = expression
          .replaceAll('SIN', 'sin')
          .replaceAll('COS', 'cos')
          .replaceAll('TAN', 'tan')
          .replaceAll('LN', 'ln')
          .replaceAll('LOG', 'log')
          .replaceAll('ABS', 'abs')
          .replaceAll('SQRT', 'sqrt');

      final graphPaint =
          Paint()
            ..color = item.color
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;

      final path = Path();
      bool isFirstPoint = true;
      double? lastScreenY;
      final double jumpThreshold = size.height * 0.5;

      // =========================================================================
      // 🎯 [렉 박멸+초정밀 통합본] 성능 최적화형 범용 경계선 동적 추적 엔진
      // =========================================================================
      // ⭐️ [초대완치 핵심]: 전체 화면 scale 배율에 맞춰 부동소수점 오차 마진을 동적으로 계산합니다.
      double? lastValidX;
      double? lastValidY;

      for (double screenX = 0; screenX < size.width; screenX += 1) {
        final graphX =
            invertedMatrix.transform3(vector_math.Vector3(screenX, 0, 0)).x;
        double graphY = parser.evaluate(
          expression,
          graphX,
          params: {'a': parameterA},
        );

        // 💥 [양방향 대완치 레이어]: NaN 상태의 변화(안에서 밖으로 탈출할 때) 가드
        if (graphY.isNaN) {
          if (!isFirstPoint && lastValidX != null && lastValidY != null) {
            // 안에서 밖으로 나가는 우측 경계선 정밀 마감
            double validX = lastValidX;
            double invalidX = graphX;
            for (int b = 0; b < 8; b++) {
              double midX = (validX + invalidX) / 2.0;
              double midY = parser.evaluate(
                expression,
                midX,
                params: {'a': parameterA},
              );
              if (!midY.isNaN && !midY.isInfinite) {
                validX = midX;
              } else {
                invalidX = midX;
              }
            }
            final double edgeY = parser.evaluate(
              expression,
              validX,
              params: {'a': parameterA},
            );
            if (!edgeY.isNaN && !edgeY.isInfinite) {
              final edgeScreenPoint = matrix.transform3(
                vector_math.Vector3(validX, -edgeY, 0),
              );
              path.lineTo(edgeScreenPoint.x, edgeScreenPoint.y);
            }
          }
          isFirstPoint = true; //
          lastScreenY = null; //
          continue; //
        }

        if (graphY.isInfinite) {
          //
          isFirstPoint = true; //
          lastScreenY = null; //
          continue; //
        }

        // 💥 [양방향 대완치 핵심]: 밖에서 안으로 들어오는 좌측 경계선 정밀 마감
        // 직전에 선이 끊겨있던 상태(isFirstPoint == true)에서 처음으로 유효한 NaN 탈출 점을 만났을 때 가동!
        if (isFirstPoint && screenX > 0) {
          final double prevGraphX =
              invertedMatrix
                  .transform3(vector_math.Vector3(screenX - 1, 0, 0))
                  .x;
          double invalidX = prevGraphX;
          double validX = graphX;

          // 이분법으로 좌측 벼랑 끝의 진짜 시작점을 역추적
          for (int b = 0; b < 8; b++) {
            double midX = (validX + invalidX) / 2.0;
            double midY = parser.evaluate(
              expression,
              midX,
              params: {'a': parameterA},
            );
            if (!midY.isNaN && !midY.isInfinite) {
              validX = midX;
            } else {
              invalidX = midX;
            }
          }

          final double edgeY = parser.evaluate(
            expression,
            validX,
            params: {'a': parameterA},
          );
          if (!edgeY.isNaN && !edgeY.isInfinite) {
            final edgeScreenPoint = matrix.transform3(
              vector_math.Vector3(validX, -edgeY, 0),
            );
            path.moveTo(
              edgeScreenPoint.x,
              edgeScreenPoint.y,
            ); // 진짜 경계선 시작점으로 워프!
            isFirstPoint = false;
          }
        }

        final screenPoint = matrix.transform3(
          vector_math.Vector3(graphX, -graphY, 0),
        ); //

        // 점근선 가드 레이어 유지 [cite: 506]
        bool shouldBreakLine = false; //
        if (lastScreenY != null) {
          //
          bool hasAsymptote =
              expression.contains('/') || //
              expression.contains('TAN') || //
              expression.contains('tan') || //
              item.text.contains('cot') || //
              item.text.contains('csc') || //
              item.text.contains('sec'); //

          if (hasAsymptote &&
              (screenPoint.y - lastScreenY).abs() > jumpThreshold) {
            //
            if ((screenPoint.y < 0 && lastScreenY > size.height) || //
                (screenPoint.y > size.height && lastScreenY < 0)) {
              //
              shouldBreakLine = true; //
            }
          }
        }

        if (isFirstPoint || shouldBreakLine) {
          //
          path.moveTo(screenPoint.x, screenPoint.y); //
          isFirstPoint = false; //
        } else {
          path.lineTo(screenPoint.x, screenPoint.y); //
        }

        lastValidX = graphX;
        lastValidY = graphY;
        lastScreenY = screenPoint.y; //
      }
      canvas.drawPath(path, graphPaint);

      // ⭐️ [추가] 교점(Intersection) 시각화
      final paintIntersection =
          Paint()
            ..color = Colors.yellow
            ..style = PaintingStyle.fill;
      for (var item in graphItems) {
        for (var point in item.intersectionPoints) {
          // ⭐️ 중요: 단순 계산 대신 matrix를 이용한 벡터 변환을 사용해야 합니다.
          // 기존에 그래프 선을 그릴 때 사용하던 방식과 일치시킵니다.
          final screenPoint = matrix.transform3(
            vector_math.Vector3(point.dx, -point.dy, 0),
          );

          final double screenX = screenPoint.x;
          final double screenY = screenPoint.y;

          // 화면 범위 안에 있을 때만 그리기
          if (screenX >= 0 &&
              screenX <= size.width &&
              screenY >= 0 &&
              screenY <= size.height) {
            canvas.drawCircle(Offset(screenX, screenY), 6.0, paintIntersection);

            // ⭐️ 변수를 올바르게 정의하여 에러를 해결합니다.
            final String exactX = toExactString(point.dx);
            final String exactY = toExactString(point.dy);

            final tp = TextPainter(
              text: TextSpan(
                text: "($exactX, $exactY)", // 👈 정수나 예쁜 분수로 표현됨
                style: const TextStyle(
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  backgroundColor: Colors.black54,
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, Offset(screenX + 10, screenY - 20));
          }
        }
      }

      // 1. 역함수 (Inverse) 그리기
      if (item.showInverse) {
        final inversePaint =
            Paint()
              ..color = item.color.withOpacity(0.4)
              ..strokeWidth = 2.0
              ..style = PaintingStyle.stroke;

        final invPath = Path();
        bool invFirst = true;
        double? lastInvScreenX;
        final double invJumpThreshold = size.width * 0.5;

        for (double screenY = 0; screenY < size.height; screenY += 1) {
          final t =
              -invertedMatrix.transform3(vector_math.Vector3(0, screenY, 0)).y;
          final ft = parser.evaluate(expression, t, params: {'a': parameterA});

          if (ft.isNaN || ft.isInfinite) {
            invFirst = true;
            lastInvScreenX = null;
            continue;
          }

          final screenPoint = matrix.transform3(vector_math.Vector3(ft, -t, 0));

          bool shouldBreakLine = false;
          if (lastInvScreenX != null) {
            if ((screenPoint.x - lastInvScreenX).abs() > invJumpThreshold) {
              shouldBreakLine = true;
            }
          }

          if (invFirst || shouldBreakLine) {
            invPath.moveTo(screenPoint.x, screenPoint.y);
            invFirst = false;
          } else {
            invPath.lineTo(screenPoint.x, screenPoint.y);
          }
          lastInvScreenX = screenPoint.x;
        }
        canvas.drawPath(invPath, inversePaint);
      }

      // 2. 도함수 (Derivative) 그리기
      if (item.showDerivative) {
        final derivPaint =
            Paint()
              ..color = Colors.redAccent
              ..strokeWidth = 2.0
              ..style = PaintingStyle.stroke;

        final derivPath = Path();
        bool derivFirst = true;
        final double h = 0.0001;

        double? lastDerivScreenY;
        final double derivJumpThreshold = size.height * 0.5;

        for (double screenX = 0; screenX < size.width; screenX += 2) {
          final graphX =
              invertedMatrix.transform3(vector_math.Vector3(screenX, 0, 0)).x;

          final yPlus = parser.evaluate(
            expression,
            graphX + h,
            params: {'a': parameterA},
          );
          final yMinus = parser.evaluate(
            expression,
            graphX - h,
            params: {'a': parameterA},
          );

          if (yPlus.isNaN || yMinus.isNaN) {
            derivFirst = true;
            continue;
          }

          final derivativeY = (yPlus - yMinus) / (2 * h);
          final screenPoint = matrix.transform3(
            vector_math.Vector3(graphX, -derivativeY, 0),
          );

          bool shouldBreakLine = false;
          if (lastDerivScreenY != null) {
            if ((screenPoint.y - lastDerivScreenY).abs() > derivJumpThreshold) {
              shouldBreakLine = true;
            }
          }

          if (derivFirst || shouldBreakLine) {
            derivPath.moveTo(screenPoint.x, screenPoint.y);
            derivFirst = false;
          } else {
            derivPath.lineTo(screenPoint.x, screenPoint.y);
          }
          lastDerivScreenY = screenPoint.y;
        }
        canvas.drawPath(derivPath, derivPaint);
      }

      // 3. 정적분 (Integral) 색칠하기
      if (item.showIntegral) {
        final integralPaint =
            Paint()
              ..color = Colors.orange.withOpacity(0.3)
              ..style = PaintingStyle.fill;

        final integralPath = Path();
        final double paintStart = math.min(item.integralA, item.integralB);
        final double paintEnd = math.max(item.integralA, item.integralB);

        if (paintStart < paintEnd) {
          final startScreen = matrix.transform3(
            vector_math.Vector3(paintStart, 0, 0),
          );
          integralPath.moveTo(startScreen.x, startScreen.y);

          final double step = (paintEnd - paintStart) / 100;
          for (double x = paintStart; x <= paintEnd; x += step) {
            final y = parser.evaluate(expression, x, params: {'a': parameterA});
            if (y.isNaN || y.isInfinite) continue;
            final screenPoint = matrix.transform3(
              vector_math.Vector3(x, -y, 0),
            );
            integralPath.lineTo(screenPoint.x, screenPoint.y);
          }

          final endScreen = matrix.transform3(
            vector_math.Vector3(paintEnd, 0, 0),
          );
          integralPath.lineTo(endScreen.x, endScreen.y);
          integralPath.close();

          canvas.drawPath(integralPath, integralPaint);
        }
      }

      // =========================================================================
      // 🎯 [변수 a × 6대 삼각함수 완벽 호환] 절편/극점 대수 전처리 엔진 최종 결정판
      // =========================================================================
      try {
        String parsedTarget = item.text.replaceAll(' ', ''); // // [cite: 639]

        parsedTarget = parsedTarget.replaceAllMapped(
          RegExp(r'a(sin|cos|tan|csc|sec|cot|ln|log|sqrt|abs)'),
          (Match m) => 'a*${m.group(1)}',
        ); // // [cite: 641]

        // 💥 [순서 대교정 핵심]: abs와 sqrt 등의 문자 구조를 다항 지수식 및 곱셈 기호 분리
        // '가장 먼저' 배치하여 괄호 짝 불일치로 인한 RangeError 싱크홀을 완벽 차단합니다!
        parsedTarget = parsedTarget.replaceAll(
          'csc',
          '1/sin',
        ); // // [cite: 642]
        parsedTarget = parsedTarget.replaceAll(
          'sec',
          '1/cos',
        ); // // [cite: 642]
        parsedTarget = parsedTarget.replaceAll(
          'cot',
          '1/tan',
        ); // // [cite: 643]

        if (!parsedTarget.contains(';')) {
          parsedTarget = parsedTarget.replaceAllMapped(
            RegExp(r'\^([a-zA-Z0-9.+/*=-]+)'),
            (Match m) => '^(${m.group(1)})',
          ); // // [cite: 643]
        } else {
          parsedTarget = parsedTarget.replaceAllMapped(
            RegExp(r'\^([^;]+);'),
            (Match m) => '^(${m.group(1)})',
          ); // // [cite: 644]
          parsedTarget = parsedTarget.replaceAll(';', ''); // // [cite: 645]
        }

        parsedTarget = parsedTarget.replaceAllMapped(
          RegExp(r'(x|a|pi|e)(\(|sin|cos|tan|log|ln|sqrt|abs)'),
          (m) => '${m[1]}*${m[2]}',
        ); // // [cite: 645]

        parsedTarget = parsedTarget.replaceAllMapped(
          RegExp(r'([\d.]+)([a-zA-Z(])'),
          (Match m) => '${m[1]}*${m[2]}',
        ); // // [cite: 646]
        parsedTarget = parsedTarget.replaceAllMapped(
          RegExp(r'([a-zA-Z])([\d.]+)'),
          (Match m) => '${m[1]}*${m[2]}',
        ); // // [cite: 646]

        for (int b = 0; b < 2; b++) {
          parsedTarget = parsedTarget.replaceAllMapped(
            RegExp(r'(x|a|pi|e)(x|a|pi|e)'),
            (m) => '${m[1]}*${m[2]}',
          ); // // [cite: 647]
        }

        parsedTarget = parsedTarget.replaceAllMapped(
          RegExp(r'(sqrt|sin|cos|tan|ln|log|abs)(?!\()([xa\d]+|pi|e)'),
          (m) => '${m[1]}(${m[2]})',
        ); // // [cite: 647]

        final parsedExpression = Parser().parse(parsedTarget);
        final double mathStartX = viewBounds.left; //
        final double mathEndX = viewBounds.right; //

        // 1. 점들을 모아둘 바구니 생성 및 잔상 비우기 [cite: 589, 590]
        List<GraphMarker> markers = [];
        markers.clear(); // [cite: 590]

        // 중복 확인하며 바구니에 점을 넣는 내부 헬퍼 함수 [cite: 590]
        void addMarker(double x, double y, String type, Color color) {
          if (x < mathStartX || x > mathEndX) return; // [cite: 590]
          for (var m in markers) {
            // [cite: 591]
            if ((m.x - x).abs() < 0.1 && (m.y - y).abs() < 0.1) {
              // [cite: 591]
              if (type == "극점" &&
                  (m.types.contains("극솟값") || m.types.contains("극댓값")))
                return; // [cite: 592]
              if ((type == "극솟값" || type == "극댓값") && m.types.contains("극점"))
                m.types.remove("극점"); // [cite: 594]
              if (!m.types.contains(type)) m.types.add(type); // [cite: 595]
              if (type == "극소" ||
                  type == "극대" ||
                  type == "극점" ||
                  type == "극솟값" ||
                  type == "극댓값") {
                // [cite: 596]
                m.color = Colors.purpleAccent; // [cite: 597]
              } else if (type == "y절편" && m.color != Colors.purpleAccent) {
                // [cite: 597]
                m.color = Colors.orangeAccent; // [cite: 597]
              }
              return; // [cite: 598]
            }
          }
          markers.add(GraphMarker(x, y, type, color)); // [cite: 599]
        }

        // [A] x절편 찾기 -> 바구니에 넣기 [cite: 600]
        if (item.showXIntercepts) {
          List<double> roots = MathAnalyzer.findXIntercepts(
            expression: parsedExpression,
            startX: mathStartX,
            endX: mathEndX,
            paramA: parameterA,
            currentScale: currentScale, // [cite: 601]
          );
          for (double rootX in roots) {
            // [cite: 602]
            addMarker(rootX, 0.0, "x절편", Colors.redAccent); // [cite: 602]
          }
        }

        // [B] y절편 찾기 -> 바구니에 넣기 [cite: 603]
        if (item.showYIntercepts) {
          double? yIntercept = MathAnalyzer.findYIntercept(
            expression: parsedExpression,
            paramA: parameterA,
          ); // [cite: 604]
          if (yIntercept != null) {
            // [cite: 605]
            addMarker(
              0.0,
              yIntercept,
              "y절편",
              Colors.orangeAccent,
            ); // [cite: 605]
          }
        }

        // [C] 극점 찾기 -> 바구니에 넣기 [cite: 606]
        if (item.showExtrema) {
          List<double> extremaXs = MathAnalyzer.findExtrema(
            expression: parsedExpression,
            startX: mathStartX,
            endX: mathEndX,
            paramA: parameterA,
            currentScale: currentScale, // [cite: 607]
          );
          final ContextModel evalContext =
              ContextModel()..bindVariable(
                Variable('a'),
                Number(parameterA),
              ); // [cite: 608]
          for (double extX in extremaXs) {
            // [cite: 609]
            evalContext.bindVariable(
              Variable('x'),
              Number(extX),
            ); // [cite: 609]
            double extY = parsedExpression.evaluate(
              EvaluationType.REAL,
              evalContext,
            ); // [cite: 610]

            double h = 0.0001; // [cite: 611]
            evalContext.bindVariable(
              Variable('x'),
              Number(extX - h),
            ); // [cite: 612]
            double yLeft = parsedExpression.evaluate(
              EvaluationType.REAL,
              evalContext,
            ); // [cite: 613]

            evalContext.bindVariable(
              Variable('x'),
              Number(extX + h),
            ); // [cite: 614]
            double yRight = parsedExpression.evaluate(
              EvaluationType.REAL,
              evalContext,
            ); // [cite: 615]

            String extType = "극점"; // [cite: 615]
            if (extY > yLeft && extY > yRight) {
              // [cite: 616]
              extType = "극댓값"; // [cite: 616]
            } else if (extY < yLeft && extY < yRight) {
              // [cite: 617]
              extType = "극솟값"; // [cite: 617]
            }

            addMarker(extX, extY, extType, Colors.purpleAccent); // [cite: 618]
          }
        }
        // =========================================================
        // 2. 바구니에 모인 점들을 화면에 그리기 (스마트 라벨 배치!)
        // =========================================================

        // 왼쪽에서 오른쪽 순서대로 점들을 정렬합니다.
        markers.sort((a, b) => a.x.compareTo(b.x));

        // ⭐️ 핵심 1: 절편들만 따로 번호를 매기기 위한 카운터 변수
        int interceptCount = 0;

        for (int i = 0; i < markers.length; i++) {
          var m = markers[i];
          final screenPoint = matrix.transform3(
            vector_math.Vector3(m.x, -m.y, 0),
          );

          // 1. 하얀색 외곽선(후광) 그리기
          canvas.drawCircle(
            Offset(screenPoint.x, screenPoint.y),
            8.0, // 원래 점(6.0)보다 조금 더 크게
            Paint()
              ..color = Colors.white.withOpacity(0.8) // 하얀색 후광
              ..style = PaintingStyle.fill
              // 살짝 번지는 효과를 주면 더 고급스럽습니다.
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
          );

          // 점 찍기
          canvas.drawCircle(
            Offset(screenPoint.x, screenPoint.y),
            6.0,
            Paint()
              ..color = m.color
              ..style = PaintingStyle.fill,
          );

          String exactX = toExactString(m.x);
          String exactY = toExactString(m.y);
          String labelText = "($exactX, $exactY)";
          if (m.types.isNotEmpty) labelText += " ${m.types.join(", ")}";

          TextSpan span = TextSpan(
            style: TextStyle(
              color: m.color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              backgroundColor: Colors.white.withOpacity(0.85),
            ),
            text: labelText,
          );

          TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          );
          tp.layout();

          // ⭐️ 핵심 2: 점의 '종류'에 따라 스마트하게 위/아래 위치 결정!
          double yOffset;

          if (m.types.contains("극댓값")) {
            yOffset = -24.0; // 산봉우리는 무조건 위로!
          } else if (m.types.contains("극솟값")) {
            yOffset = 12.0; // 골짜기는 무조건 아래로!
          } else {
            // 극점이 아닌 애들(x, y절편)끼리만 따로 카운트해서 번갈아가며 배치
            yOffset = (interceptCount % 2 == 0) ? -24.0 : 12.0;
            interceptCount++;
          }

          double xOffset = screenPoint.x - (tp.width / 2);
          tp.paint(canvas, Offset(xOffset, screenPoint.y + yOffset));
        }
      } catch (e) {
        // 무시
      }
      // =========================================================
    }
    canvas.restore();
  }

  // ⭐️ [버그 수정본]: 화면이 미세하게 움직이거나 상태가 바뀔 때 무조건 마커를 새로 그리도록 갱신 조건을 확실하게 보강합니다.
  @override
  bool shouldRepaint(CoordinatePainter oldDelegate) {
    // 1. 매트릭스(화면 이동/확대/축소)가 조금이라도 바뀌었는지 체크
    if (oldDelegate.matrix != matrix) return true;

    // 2. 수식 파라미터(변수 a 슬라이더 등)가 바뀌었는지 체크
    if (oldDelegate.parameterA != parameterA) return true;

    // 3. 그래프 수식 리스트의 개수나 내용물이 바뀌었는지 체크
    if (!listEquals(oldDelegate.graphItems, graphItems)) return true;

    // 4. ⭐️ [핵심 추가]: 각 그래프 아이템 내부의 토글 상태(showExtrema, showXIntercepts 등)가 하나라도 바뀌면 리페인트합니다.
    for (int i = 0; i < graphItems.length; i++) {
      if (oldDelegate.graphItems[i].showXIntercepts !=
              graphItems[i].showXIntercepts ||
          oldDelegate.graphItems[i].showYIntercepts !=
              graphItems[i].showYIntercepts ||
          oldDelegate.graphItems[i].showExtrema != graphItems[i].showExtrema ||
          oldDelegate.graphItems[i].showIntegral !=
              graphItems[i].showIntegral ||
          oldDelegate.graphItems[i].showDerivative !=
              graphItems[i].showDerivative ||
          oldDelegate.graphItems[i].showInverse != graphItems[i].showInverse) {
        return true;
      }
    }

    return false;
  }
}

extension VectorToOffset on vector_math.Vector3 {
  Offset toOffset() => Offset(x, y);
}

// ==========================================================
// 🛠️ 추가 도구 1: 소수를 예쁜 분수나 정수로 바꿔주는 마법의 함수
// ==========================================================
String toExactString(double value) {
  if (value.isNaN || value.isInfinite) return ""; //
  if (value.abs() < 1e-6) return "0"; // [cite: 506]

  int rounded = value.round(); //
  if ((value - rounded).abs() < 1e-5) {
    //
    return rounded.toString(); //
  } // [cite: 507, 508]

  // ⭐️ [지오지브라식 유리수 스냅 알고리즘]
  // 컴퓨터 부동소수점 제한(52비트)으로 오염된 실수를 구원하기 위해
  // d=2부터 d=10000까지 돌며 '가장 정갈하면서도 가치 있는 황금 분수'를 추적합니다.
  int bestNumerator = 0;
  int bestDenominator = 0;
  double bestScore = double.infinity; // 오차와 분모 정밀도를 종합한 점수

  for (int d = 2; d <= 10000; d++) {
    double num = value * d; // [cite: 511]
    int numRounded = num.round(); // [cite: 512]

    if (numRounded != 0) {
      // [cite: 512]
      double currentError = (num - numRounded).abs(); // [cite: 512]

      // ⭐️ 핵심 컴공 매직: 9999, 999, 100, 50 처럼 수학적으로 의미 있는 분모(d)에
      // 파격적인 보정 보너스(가중치)를 부여하여 비트 오염을 무력화합니다.
      double priorityBonus = 1.0;
      if (d == 9999 || d == 999 || d == 99)
        priorityBonus = 0.000001;
      else if (d % 1000 == 0 || d % 100 == 0)
        priorityBonus = 0.01;
      else if (d % 10 == 0 || d % 5 == 0)
        priorityBonus = 0.1;

      // 64비트 실수 연산 노이즈 범위(0.02) 안으로 들어오는 후보들 중
      if (currentError < 0.02) {
        // 오차와 보너스를 결합한 종합 스코어가 가장 낮은 녀석을 최종 승자로 채택!
        double finalScore = currentError * priorityBonus;
        if (finalScore < bestScore) {
          bestScore = finalScore;
          bestNumerator = numRounded;
          bestDenominator = d;
        }
      }
    }
  }

  // 만 바퀴 스캔 후 최종 선정된 완벽한 분수를 리턴
  if (bestDenominator != 0) {
    return "$bestNumerator/$bestDenominator"; // [cite: 516, 517]
  }

  return value.toStringAsFixed(3); // [cite: 517]
}

// ==========================================================
// 🛠️ 추가 도구 2: 겹치는 점들을 하나로 뭉쳐줄 '점 바구니' 클래스
// ==========================================================
class GraphMarker {
  double x, y;
  List<String> types; // 예: ["y절편", "극소점"]
  Color color;

  GraphMarker(this.x, this.y, String initialType, this.color)
    : types = [initialType];
}
