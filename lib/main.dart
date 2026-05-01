import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'dart:developer';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterNaverMap().init(
    clientId: 'i6wtcd41v7',
    onAuthFailed: (ex) => log("네이버 지도 인증 오류: $ex"),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

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
              ElevatedButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MainScreen(userName: '소연'),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEE500),
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '카카오로 시작하기',
                  style: TextStyle(fontWeight: FontWeight.bold),
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
  const MainScreen({super.key, required this.userName});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final TextEditingController _chatController = TextEditingController();
  NaverMapController? _mapController;
  NLatLng _currentLocation = const NLatLng(37.5615, 126.9248);

  // ✅ 수정 완료: 변수를 실제 지도 로딩 판단 시 사용합니다.
  bool _isLocationFetched = false;

  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _messages = [
      {
        "isMe": false,
        "text": "${widget.userName}님, 안녕하세요! 어떤 분위기의 카페를 찾으시나요?",
        "type": "text",
      },
    ];
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = NLatLng(position.latitude, position.longitude);
      _isLocationFetched = true; // ✅ 값 변경
    });
  }

  Future<void> _handleChatSubmit(String text) async {
    if (text.trim().isEmpty) return;
    _chatController.clear();

    setState(() {
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

      setState(() => _messages.removeLast());
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _messages.add({
            "isMe": false,
            "text": data['choices'][0]['message']['content'],
            "type": "text",
          });
          _messages.add({"isMe": false, "type": "carousel"});
        });
      }
    } catch (e) {
      setState(
        () => _messages.add({
          "isMe": false,
          "text": "연결 오류가 발생했어요.",
          "type": "text",
        }),
      );
    }
  }

  Widget _buildHomeView() {
    // ✅ 수정 완료: 위치를 가져오는 중이면 로딩 인디케이터를 보여줍니다.
    if (!_isLocationFetched) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6F4E37)),
      );
    }

    return Stack(
      children: [
        NaverMap(
          options: NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: _currentLocation,
              zoom: 15,
            ),
            locationButtonEnable: true,
          ),
          onMapReady: (controller) => _mapController = controller,
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
            child: const TextField(
              decoration: InputDecoration(
                hintText: '카페 분위기를 검색해보세요',
                border: InputBorder.none,
                suffixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 30,
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
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text(
          '분위기별 카페',
          style: TextStyle(
            color: Color(0xFF6F4E37),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 4,
        itemBuilder: (context, index) => _buildCafeCard(
          '오버딥 카페',
          '조용한 우드톤',
          const NLatLng(37.5620, 126.9250),
        ),
      ),
    );
  }

  Widget _buildCafeCard(String name, String desc, NLatLng loc) {
    return GestureDetector(
      onTap: () => _showCafeDetail(name, desc),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          // ✅ 수정 완료: .withOpacity -> .withValues
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
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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
      backgroundColor: const Color(0xFFFAF7F2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'AI 챗봇 상담',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6F4E37),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    if (msg["type"] == "carousel")
                      return _buildCarousel(setModalState);
                    return _buildChatBubble(
                      msg["text"],
                      msg["isMe"],
                      msg["type"] == "loading",
                    );
                  },
                ),
              ),
              TextField(
                controller: _chatController,
                onSubmitted: (val) async {
                  await _handleChatSubmit(val);
                  setModalState(() {});
                },
                decoration: InputDecoration(
                  hintText: '분위기를 말해주세요...',
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () async {
                      await _handleChatSubmit(_chatController.text);
                      setModalState(() {});
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
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
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF6F4E37) : Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                text,
                style: TextStyle(color: isMe ? Colors.white : Colors.black),
              ),
      ),
    );
  }

  Widget _buildCarousel(Function setModalState) {
    return Container(
      height: 150,
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCarouselItem('오버딥 카페', const NLatLng(37.5620, 126.9250)),
          _buildCarouselItem('연남동 우드밀', const NLatLng(37.5630, 126.9260)),
        ],
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
        _mapController?.addOverlay(NMarker(id: name, position: loc));
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

  void _showCafeDetail(String name, String desc) {
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
            Text(desc, style: const TextStyle(color: Color(0xFF6F4E37))),
            const Divider(height: 40),
            const Text(
              'AI 분석 분위기',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('아늑한 조명과 우드톤 가구가 배치되어 집중하기 좋습니다.'),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6F4E37),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () {
                  // ✅ 수정 완료: 한 줄 if문에 중괄호를 씌웠습니다.
                  setState(() {
                    log('저장되었습니다.');
                  });
                },
                child: const Text(
                  '내 저장 리스트에 담기',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeView(),
          _buildListView(),
          const Center(child: Text('프로필 준비 중')),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: const Color(0xFF6F4E37),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: '지도'),
          BottomNavigationBarItem(
            icon: Icon(Icons.format_list_bulleted),
            label: '카페목록',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: '프로필',
          ),
        ],
      ),
    );
  }
}
