import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Added for kIsWeb
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'dart:developer';
import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:shared_preferences/shared_preferences.dart';

// [기능 추가 2] 로그아웃 후에도 전역 앱 데이터를 유지하기 위한 영속성 임시 스토리지 클래스
class AppState {
  static bool isInitialized = false;
  static String? nickname;
  static String? profileImageUrl;
  static String preferredNeighborhood = '마포구 연남동';
  static List<String> tasteTags = []; // [기능 추가 4] 최초 사용 시 빈 리스트로 시작
  static Set<String> savedCafeNames = {}; // [기능 추가 4] 최초 빈 저장소로 시작
  static List<Map<String, dynamic>> chatMessages = [];

  // Load state from SharedPreferences
  static Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      nickname = prefs.getString('nickname');
      profileImageUrl = prefs.getString('profileImageUrl');
      preferredNeighborhood = prefs.getString('preferredNeighborhood') ?? '마포구 연남동';
      tasteTags = prefs.getStringList('tasteTags') ?? [];
      
      final savedCafesList = prefs.getStringList('savedCafeNames') ?? [];
      savedCafeNames = savedCafesList.toSet();
      
      final chatMessagesJson = prefs.getString('chatMessages');
      if (chatMessagesJson != null) {
        final decoded = jsonDecode(chatMessagesJson) as List<dynamic>;
        chatMessages = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
      } else {
        chatMessages = [];
      }
      
      isInitialized = prefs.getBool('isInitialized') ?? false;
      log("AppState loaded from SharedPreferences successfully. Nickname: $nickname, ProfileImageUrl: $profileImageUrl, Messages: ${chatMessages.length}");
    } catch (e) {
      log("Failed to load AppState from SharedPreferences: $e");
    }
  }

  // Save state to SharedPreferences
  static Future<void> saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (nickname != null) {
        await prefs.setString('nickname', nickname!);
      }
      if (profileImageUrl != null) {
        await prefs.setString('profileImageUrl', profileImageUrl!);
      } else {
        await prefs.remove('profileImageUrl');
      }
      await prefs.setString('preferredNeighborhood', preferredNeighborhood);
      await prefs.setStringList('tasteTags', tasteTags);
      await prefs.setStringList('savedCafeNames', savedCafeNames.toList());
      await prefs.setString('chatMessages', jsonEncode(chatMessages));
      await prefs.setBool('isInitialized', isInitialized);
      
      log("AppState saved to SharedPreferences successfully. Messages: ${chatMessages.length}");
    } catch (e) {
      log("Failed to save AppState to SharedPreferences: $e");
    }
  }

  // Clear state (if ever needed on delete account or clean install, but on logout we DO NOT delete)
  static Future<void> clearStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      log("SharedPreferences cleared.");
    } catch (e) {
      log("Failed to clear SharedPreferences: $e");
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load SharedPreferences data
  await AppState.loadFromStorage();
  
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

  // 프로필 상태 변수
  late String _nickname;
  late String _profileImageUrl;

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
      "analysis": "공간 전체를 감싸는 통유리를 통해 자연광을 극대화한 설계입니다. 내부와 외부 테라스가 단차 없이 연결되어 시각적 확장성이 뛰어납니다."
    },
    {
      "name": "바이산 (Baesan)",
      "desc": "성수동의 거친 매력을 담은 창고형 티 하우스",
      "loc": const NLatLng(37.5411, 127.0565),
      "mood": "#창고개조 #티하우스 #빈티지아트",
      "analysis": "벽면에 과감한 그라피티와 대형 설치 미술을 배치해 자유롭고 역동적인 분위기를 연출했습니다."
    },
    {
      "name": "레인리포트 크루아상 (Rain Report)",
      "desc": "365일 비가 내리는 컨셉의 감각적 공간",
      "loc": const NLatLng(37.5452, 127.0528),
      "mood": "#이색컨셉 #호우주의보 #디저트",
      "analysis": "중정을 향해 인공 비가 내리도록 설계된 수경 시설이 핵심입니다. 어두운 블랙톤 인테리어와 물줄기가 만드는 청각적 효과가 공간의 밀도를 높입니다."
    },
    {
      "name": "무신사 테라스 성수",
      "desc": "미래지향적인 금속 질감의 루프탑 라운지",
      "loc": const NLatLng(37.5448, 127.0592),
      "mood": "#메탈릭 #루프탑 #무신사",
      "analysis": "스테인리스 스틸과 폴리카보네이트 소재를 활용한 미래적인 인테리어가 특징입니다. 도시의 수직적인 전경을 한눈에 담을 수 있는 조망 설계가 훌륭합니다."
    },
    {
      "name": "카페 할아버지공장",
      "desc": "마당 위 오두막이 있는 동화 같은 공간",
      "loc": const NLatLng(37.5418, 127.0581),
      "mood": "#마당있는카페 #나무위의집 #복합문화",
      "analysis": "중정의 큰 나무 위에 지어진 오두막이 공간의 정체성(Identity)을 형성합니다. 실내외 경계가 모호한 설계로 숲속에 있는 듯한 느낌을 줍니다."
    },
    {
      "name": "연무장 (Yeonmujang)",
      "desc": "도시적인 라운지 스타일의 뷰 맛집",
      "loc": const NLatLng(37.5432, 127.0525),
      "mood": "#스카이라운지 #모던바 #뷰맛집",
      "analysis": "건물 최상층에 위치하여 성수동의 공장지대 지붕들을 조망할 수 있는 '뷰 프레임'이 뛰어납니다. 저녁 시간대의 간접 조명 활용이 훌륭합니다."
    }
  ];

  @override
  void initState() {
    super.initState();
    
    // [기능 추가 2] 최초 1회만 초기 값 할당, 이후 재로그인 시에는 기존 AppState 데이터 사용
    if (!AppState.isInitialized) {
      AppState.nickname = widget.userName;
      AppState.profileImageUrl = widget.userProfileUrl;
      AppState.chatMessages = [
        {
          "isMe": false,
          "text": "${widget.userName}님, 안녕하세요! 어떤 분위기의 카페를 찾으시나요?",
          "type": "text",
        },
      ];
      AppState.isInitialized = true;
    } else {
      // 이미 초기화된 상태여도 카카오 로그인 등으로 새 프로필 이미지가 들어왔다면 연동 보장
      if (widget.userProfileUrl != null && widget.userProfileUrl!.isNotEmpty) {
        AppState.profileImageUrl = widget.userProfileUrl;
      }
    }
    
    _nickname = AppState.nickname!;
    _profileImageUrl = AppState.profileImageUrl ?? '';
    _determinePosition();
    _updateTasteTags(); // [기능 추가 4] 저장 목록 바탕으로 동적 해시태그 취향 갱신
  }

  // [기능 추가 4] 사용자의 카페 저장 리스트를 바탕으로 해시태그를 동적으로 추출 및 갱신하는 분석 함수
  void _updateTasteTags() {
    if (AppState.savedCafeNames.isEmpty) {
      AppState.tasteTags = [];
      return;
    }
    
    Set<String> computedTags = {};
    for (var cafeName in AppState.savedCafeNames) {
      final cafe = allCafeData.firstWhere(
        (c) => c['name'] == cafeName, 
        orElse: () => <String, dynamic>{}
      );
      if (cafe.isNotEmpty) {
        final tags = cafe['mood'].toString().split(' ');
        for (var t in tags) {
          if (t.trim().startsWith('#')) {
            computedTags.add(t.trim());
          }
        }
      }
    }
    setState(() {
      AppState.tasteTags = computedTags.toList();
    });
  }

  void _handleSearch(String query) {
    if (query.trim().isEmpty) return;

    final q = query.toLowerCase().trim();
    FocusScope.of(context).unfocus();

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

  Future<void> _handleChatSubmit(String text, StateSetter setModalState) async {
    if (text.trim().isEmpty) return;
    _chatController.clear();

    setModalState(() {
      AppState.chatMessages.add({"isMe": true, "text": text, "type": "text"});
      AppState.chatMessages.add({"isMe": false, "text": "", "type": "loading"});
    });

    try {
      final response = await http.post(
        Uri.parse('https://factchat-cloud.mindlogic.ai/v1/gateway/chat/completions'),
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

      setModalState(() => AppState.chatMessages.removeLast());
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'];

        final q = text.toLowerCase();
        final isSeongsu = q.contains('성수');
        final isYeonnam = q.contains('연남');

        List<Map<String, dynamic>> scoredCafes = [];

        for (var cafe in allCafeData) {
          final name = cafe['name'].toString().toLowerCase();
          final mood = cafe['mood'].toString().toLowerCase();
          final desc = cafe['desc'].toString().toLowerCase();

          final cafeIsYeonnam = mood.contains('연남') || name.contains('연남');
          if (isSeongsu && cafeIsYeonnam) continue;
          if (isYeonnam && !cafeIsYeonnam) continue;

          int score = 0;
          final words = q.split(' ');
          for (var w in words) {
            if (w.length < 2) continue;
            if (w == '카페' || w == '추천' || w == '알려') continue;

            final keyword = w.replaceAll('동', '').replaceAll('한', '').replaceAll('에', '');
            if (keyword.isEmpty) continue;

            if (name.contains(keyword)) score += 3;
            if (mood.contains(keyword)) score += 3;
            if (desc.contains(keyword)) score += 1;
          }

          if (isSeongsu && !cafeIsYeonnam) score += 1;
          if (isYeonnam && cafeIsYeonnam) score += 1;

          if (score > 0) {
            scoredCafes.add({...cafe, 'score': score});
          }
        }

        scoredCafes.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

        List<Map<String, dynamic>> recommended = scoredCafes.map((e) {
          final cafe = Map<String, dynamic>.from(e);
          cafe.remove('score');
          return cafe;
        }).take(5).toList();

        if (recommended.isEmpty) {
          if (isSeongsu) {
            recommended = allCafeData.where((c) => !c['mood'].toString().contains('연남')).take(3).toList();
          } else if (isYeonnam) {
            recommended = allCafeData.where((c) => c['mood'].toString().contains('연남')).take(3).toList();
          } else {
            recommended = allCafeData.take(3).toList();
          }
        }

        setModalState(() {
          AppState.chatMessages.add({
            "isMe": false,
            "text": reply,
            "type": "text",
          });
          AppState.chatMessages.add({"isMe": false, "type": "carousel", "cafes": recommended});
        });
        AppState.saveToStorage(); // 영속화 저장
      }
    } catch (e) {
      setModalState(() {
        if (AppState.chatMessages.isNotEmpty && AppState.chatMessages.last["type"] == "loading") {
          AppState.chatMessages.removeLast();
        }
        AppState.chatMessages.add({
          "isMe": false,
          "text": "연결 오류가 발생했어요.",
          "type": "text",
        });
      });
      AppState.saveToStorage(); // 영속화 저장
    }
  }

  Widget _buildHomeView() {
    if (!_isLocationFetched) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6F4E37)),
      );
    }

    final Set<String> uniqueTags = {};
    final List<Map<String, dynamic>> tagChips = [];
    for (var cafe in allCafeData) {
      final tags = cafe['mood'].toString().split(' ');
      for (var t in tags) {
        final tagText = t.trim();
        if (tagText.isNotEmpty && tagText.startsWith('#') && !uniqueTags.contains(tagText)) {
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    side: BorderSide(color: const Color(0xFF6F4E37).withValues(alpha: 0.3), width: 1),
                    onPressed: () {
                      _mapController?.updateCamera(
                        NCameraUpdate.scrollAndZoomTo(
                          target: cafe['loc'] as NLatLng,
                          zoom: 16,
                        ),
                      );
                      _showCafeDetail(cafe['name'], cafe['desc'], cafe['analysis']);
                    },
                  ),
                );
              },
            ),
          ),
        ),
        // [기능 추가 5] 메인화면 속 AI 챗봇 버튼 위에 현재 위치 정렬 버튼 추가
        Positioned(
          bottom: 185,
          right: 20,
          child: FloatingActionButton(
            heroTag: "current_location_fab",
            backgroundColor: Colors.white,
            onPressed: () {
              if (_mapController != null) {
                _mapController!.updateCamera(
                  NCameraUpdate.scrollAndZoomTo(
                    target: _currentLocation,
                    zoom: 16,
                  ),
                );
              }
            },
            child: const Icon(Icons.my_location, color: Color(0xFF6F4E37)),
          ),
        ),
        Positioned(
          bottom: 115,
          right: 20,
          child: FloatingActionButton(
            heroTag: "chatbot_fab",
            backgroundColor: const Color(0xFF6F4E37),
            onPressed: () => _showChatModal(),
            child: const Icon(Icons.smart_toy, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    final savedCafes = allCafeData.where((cafe) => AppState.savedCafeNames.contains(cafe['name'])).toList();

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
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
      // [기능 추가 3] 저장 리스트 탭에서 카드 선택 시 빼기창을 여는 대신 해당 위치로 지도를 즉시 이동
      onTap: () {
        _showCafeDetail(cafe['name'], cafe['desc'], cafe['analysis'], fromSavedTab: true);
      },
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
                          if (AppState.savedCafeNames.contains(name)) {
                            AppState.savedCafeNames.remove(name);
                          } else {
                            AppState.savedCafeNames.add(name);
                          }
                          _updateTasteTags(); // 실시간 해시태그 목록 동기화
                        });
                        AppState.saveToStorage(); // 영속화 저장
                      },
                      child: Container(
                         padding: const EdgeInsets.all(6),
                         decoration: BoxDecoration(
                           color: Colors.white.withValues(alpha: 0.8),
                           shape: BoxShape.circle,
                         ),
                         child: Icon(
                           AppState.savedCafeNames.contains(name) ? Icons.bookmark : Icons.bookmark_border,
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

  void _showChatModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                      child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "AI 카페 가이드",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                  itemCount: AppState.chatMessages.length,
                  itemBuilder: (context, index) {
                    final msg = AppState.chatMessages[index];
                    if (msg["type"] == "carousel") {
                      final cafes = msg["cafes"] as List<Map<String, dynamic>>? ?? [];
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

  Widget _buildChatBubble(String text, bool isMe, bool isLoading) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF8D6E63) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 20),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5)
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
                style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15),
              ),
      ),
    );
  }

  Widget _buildChatInput(StateSetter setModalState) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
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
            .map((cafe) => _buildCarouselItem(cafe['name'], cafe['loc'] as NLatLng))
            .toList(),
      ),
    );
  }

  Widget _buildCarouselItem(String name, NLatLng loc) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _currentIndex = 0;
        });

        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: loc, zoom: 16),
        );

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

  void _showCafeDetail(String name, String desc, String analysis, {bool fromSavedTab = false}) {
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
                Text(address, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(color: Color(0xFF6F4E37))),
            const Divider(height: 40),
            const Text('AI 분석 분위기', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(analysis, style: const TextStyle(height: 1.5)),
            const Spacer(),
            Builder(
              builder: (context) {
                if (fromSavedTab) {
                  return SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6F4E37),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: () {
                        Navigator.pop(context); // Close detail bottom sheet
                        setState(() {
                          _currentIndex = 0; // Switch to Map tab
                        });
                        final cafe = allCafeData.firstWhere(
                          (c) => c['name'] == name,
                          orElse: () => <String, dynamic>{},
                        );
                        if (cafe.isNotEmpty) {
                          _mapController?.updateCamera(
                            NCameraUpdate.scrollAndZoomTo(target: cafe['loc'] as NLatLng, zoom: 16),
                          );
                        }
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            '카페 위치로 지도 이동',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final isSaved = AppState.savedCafeNames.contains(name);
                return SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSaved ? const Color(0xFFEADBC8) : const Color(0xFF6F4E37),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: () {
                      setState(() {
                        if (isSaved) {
                          AppState.savedCafeNames.remove(name);
                        } else {
                          AppState.savedCafeNames.add(name);
                        }
                        _updateTasteTags(); // 취향분석 동적 동기화
                      });
                      AppState.saveToStorage(); // 영속화 저장
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
    if (_profileImageUrl.isEmpty || !_profileImageUrl.startsWith('http') || _profileImageUrl.contains('default_profile')) {
      return const NetworkImage('https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=200&q=80');
    }
    return NetworkImage(_profileImageUrl);
  }

  Widget _buildProfileView() {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text('내 프로필', style: TextStyle(color: Color(0xFF6F4E37), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 120.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFEADBC8), width: 3),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4)),
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
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '📌 ${AppState.preferredNeighborhood}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6F4E37)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
                  border: Border.all(color: const Color(0xFFFAF6F0), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bar_chart, color: Color(0xFF6F4E37), size: 20),
                        SizedBox(width: 8),
                        Text('나의 카페 취향 분석', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6F4E37))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '내가 저장했던 카페들을 바탕으로 분석된 해시태그입니다. 카페를 저장할 때마다 실시간으로 취향을 새롭게 갱신합니다.',
                      style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    // [기능 추가 4] 취향 분석 해시태그 카드 연동 - 리스트 상태에 따라 동적으로 노출
                    AppState.tasteTags.isEmpty 
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("아직 분석 데이터가 없습니다.\n카페를 내 저장 리스트에 추가해 보세요!", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                      )
                    : Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: AppState.tasteTags.map((tag) {
                          return Chip(
                            backgroundColor: const Color(0xFFFAF6F0),
                            side: const BorderSide(color: Color(0xFFEADBC8), width: 0.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            label: Text(tag, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF5C3D2E))),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
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
                      subtitle: '이전 카페 추천 세션 모아보기 및 삭제',
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
      title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }

  void _showEditProfileSheet() {
    final nickController = TextEditingController(text: _nickname);
    final townController = TextEditingController(text: AppState.preferredNeighborhood);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 50, height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.edit_note, color: Color(0xFF6F4E37), size: 26),
                  SizedBox(width: 8),
                  Text('회원정보 수정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF6F4E37))),
                ],
              ),
              const SizedBox(height: 24),
              const Text('사용자 닉네임', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF333333))),
              const SizedBox(height: 8),
              TextField(
                controller: nickController,
                decoration: InputDecoration(
                  hintText: '닉네임을 입력해주세요',
                  filled: true, fillColor: const Color(0xFFFAF7F2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              const Text('주로 가는 동네 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF333333))),
              const SizedBox(height: 8),
              TextField(
                controller: townController,
                decoration: InputDecoration(
                  hintText: '예: 마포구 연남동',
                  filled: true, fillColor: const Color(0xFFFAF7F2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6F4E37),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: () {
                    if (nickController.text.trim().isNotEmpty && townController.text.trim().isNotEmpty) {
                      setState(() {
                        _nickname = nickController.text.trim();
                        AppState.nickname = _nickname;
                        AppState.preferredNeighborhood = townController.text.trim();
                      });
                      AppState.saveToStorage(); // 영속화 저장
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('저장하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // [기능 추가 1] AI 대화형 상담 내역 기록 분리 및 삭제를 지원하는 확장 바텀시트 구조
  void _showChatHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final List<Map<String, dynamic>> historyList = [];
          for (int i = 0; i < AppState.chatMessages.length; i++) {
            if (AppState.chatMessages[i]["isMe"] == true) {
              final String question = AppState.chatMessages[i]["text"] ?? "";
              String answer = "추천 카페를 탐색 중입니다...";
              int answerIndex = -1;
              for (int j = i + 1; j < AppState.chatMessages.length; j++) {
                if (AppState.chatMessages[j]["isMe"] == false && AppState.chatMessages[j]["type"] == "text") {
                  answer = AppState.chatMessages[j]["text"] ?? "";
                  answerIndex = j;
                  break;
                }
              }
              historyList.add({
                "questionIndex": i,
                "answerIndex": answerIndex,
                "date": "상담 기록",
                "question": question,
                "answer": answer,
              });
            }
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 50, height: 5,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.history, color: Color(0xFF6F4E37), size: 26),
                        SizedBox(width: 8),
                        Text('AI 챗봇 상담 기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF6F4E37))),
                      ],
                    ),
                    if (historyList.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 18),
                        label: const Text('전체 삭제', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Text('전체 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
                              content: const Text('모든 상담 기록을 삭제하시겠습니까?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    setState(() {
                                      AppState.chatMessages.clear();
                                      AppState.chatMessages.add({
                                        "isMe": false,
                                        "text": "$_nickname님, 안녕하세요! 어떤 분위기의 카페를 찾으시나요?",
                                        "type": "text",
                                      });
                                    });
                                    setSheetState(() {});
                                    AppState.saveToStorage();
                                  },
                                  child: const Text('전체 삭제', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: historyList.isEmpty
                      ? const Center(child: Text('아직 저장된 상담 기록이 없습니다.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey)))
                      : ListView.builder(
                          itemCount: historyList.length,
                          itemBuilder: (context, index) {
                            final logItem = historyList[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF6F0),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: const Color(0xFFEADBC8), width: 0.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: const Color(0xFF6F4E37), borderRadius: BorderRadius.circular(8)),
                                        child: const Text('AI 대화', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                      // 개별 대화 기록 세션 쌍 삭제 버튼
                                      IconButton(
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                        onPressed: () {
                                          setState(() {
                                            int qIdx = logItem["questionIndex"];
                                            int aIdx = logItem["answerIndex"];
                                            // 인덱스 밀림 방지를 위해 큰 인덱스부터 삭제 진행
                                            if (aIdx != -1 && qIdx != -1) {
                                              if (aIdx > qIdx) {
                                                AppState.chatMessages.removeAt(aIdx);
                                                AppState.chatMessages.removeAt(qIdx);
                                              } else {
                                                AppState.chatMessages.removeAt(qIdx);
                                                AppState.chatMessages.removeAt(aIdx);
                                              }
                                            } else if (qIdx != -1) {
                                              AppState.chatMessages.removeAt(qIdx);
                                            }
                                          });
                                          AppState.saveToStorage(); // 영속화 저장
                                          setSheetState(() {}); // BottomSheet 내부 UI 리빌드
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Q. ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6F4E37))),
                                      Expanded(child: Text(logItem["question"]!, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333)))),
                                    ],
                                  ),
                                  const Divider(height: 20, color: Color(0xFFEADBC8)),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('A. ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC78030))),
                                      Expanded(child: Text(logItem["answer"]!, style: const TextStyle(color: Color(0xFF5C3D2E), height: 1.4))),
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
          );
        }
      ),
    );
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('로그아웃', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333))),
          ],
        ),
        content: const Text('로그아웃 하시겠습니까?\n(활동 기록은 안전하게 유지됩니다)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
            child: const Text('로그아웃', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeView(),
          _buildListView(),
          _buildProfileView(),
        ],
      ),
      bottomNavigationBar: TrendyBottomNav(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
      ),
    );
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  const GlassContainer({super.key, required this.child, this.borderRadius = 24});

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

class TrendyBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  const TrendyBottomNav({super.key, required this.currentIndex, required this.onTap});

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
              GestureDetector(onTap: () => onTap(0), child: _navIcon(Icons.map_rounded, currentIndex == 0)),
              GestureDetector(onTap: () => onTap(1), child: _navIcon(Icons.bookmark_outline_rounded, currentIndex == 1)),
              GestureDetector(onTap: () => onTap(2), child: _navIcon(Icons.person_rounded, currentIndex == 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, bool isActive) {
    return Icon(icon, color: isActive ? const Color(0xFF8D6E63) : Colors.black38, size: 28);
  }
}
