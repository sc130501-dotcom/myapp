import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'dart:developer';
import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 카카오 SDK 초기화
  KakaoSdk.init(nativeAppKey: '2fcccc432c3248ddfa305b467bbbd9de');

  if (!kIsWeb) {
    await FlutterNaverMap().init(
      clientId: 'i6wtcd41v7',
      onAuthFailed: (ex) => log("네이버 지도 인증 오류: $ex"),
    );
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard', useMaterial3: true),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoggedIn = false;
  String? _cachedNickname;
  String? _cachedProfileUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      if (await AuthApi.instance.hasToken()) {
        User user = await UserApi.instance.me();
        setState(() {
          _isLoggedIn = true;
          _cachedNickname = user.kakaoAccount?.profile?.nickname;
          _cachedProfileUrl = user.kakaoAccount?.profile?.profileImageUrl;
        });
      }
    } catch (e) {
      log("기존 로그인 체크 실패: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loginWithKakao() async {
    if (_isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainScreen(
            userName: _cachedNickname ?? '소연',
            userProfileUrl: _cachedProfileUrl,
          ),
        ),
      );
      return;
    }

    try {
      bool isInstalled = await isKakaoTalkInstalled();
      OAuthToken token;
      if (isInstalled) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }
      log("카카오 로그인 성공: ${token.accessToken}");

      User user = await UserApi.instance.me();
      String nickname = user.kakaoAccount?.profile?.nickname ?? '소연';
      String? profileImageUrl = user.kakaoAccount?.profile?.profileImageUrl;

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(
              userName: nickname,
              userProfileUrl: profileImageUrl,
            ),
          ),
        );
      }
    } catch (error) {
      log("카카오 로그인 실패: $error");
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('카카오 로그인 실패', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              '오류가 발생했습니다.\n에뮬레이터/네트워크 환경 문제일 수 있습니다. 오프라인 체험 모드로 로그인하시겠습니까?\n\n상세 오류: $error'
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MainScreen(
                        userName: '소연',
                        userProfileUrl: null,
                      ),
                    ),
                  );
                },
                child: const Text(
                  '오프라인 체험',
                  style: TextStyle(color: Color(0xFF6F4E37), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.coffee, size: 80, color: Color(0xFF6F4E37)),
              const SizedBox(height: 24),
              const Text(
                '카페 파인더',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6F4E37),
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 60),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6F4E37)),
                    )
                  : ElevatedButton(
                      onPressed: _loginWithKakao,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE500),
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isLoggedIn ? '앱 실행' : '카카오로 시작하기',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final String userName;
  final String? userProfileUrl;
  const MainScreen({super.key, required this.userName, this.userProfileUrl});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  NaverMapController? _mapController;
  NLatLng _currentLocation = const NLatLng(37.5615, 126.9248);
  bool _isLocationFetched = false;

  List<Map<String, dynamic>> _messages = [];

  // 프로필 상태 변수 추가
  late String _nickname;
  String _preferredNeighborhood = '마포구 연남동';
  final List<String> _tasteTags = ['#조용한', '#우드톤', '#디저트맛집', '#채광좋은'];
  late String _profileImageUrl;

  // 저장 리스트 상태 추가
  final Set<String> _savedCafeNames = {'오버딥 카페', '연남동 우드밀'};

  final List<Map<String, dynamic>> allCafeData = [
    {
      "name": "오버딥 카페",
      "desc": "심해 컨셉의 독특한 블루 인테리어",
      "loc": const NLatLng(37.5620, 126.9250),
      "mood": "#연남동 #바다컨셉 #마들렌",
      "analysis": "푸른 조명과 물결 패턴이 돋보이는 신비로운 공간입니다. 마치 깊은 바닷속에 들어온 듯한 몰입감을 줍니다."
    },
    {
      "name": "연남동 우드밀",
      "desc": "따뜻한 나무 향기가 나는 아늑한 공간",
      "loc": const NLatLng(37.5630, 126.9260),
      "mood": "#연남동 #우드톤 #조용한",
      "analysis": "전체적으로 원목을 사용하여 편안하고 아늑한 분위기를 연출했습니다. 조용히 대화를 나누기 좋습니다."
    },
    {
      "name": "카페 스콘",
      "desc": "아기자기한 루프탑과 디저트",
      "loc": const NLatLng(37.5640, 126.9240),
      "mood": "#루프탑 #스콘맛집 #채광좋은",
      "analysis": "밝은 화이트 톤에 햇살이 잘 드는 구조입니다. 아기자기한 소품들과 옥상 루프탑 공간이 매력적입니다."
    },
    {
      "name": "테일러커피",
      "desc": "클래식하고 고급스러운 커피 전문점",
      "loc": const NLatLng(37.5610, 126.9265),
      "mood": "#커피전문 #클래식 #연남동",
      "analysis": "깔끔하고 세련된 블랙 앤 화이트 톤에 무게감 있는 우드가 어우러져 고급스러운 커피 경험을 제공합니다."
    },
    {
      "name": "오우드 성수 (Oude)",
      "desc": "탁 트인 층고와 전면 유리창이 주는 개방감",
      "loc": const NLatLng(37.5442, 127.0548),
      "mood": "#통유리 #테라스카페 #햇살맛집",
      "analysis":
          "공간 전체를 감싸는 통유리를 통해 자연광을 극대화한 설계입니다. 내부와 외부 테라스가 단차 없이 연결되어 시각적 확장성이 뛰어납니다."
    },
    {
      "name": "바이산 (Baesan)",
      "desc": "성수동의 거친 매력을 담은 창고형 티 하우스",
      "loc": const NLatLng(37.5411, 127.0565),
      "mood": "#창고개조 #티하우스 #빈티지아트",
      "analysis":
          "대림창고 옆에 위치한 또 다른 대형 재생 공간입니다. 벽면에 과감한 그라피티와 대형 설치 미술을 배치해 자유롭고 역동적인 분위기를 연출했습니다."
    },
    {
      "name": "레인리포트 크루아상 (Rain Report)",
      "desc": "365일 비가 내리는 컨셉의 감각적 공간",
      "loc": const NLatLng(37.5452, 127.0528),
      "mood": "#이색컨셉 #호우주의보 #디저트",
      "analysis":
          "중정을 향해 인공 비가 내리도록 설계된 수경 시설이 핵심입니다. 어두운 블랙톤 인테리어와 물줄기가 만드는 청각적 효과가 공간의 밀도를 높입니다."
    },
    {
      "name": "무신사 테라스 성수",
      "desc": "미래지향적인 금속 질감의 루프탑 라운지",
      "loc": const NLatLng(37.5448, 127.0592),
      "mood": "#메탈릭 #루프탑 #무신사",
      "analysis":
          "스테인리스 스틸과 폴리카보네이트 소재를 활용한 미래적인 인테리어가 특징입니다. 도시의 수직적인 전경을 한눈에 담을 수 있는 조망 설계가 훌륭합니다."
    },
    {
      "name": "카페 할아버지공장",
      "desc": "마당 위 오두막이 있는 동화 같은 공간",
      "loc": const NLatLng(37.5418, 127.0581),
      "mood": "#마당있는카페 #나무위의집 #복합문화",
      "analysis":
          "중정의 큰 나무 위에 지어진 오두막이 공간의 정체성(Identity)을 형성합니다. 실내외 경계가 모호한 설계로 숲속에 있는 듯한 느낌을 줍니다."
    },
    {
      "name": "연무장 (Yeonmujang)",
      "desc": "도시적인 라운지 스타일의 뷰 맛집",
      "loc": const NLatLng(37.5432, 127.0525),
      "mood": "#스카이라운지 #모던바 #뷰맛집",
      "analysis":
          "건물 최상층에 위치하여 성수동의 공장지대 지붕들을 조망할 수 있는 '뷰 프레임'이 뛰어납니다. 저녁 시간대의 간접 조명 활용이 훌륭합니다."
    },
    {
      "name": "마를리 (Marly)",
      "desc": "돌과 모래가 어우러진 차분한 공간",
      "loc": const NLatLng(37.5428, 127.0572),
      "mood": "#스톤인테리어 #케이크맛집 #차분한",
      "analysis":
          "자연석과 모래 등 거친 자연 소재를 실내로 들여와 고요한 정원을 연상시킵니다. 절제된 색감 사용으로 재료 본연의 질감을 강조한 디자인입니다."
    },
    {
      "name": "포제 (POZE)",
      "desc": "층별로 다른 컨셉을 가진 아카이브 공간",
      "loc": const NLatLng(37.5405, 127.0553),
      "mood": "#전시형카페 #빈티지스피커 #감각적인",
      "analysis":
          "지하부터 루프탑까지 각각 '아카이브', '라운지', '스튜디오' 컨셉으로 나뉩니다. 공간마다 다른 조도를 설정해 이동할 때마다 새로운 공간감을 경험하게 합니다."
    },
    {
      "name": "성수 베이킹 스튜디오",
      "desc": "유럽 노천 시장의 따뜻한 분위기",
      "loc": const NLatLng(37.5439, 127.0435),
      "mood": "#베이커리 #유럽감성 #서울숲골목",
      "analysis":
          "좁은 골목에 위치한 파사드에 따뜻한 노란색 조명을 배치해 가독성과 아늑함을 동시에 잡았습니다. 고소한 빵 냄새가 공간의 일부가 되는 곳입니다."
    },
    {
      "name": "러프사이드 성수 (Rough Side)",
      "desc": "질감의 대비가 느껴지는 미니멀 카페",
      "loc": const NLatLng(37.5446, 127.0578),
      "mood": "#미니멀리즘 #커피전문 #시크한",
      "analysis":
          "매끄러운 아크릴과 거친 암석의 대비를 통해 '러프(Rough)'한 컨셉을 전달합니다. 불필요한 가구를 최소화해 시각적 피로도를 낮춘 설계입니다."
    },
    {
      "name": "도렐 성수 (Dorrell)",
      "desc": "스케이트보드 파크를 모티브로 한 액티브 공간",
      "loc": const NLatLng(37.5455, 127.0560),
      "mood": "#스케이트보드 #스트릿문화 #너티클라우드",
      "analysis":
          "바닥의 곡면 처리가 마치 스케이트보드 파크의 하프파이프를 연상시킵니다. 역동적인 선을 활용해 경쾌한 공간 에너지를 만들어냈습니다."
    },
    {
      "name": "슈퍼매직팩토리",
      "desc": "화려한 색감이 폭발하는 아트 스튜디오",
      "loc": const NLatLng(37.5412, 127.0621),
      "mood": "#비비드컬러 #키치한 #아트카페",
      "analysis":
          "성수동의 무채색 거리에서 눈에 띄는 화려한 원색을 사용했습니다. 다양한 텍스처의 오브제를 믹스매치하여 팝아트적인 공간 구성을 보여줍니다."
    },
    {
      "name": "커피냅로스터스 성수",
      "desc": "지형의 높낮이를 활용한 독특한 좌석",
      "loc": const NLatLng(37.5468, 127.0450),
      "mood": "#공간의재해석 #플랫화이트 #미니멀",
      "analysis":
          "평평한 바닥 대신 둔덕처럼 솟아오른 지형적 디자인을 내부로 들였습니다. 앉는 위치에 따라 시야의 높낮이가 달라지는 흥미로운 공간 경험을 제공합니다."
    },
    {
      "name": "업사이드커피 성수",
      "desc": "귀여운 마스코트와 아늑한 우드 인테리어",
      "loc": const NLatLng(37.5472, 127.0510),
      "mood": "#우드톤 #미어캣 #친근한",
      "analysis":
          "전체적으로 밝은 톤의 목재를 사용해 누구나 편하게 머물 수 있는 따뜻한 밀도를 형성합니다. 작은 공간이지만 효율적인 'ㄱ'자 바 배치가 인상적입니다."
    },
    {
      "name": "에이투비 (A to B)",
      "desc": "낮에는 카페, 밤에는 바로 변하는 공간",
      "loc": const NLatLng(37.5435, 127.0558),
      "mood": "#낮카밤바 #선셋조명 #힙한분위기",
      "analysis":
          "시간대에 따라 조명의 채도와 조도를 조절해 공간의 기능을 전환합니다. 주황빛 선셋 조명이 흰 벽에 투사되어 몽환적인 분위기를 연출합니다."
    }
  ];

  @override
  void initState() {
    super.initState();
    _nickname = widget.userName;
    _profileImageUrl = widget.userProfileUrl ?? '';
    _messages = [
      {
        "isMe": false,
        "text": "${widget.userName}님, 안녕하세요! 어떤 분위기의 카페를 찾으시나요?",
        "type": "text",
      },
    ];
    _determinePosition();
  }

  void _handleSearch(String query) {
    if (query.trim().isEmpty) return;

    final q = query.toLowerCase().trim();
    FocusScope.of(context).unfocus(); // 키보드 숨기기

    // 1. 지역 검색 우선 처리 (카드 띄우지 않고 카메라만 이동)
    if (q == '연남' || q == '연남동') {
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: const NLatLng(37.5625, 126.9255),
          zoom: 14.5,
        ),
      );
      return;
    }

    if (q == '성수' || q == '성수동') {
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: const NLatLng(37.5440, 127.0550),
          zoom: 14.5,
        ),
      );
      return;
    }

    // 2. 카페 이름이나 해시태그 검색
    Map<String, dynamic>? match;
    for (var cafe in allCafeData) {
      final name = cafe['name'].toString().toLowerCase();
      final mood = cafe['mood'].toString().toLowerCase();
      if (name.contains(q) || mood.contains(q)) {
        match = cafe;
        break;
      }
    }

    if (match != null) {
      _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: match['loc'] as NLatLng,
          zoom: 16,
        ),
      );
      _showCafeDetail(match['name'], match['desc'], match['analysis']);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색 결과가 없습니다.')),
      );
    }
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = NLatLng(position.latitude, position.longitude);
        _isLocationFetched = true;
      });
    } catch (e) {
      log("위치 권한 오류: $e");
      setState(() {
        _isLocationFetched = true;
      });
    }
  }

  // 두 번째 코드 스타일로 변경: StatefulBuilder의 내부분기를 반영하기 위해 setModalState 전달받음
  Future<void> _handleChatSubmit(String text, StateSetter setModalState) async {
    if (text.trim().isEmpty) return;
    _chatController.clear();

    setModalState(() {
      _messages.add({"isMe": true, "text": text, "type": "text"});
      _messages.add({"isMe": false, "text": "", "type": "loading"});
    });

    try {
      final response = await http.post(
        Uri.parse(
          'https://factchat-cloud.mindlogic.ai/v1/gateway/chat/completions',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer vPtvysHtpKhpAwUU0cvMki7pmdyN2JIJ',
        },
        body: jsonEncode({
          "model": "claude-sonnet-4-6",
          "messages": [
            {"role": "user", "content": text},
          ],
        }),
      );

      setModalState(() => _messages.removeLast());
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'];

        // 스마트 추천 로직: 유저 질문을 기반으로 카페 점수 매기기
        final q = text.toLowerCase();
        final isSeongsu = q.contains('성수');
        final isYeonnam = q.contains('연남');

        List<Map<String, dynamic>> scoredCafes = [];

        for (var cafe in allCafeData) {
          final name = cafe['name'].toString().toLowerCase();
          final mood = cafe['mood'].toString().toLowerCase();
          final desc = cafe['desc'].toString().toLowerCase();

          // 지역 필터 (성수라고 쳤는데 연남이 나오면 아예 제외)
          final cafeIsYeonnam = mood.contains('연남') || name.contains('연남');
          if (isSeongsu && cafeIsYeonnam) continue;
          if (isYeonnam && !cafeIsYeonnam) continue;

          int score = 0;
          // 단어별 매칭 (예: "조용한" -> "조용")
          final words = q.split(' ');
          for (var w in words) {
            if (w.length < 2) continue;
            if (w == '카페' || w == '추천' || w == '알려') continue;

            final keyword =
                w.replaceAll('동', '').replaceAll('한', '').replaceAll('에', '');
            if (keyword.isEmpty) continue;

            if (name.contains(keyword)) score += 3;
            if (mood.contains(keyword)) score += 3;
            if (desc.contains(keyword)) score += 1;
          }

          // 기본적으로 지역 조건만 맞아도 1점 부여
          if (isSeongsu && !cafeIsYeonnam) score += 1;
          if (isYeonnam && cafeIsYeonnam) score += 1;

          if (score > 0) {
            scoredCafes.add({...cafe, 'score': score});
          }
        }

        scoredCafes
            .sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

        List<Map<String, dynamic>> recommended = scoredCafes
            .map((e) {
              final cafe = Map<String, dynamic>.from(e);
              cafe.remove('score');
              return cafe;
            })
            .take(5)
            .toList();

        // 검색 결과가 아예 없으면 해당 지역 기반으로 기본 추천
        if (recommended.isEmpty) {
          if (isSeongsu) {
            recommended = allCafeData
                .where((c) => !c['mood'].toString().contains('연남'))
                .take(3)
                .toList();
          } else if (isYeonnam) {
            recommended = allCafeData
                .where((c) => c['mood'].toString().contains('연남'))
                .take(3)
                .toList();
          } else {
            recommended = allCafeData.take(3).toList();
          }
        }

        setModalState(() {
          _messages.add({
            "isMe": false,
            "text": reply,
            "type": "text",
          });
          // 동적 추천 캐러셀 추가
          _messages
              .add({"isMe": false, "type": "carousel", "cafes": recommended});
        });
      }
    } catch (e) {
      setModalState(() {
        if (_messages.isNotEmpty && _messages.last["type"] == "loading") {
          _messages.removeLast();
        }
        _messages.add({
          "isMe": false,
          "text": "연결 오류가 발생했어요.",
          "type": "text",
        });
      });
    }
  }

  Widget _buildHomeView() {
    if (!_isLocationFetched) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6F4E37)),
      );
    }

    // 중복 없는 태그 리스트 추출
    final Set<String> uniqueTags = {};
    final List<Map<String, dynamic>> tagChips = [];
    for (var cafe in allCafeData) {
      final tags = cafe['mood'].toString().split(' ');
      for (var t in tags) {
        final tagText = t.trim();
        if (tagText.isNotEmpty &&
            tagText.startsWith('#') &&
            !uniqueTags.contains(tagText)) {
          uniqueTags.add(tagText);
          tagChips.add({'tag': tagText, 'cafe': cafe});
        }
      }
    }

    return Stack(
      children: [
        if (kIsWeb)
          Container(
            color: Colors.grey[200],
            child: const Center(
              child: Text(
                '웹에서는 네이버 지도(앱 전용)를 지원하지 않습니다.\n모바일 기기에서 확인해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ),
          )
        else
          NaverMap(
            options: NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _currentLocation,
                zoom: 15,
              ),
              locationButtonEnable: true,
            ),
            onMapReady: (controller) {
              _mapController = controller;

              // 마커들을 Set으로 모아서 한 번에 추가
              final markers = allCafeData.map((cafe) {
                final marker = NMarker(
                  id: cafe['name'] as String,
                  position: cafe['loc'] as NLatLng,
                );
                marker.setOnTapListener((overlay) {
                  _showCafeDetail(cafe['name'], cafe['desc'], cafe['analysis']);
                });
                return marker;
              }).toSet();

              _mapController?.addOverlayAll(markers);

              // 지도가 켜지면 성수동 한복판으로 카메라 줌인 이동 (초기화)
              _mapController?.updateCamera(
                NCameraUpdate.scrollAndZoomTo(
                  target: const NLatLng(37.5440, 127.0550),
                  zoom: 14.5,
                ),
              );
            },
          ),
        Positioned(
          top: 60,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onSubmitted: _handleSearch,
              decoration: InputDecoration(
                hintText: '카페 분위기를 검색해보세요',
                border: InputBorder.none,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _handleSearch(_searchController.text),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 120,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: tagChips.length,
              itemBuilder: (context, index) {
                final chipData = tagChips[index];
                final tag = chipData['tag'] as String;
                final cafe = chipData['cafe'] as Map<String, dynamic>;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    label: Text(tag,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF6F4E37),
                            fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(
                        color: const Color(0xFF6F4E37).withValues(alpha: 0.3),
                        width: 1),
                    onPressed: () {
                      _mapController?.updateCamera(
                        NCameraUpdate.scrollAndZoomTo(
                          target: cafe['loc'] as NLatLng,
                          zoom: 16,
                        ),
                      );
                      _showCafeDetail(
                          cafe['name'], cafe['desc'], cafe['analysis']);
                    },
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          // 챗봇 버튼 위젯 스타일은 1번째 코드를 유지하되,
          // 하단 플로팅 배너와 겹치지 않도록 bottom 위치를 115로 상향 조정했습니다.
          bottom: 115,
          right: 20,
          child: FloatingActionButton(
            backgroundColor: const Color(0xFF6F4E37),
            onPressed: () => _showChatModal(),
            child: const Icon(Icons.smart_toy, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    final savedCafes = allCafeData.where((cafe) => _savedCafeNames.contains(cafe['name'])).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text(
          '저장 리스트',
          style: TextStyle(
            color: Color(0xFF6F4E37),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: savedCafes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border_rounded,
                    size: 80,
                    color: const Color(0xFF6F4E37).withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '저장된 카페가 없습니다',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6F4E37),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '마음에 드는 카페를 저장 리스트에 담아보세요!',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110), // 하단 바 여백 고려
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.8,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: savedCafes.length,
              itemBuilder: (context, index) {
                final cafe = savedCafes[index];
                return _buildCafeCard(cafe);
              },
            ),
    );
  }

  Widget _buildCafeCard(Map<String, dynamic> cafe) {
    final name = cafe['name'] as String;
    return GestureDetector(
      onTap: () =>
          _showCafeDetail(cafe['name'], cafe['desc'], cafe['analysis']),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_savedCafeNames.contains(name)) {
                            _savedCafeNames.remove(name);
                            log('저장에서 제외되었습니다: $name');
                          } else {
                            _savedCafeNames.add(name);
                            log('저장되었습니다: $name');
                          }
                        });
                      },
                      child: Container(
                         padding: const EdgeInsets.all(6),
                         decoration: BoxDecoration(
                           color: Colors.white.withValues(alpha: 0.8),
                           shape: BoxShape.circle,
                         ),
                         child: Icon(
                           _savedCafeNames.contains(name) ? Icons.bookmark : Icons.bookmark_border,
                           color: const Color(0xFF6F4E37),
                           size: 18,
                         ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cafe['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    cafe['desc'],
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 챗봇 버튼 클릭 시 뜨는 창 디자인 및 로직을 두 번째 코드로 교체
  void _showChatModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // 상단 라운드 처리를 위해 투명화
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Color(0xFFFAF7F2),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFA5D6A7),
                      child: Icon(Icons.auto_awesome,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "AI 카페 가이드",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    if (msg["type"] == "carousel") {
                      final cafes =
                          msg["cafes"] as List<Map<String, dynamic>>? ?? [];
                      return _buildCarousel(cafes);
                    }
                    return _buildChatBubble(
                      msg["text"],
                      msg["isMe"],
                      msg["type"] == "loading",
                    );
                  },
                ),
              ),
              _buildChatInput(setModalState),
            ],
          ),
        ),
      ),
    );
  }

  // 두 번째 코드의 트렌디한 말풍선 디자인 반영
  Widget _buildChatBubble(String text, bool isMe, bool isLoading) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF8D6E63) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 5,
            )
          ],
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8D6E63)),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87, fontSize: 15),
              ),
      ),
    );
  }

  // 두 번째 코드의 깔끔한 입력창 구조 반영
  Widget _buildChatInput(StateSetter setModalState) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: _chatController,
                onSubmitted: (val) => _handleChatSubmit(val, setModalState),
                decoration: const InputDecoration(
                  hintText: "메시지를 입력하세요...",
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _handleChatSubmit(_chatController.text, setModalState),
            child: const CircleAvatar(
              backgroundColor: Color(0xFF8D6E63),
              child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel(List<Map<String, dynamic>> cafes) {
    if (cafes.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 150,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: cafes
            .map((cafe) =>
                _buildCarouselItem(cafe['name'], cafe['loc'] as NLatLng))
            .toList(),
      ),
    );
  }

  Widget _buildCarouselItem(String name, NLatLng loc) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // 봇 창 닫기
        setState(() {
          _currentIndex = 0; // 지도로 탭 이동
        });

        // 지도를 해당 위치로 이동
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: loc, zoom: 16),
        );

        // 전체 데이터에서 해당 카페를 찾아서 디테일 카드 띄우기
        Map<String, dynamic>? match;
        for (var c in allCafeData) {
          if (c['name'] == name) {
            match = c;
            break;
          }
        }

        if (match != null) {
          _showCafeDetail(match['name'], match['desc'], match['analysis']);
        }
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.coffee, color: Color(0xFF6F4E37)),
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showCafeDetail(String name, String desc, String analysis) {
    // 위도/경도 대신 사용자 친화적인 실제 주소 매핑
    final Map<String, String> addressMap = {
      "오버딥 카페": "서울 마포구 성미산로 149-8",
      "연남동 우드밀": "서울 마포구 동교로46길 12",
      "카페 스콘": "서울 마포구 성미산로 172",
      "테일러커피": "서울 마포구 성미산로 189",
      "오우드 성수 (Oude)": "서울 성동구 연무장길 101-1",
      "바이산 (Baesan)": "서울 성동구 성수이로 78",
      "레인리포트 크루아상 (Rain Report)": "서울 성동구 성수이로16길 32",
      "무신사 테라스 성수": "서울 성동구 연무장길 101-1",
      "카페 할아버지공장": "서울 성동구 성수이로7가길 9",
      "연무장 (Yeonmujang)": "서울 성동구 연무장길 36",
      "마를리 (Marly)": "서울 성동구 연무장길 47",
      "포제 (POZE)": "서울 성동구 연무장9길 7",
      "성수 베이킹 스튜디오": "서울 성동구 서울숲2길 46",
      "러프사이드 성수 (Rough Side)": "서울 성동구 연무장길 81",
      "도렐 성수 (Dorrell)": "서울 성동구 연무장7길 11",
      "슈퍼매직팩토리": "서울 성동구 성수이로 66",
      "커피냅로스터스 성수": "서울 성동구 성수이로 88",
      "업사이드커피 성수": "서울 성동구 연무장13길 3",
      "에이투비 (A to B)": "서울 성동구 아차산로 135"
    };

    final address = addressMap[name] ?? "주소 정보 없음";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  address,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(color: Color(0xFF6F4E37))),
            const Divider(height: 40),
            const Text(
              'AI 분석 분위기',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(analysis, style: const TextStyle(height: 1.5)),
            const Spacer(),
            Builder(
              builder: (context) {
                final isSaved = _savedCafeNames.contains(name);
                return SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSaved ? const Color(0xFFEADBC8) : const Color(0xFF6F4E37),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        if (isSaved) {
                          _savedCafeNames.remove(name);
                          log('저장에서 제외되었습니다: $name');
                        } else {
                          _savedCafeNames.add(name);
                          log('저장되었습니다: $name');
                        }
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isSaved ? '저장 리스트에서 제외되었습니다.' : '내 저장 리스트에 담겼습니다.'),
                          backgroundColor: const Color(0xFF6F4E37),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: isSaved ? const Color(0xFF6F4E37) : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSaved ? '저장 리스트에서 빼기' : '내 저장 리스트에 담기',
                          style: TextStyle(
                            color: isSaved ? const Color(0xFF6F4E37) : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider _getProfileImage() {
    if (_profileImageUrl.isEmpty ||
        !_profileImageUrl.startsWith('http') ||
        _profileImageUrl.contains('default_profile')) {
      return const AssetImage('assets/images/profile.jpg');
    }
    return NetworkImage(_profileImageUrl);
  }

  Widget _buildProfileView() {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text(
          '내 프로필',
          style: TextStyle(
            color: Color(0xFF6F4E37),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 상단 프로필 영역
              Center(
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFEADBC8),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundImage: _getProfileImage(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _nickname,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '📌 $_preferredNeighborhood',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6F4E37),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 2. 가운데 카페 취향 분석 영역
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFFAF6F0), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bar_chart, color: Color(0xFF6F4E37), size: 20),
                            SizedBox(width: 8),
                            Text(
                              '나의 카페 취향 분석',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6F4E37)),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: _showEditTagsDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF6F0),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEADBC8), width: 0.5),
                            ),
                            child: const Text(
                              '태그 수정',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6F4E37),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '내가 저장했던 카페들을 바탕으로 분석된 해시태그입니다. 태그를 직접 수정하여 취향을 정교하게 다듬어보세요.',
                      style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _tasteTags.map((tag) {
                        return GestureDetector(
                          onTap: _showEditTagsDialog,
                          child: Chip(
                            backgroundColor: const Color(0xFFFAF6F0),
                            side: const BorderSide(color: Color(0xFFEADBC8), width: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            label: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5C3D2E),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. 밑에 수직 배열 버튼 메뉴 영역
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFFAF6F0), width: 1.5),
                ),
                child: Column(
                  children: [
                    _buildProfileMenuItem(
                      icon: Icons.edit_note,
                      title: '회원정보 수정',
                      subtitle: '닉네임 변경 및 선호 동네 설정',
                      onTap: _showEditProfileSheet,
                    ),
                    const Divider(height: 1, indent: 20, endIndent: 20),
                    _buildProfileMenuItem(
                      icon: Icons.history,
                      title: 'AI 챗봇 상담 기록',
                      subtitle: '이전 카페 추천 세션 모아보기',
                      onTap: _showChatHistorySheet,
                    ),
                    const Divider(height: 1, indent: 20, endIndent: 20),
                    _buildProfileMenuItem(
                      icon: Icons.logout,
                      title: '로그아웃',
                      subtitle: '안전하게 로그아웃하고 첫 화면으로 이동',
                      onTap: _handleLogout,
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.redAccent : const Color(0xFF333333);
    final iconColor = isDestructive ? Colors.redAccent : const Color(0xFF6F4E37);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red[50] : const Color(0xFFFAF6F0),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  void _showEditTagsDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Row(
                children: [
                  Icon(Icons.tag, color: Color(0xFF6F4E37)),
                  SizedBox(width: 8),
                  Text(
                    '취향 태그 편집',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6F4E37),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '태그를 터치하면 삭제됩니다.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _tasteTags.map((tag) {
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _tasteTags.remove(tag);
                            });
                            setDialogState(() {});
                          },
                          child: Chip(
                            backgroundColor: const Color(0xFFFAF6F0),
                            side: const BorderSide(color: Color(0xFFEADBC8), width: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tag,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5C3D2E),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.close, size: 14, color: Colors.grey),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: textController,
                            decoration: InputDecoration(
                              hintText: '태그 추가 (예: #감성카페)',
                              hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                              filled: true,
                              fillColor: const Color(0xFFFAF7F2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                String formatted = value.trim();
                                if (!formatted.startsWith('#')) {
                                  formatted = '#$formatted';
                                }
                                if (!_tasteTags.contains(formatted)) {
                                  setState(() {
                                    _tasteTags.add(formatted);
                                  });
                                  textController.clear();
                                  setDialogState(() {});
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF6F4E37),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.add, color: Colors.white),
                          onPressed: () {
                            final text = textController.text;
                            if (text.trim().isNotEmpty) {
                              String formatted = text.trim();
                              if (!formatted.startsWith('#')) {
                                formatted = '#$formatted';
                              }
                              if (!_tasteTags.contains(formatted)) {
                                setState(() {
                                  _tasteTags.add(formatted);
                                });
                                textController.clear();
                                setDialogState(() {});
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '확인',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6F4E37),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditProfileSheet() {
    final nickController = TextEditingController(text: _nickname);
    final townController = TextEditingController(text: _preferredNeighborhood);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 50,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.edit_note, color: Color(0xFF6F4E37), size: 26),
                  SizedBox(width: 8),
                  Text(
                    '회원정보 수정',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6F4E37),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                '사용자 닉네임',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nickController,
                decoration: InputDecoration(
                  hintText: '닉네임을 입력해주세요',
                  filled: true,
                  fillColor: const Color(0xFFFAF7F2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '주로 가는 동네 설정',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: townController,
                decoration: InputDecoration(
                  hintText: '예: 마포구 연남동',
                  filled: true,
                  fillColor: const Color(0xFFFAF7F2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F4E37),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (nickController.text.trim().isNotEmpty &&
                        townController.text.trim().isNotEmpty) {
                      setState(() {
                        _nickname = nickController.text.trim();
                        _preferredNeighborhood = townController.text.trim();
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('회원정보가 수정되었습니다.'),
                          backgroundColor: Color(0xFF6F4E37),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    '저장하기',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatHistorySheet() {
    // 현재 세션의 실제 Q&A 내역 추출
    final List<Map<String, String>> historyList = [];
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i]["isMe"] == true) {
        final String question = _messages[i]["text"] ?? "";
        String answer = "답변을 불러오는 중입니다...";
        for (int j = i + 1; j < _messages.length; j++) {
          if (_messages[j]["isMe"] == false && _messages[j]["type"] == "text") {
            answer = _messages[j]["text"] ?? "";
            break;
          }
        }
        historyList.add({
          "date": "오늘",
          "question": question,
          "answer": answer,
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 50,
                height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const Row(
              children: [
                Icon(Icons.history, color: Color(0xFF6F4E37), size: 26),
                SizedBox(width: 8),
                Text(
                  'AI 챗봇 상담 기록',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6F4E37),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: historyList.isEmpty
                  ? const Center(
                      child: Text(
                        '아직 AI 카페 추천 챗봇 기능을 이용하지 않았습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: historyList.length,
                      itemBuilder: (context, index) {
                        final log = historyList[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF6F0),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: const Color(0xFFEADBC8),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6F4E37),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'AI 상담',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    log["date"]!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Q. ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6F4E37),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      log["question"]!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF333333),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20, color: Color(0xFFEADBC8)),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'A. ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFC78030),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      log["answer"]!,
                                      style: const TextStyle(
                                        color: Color(0xFF5C3D2E),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              '로그아웃',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
          ],
        ),
        content: const Text('정말로 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '취소',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 팝업 닫기
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoginPage(),
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('로그아웃 되었습니다.'),
                  backgroundColor: Color(0xFF6F4E37),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text(
              '로그아웃',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // TrendyBottomNav(글래스모피즘 바)가 뷰 레이어 위에 이쁘게 안착하도록 활성화
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeView(),
          _buildListView(),
          _buildProfileView(),
        ],
      ),
      // 하단 네비게이션 배너를 2번째 코드의 트렌디 스타일(글래스모피즘 + 북마크 아이콘)로 완전히 교체
      bottomNavigationBar: TrendyBottomNav(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
      ),
    );
  }
}

// 두 번째 코드의 글래스모피즘 컨테이너 컴포넌트 추가
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  const GlassContainer(
      {super.key, required this.child, this.borderRadius = 24});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// 두 번째 코드의 플로팅 타입 하단 네비게이션 컴포넌트 추가 (2번째 아이콘: bookmark_outline_rounded)
class TrendyBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const TrendyBottomNav(
      {super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      child: GlassContainer(
        borderRadius: 35,
        child: SizedBox(
          height: 70,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              GestureDetector(
                onTap: () => onTap(0),
                child: _navIcon(Icons.map_rounded, currentIndex == 0),
              ),
              GestureDetector(
                onTap: () => onTap(1),
                child:
                    _navIcon(Icons.bookmark_outline_rounded, currentIndex == 1),
              ),
              GestureDetector(
                onTap: () => onTap(2),
                child: _navIcon(Icons.person_rounded, currentIndex == 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, bool isActive) {
    return Icon(
      icon,
      color: isActive ? const Color(0xFF8D6E63) : Colors.black38,
      size: 28,
    );
  }
}
