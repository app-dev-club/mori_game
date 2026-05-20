import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mori_game/models/CardModel.dart';
import 'package:mori_game/logic/MoriLogic.dart';
import 'package:mori_game/widgets/CardWidget.dart';
import 'dart:async';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final DatabaseReference _roomRef = FirebaseDatabase.instance.ref('rooms/test_room');
  StreamSubscription<DatabaseEvent>? _roomSubscription;

  late String myId;
  String? hostId;
  bool get isHost => myId == hostId;

  List<CardModel> firebaseDeck = []; 
  List<CardModel> myHand = []; 
  List<String> playerIds = [];
  
  int fieldNumber = -1;
  Suit fieldSuit = Suit.joker;
  bool isInitialPhase = true;
  bool isInitializing = true;
  int currentTurnIndex = 0;
  bool isDrawCompetitive = false; 

  @override
  void initState() {
    super.initState();
    myId = DateTime.now().millisecondsSinceEpoch.toString();
    _listenToRoom();
    _initializeGame();
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  // --- 初期化: プレイヤーリストの整合性を保ちつつ入室 ---
  Future<void> _initializeGame() async {
    setState(() => isInitializing = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    
    final snapshot = await _roomRef.get();
    
    List<String> currentPlayers = [];
    if (snapshot.child('players').exists) {
      currentPlayers = List<String>.from(snapshot.child('players').value as List);
    }
    
    if (!currentPlayers.contains(myId)) {
      currentPlayers.add(myId);
      await _roomRef.child('players').set(currentPlayers);
    }

    if (!snapshot.exists || snapshot.child('host').value == null) {
      await _setupNewRoom();
    } else {
      await _joinAsGuest();
    }
    setState(() => isInitializing = false);
  }

  Future<void> _setupNewRoom() async {
    List<CardModel> fullDeck = _generateFullDeck();
    fullDeck.shuffle();
    final initialHand = fullDeck.sublist(0, 5);
    fullDeck.removeRange(0, 5);
    final firstCard = fullDeck.removeLast();

    await _roomRef.set({
      'host': myId,
      'players': [myId],
      'deck': fullDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'field': {'number': firstCard.number, 'suit': firstCard.suit.name},
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'isDrawCompetitive': false,
    });

    setState(() {
      myHand = initialHand;
      firebaseDeck = fullDeck;
    });
  }

  Future<void> _joinAsGuest() async {
    int retryCount = 0;
    while (retryCount < 5) {
      final snapshot = await _roomRef.get();
      final deckData = snapshot.child('deck').value as List?;
      if (deckData != null && deckData.length >= 5) {
        List<CardModel> currentDeck = deckData.map((item) {
          final map = item as Map;
          return CardModel(number: (map['number'] as num).toInt(), suit: Suit.values.firstWhere((e) => e.name == map['suit']));
        }).toList();
        setState(() {
          myHand = currentDeck.sublist(0, 5);
          firebaseDeck = currentDeck.sublist(5);
        });
        await _roomRef.update({'deck': firebaseDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList()});
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
      retryCount++;
    }
  }

  // --- リアルタイム監視 ---
  void _listenToRoom() {
    _roomSubscription = _roomRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      if (mounted) {
        setState(() {
          hostId = data['host']?.toString();
          playerIds = List<String>.from(data['players'] ?? []);
          currentTurnIndex = (data['currentTurnIndex'] as num? ?? 0).toInt();
          isDrawCompetitive = data['isDrawCompetitive'] ?? false;
          
          if (data['deck'] != null) {
            firebaseDeck = (data['deck'] as List).map((item) {
              final map = item as Map;
              return CardModel(number: (map['number'] as num).toInt(), suit: Suit.values.firstWhere((e) => e.name == map['suit']));
            }).toList();
          }
          final field = data['field'] as Map?;
          if (field != null) {
            fieldNumber = (field['number'] as num).toInt();
            fieldSuit = Suit.values.firstWhere((e) => e.name == field['suit']);
            isInitialPhase = data['isInitialPhase'] ?? true;
          }
        });
        if (isHost && isInitialPhase && fieldNumber != -1 && !_hasInitialMatchingCard()) {
          _drawNextInitialCard();
        }
      }
    });
  }

  // --- ターン・割り込み判定ロジック ---
  bool _canIPlay(CardModel card) {
    if (isInitialPhase) return card.number == fieldNumber;

    // 1. 同じ数字はいつでも割り込みOK (早い者勝ち)
    if (card.number == fieldNumber) return true;

    int myIndex = playerIds.indexOf(myId);
    if (myIndex == -1) return false;
    int officialTurnIndex = currentTurnIndex % playerIds.length;
    
    // 2. ドロー後の早い者勝ち
    if (isDrawCompetitive) {
      int drawerIndex = (currentTurnIndex - 1 + playerIds.length) % playerIds.length;
      if (myIndex == drawerIndex || myIndex == officialTurnIndex) {
        if (card.suit == fieldSuit) return true;
      }
      return false;
    }

    // 3. 通常ターン
    if (myIndex == officialTurnIndex && card.suit == fieldSuit) return true;

    return false;
  }

  void _playCard(CardModel card) {
    if (!_canIPlay(card)) {
      _showErrorSnackBar("今は出せません");
      return;
    }

    int myIndex = playerIds.indexOf(myId);
    if (myIndex == -1) return;

    setState(() => myHand.remove(card));

    // 次のターンは、誰がどのような形で出したとしても「出した人の次」に回す
    int nextTurnIndex = (myIndex + 1) % playerIds.length;

    _roomRef.update({
      'field': {'number': card.number, 'suit': card.suit.name},
      'isInitialPhase': false,
      'currentTurnIndex': nextTurnIndex,
      'isDrawCompetitive': false,
    });
  }

  Future<void> _drawCard() async {
    if (firebaseDeck.isEmpty || isInitialPhase) return;
    if (myHand.length >= 7) return;

    int myIndex = playerIds.indexOf(myId);
    if (currentTurnIndex % playerIds.length != myIndex) return;

    final snapshot = await _roomRef.child('deck').get();
    if (snapshot.exists) {
      List<dynamic> deckData = List.from(snapshot.value as List);
      var lastCardMap = deckData.removeLast() as Map;
      CardModel drawnCard = CardModel(number: (lastCardMap['number'] as num).toInt(), suit: Suit.values.firstWhere((e) => e.name == lastCardMap['suit']));

      setState(() => myHand.add(drawnCard));
      
      // ドロー後は「次の人」に公式ターンを渡し、競争モードをONにする
      await _roomRef.update({
        'deck': deckData,
        'currentTurnIndex': (currentTurnIndex + 1) % playerIds.length,
        'isDrawCompetitive': true,
      });
    }
  }

  // --- ヘルパーメソッド ---
  List<CardModel> _generateFullDeck() {
    List<CardModel> deck = [];
    for (var suit in Suit.values) {
      if (suit == Suit.joker) { deck.add(CardModel(suit: suit, number: 0)); }
      else { for (int i = 1; i <= 13; i++) { deck.add(CardModel(suit: suit, number: i)); } }
    }
    return deck;
  }

  bool _hasInitialMatchingCard() => fieldSuit == Suit.joker || myHand.any((c) => c.number == fieldNumber);

  Future<void> _drawNextInitialCard() async {
    if (firebaseDeck.isEmpty) return;
    await Future.delayed(const Duration(seconds: 2));
    if (mounted && isInitialPhase && !_hasInitialMatchingCard()) {
      CardModel nextCard = firebaseDeck.removeLast();
      await _roomRef.update({
        'field': {'number': nextCard.number, 'suit': nextCard.suit.name},
        'deck': firebaseDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      });
    }
  }

  bool _canMori() {
    if (isInitialPhase || fieldNumber == -1) return false;
    if (myHand.length == 2) return MoriLogic.checkNormalMori(fieldNumber, myHand) || MoriLogic.checkSpecialMori(fieldNumber, myHand);
    if (myHand.length == 1) return myHand[0].number == fieldNumber;
    return false;
  }

  void _showErrorSnackBar(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 500)));

  void _showResultDialog(String title, String message) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      title: Text(title), content: Text(message),
      actions: [TextButton(onPressed: () { Navigator.pop(context); _resetGame(); }, child: const Text('リセット'))],
    ));
  }

  void _resetGame() => _roomRef.remove().then((_) => _initializeGame());

  @override
  Widget build(BuildContext context) {
    if (isInitializing || fieldNumber == -1 || myHand.isEmpty) {
      return const Scaffold(backgroundColor: Color(0xFF1B5E20), body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    int myIndex = playerIds.indexOf(myId);
    int officialTurnIndex = currentTurnIndex % playerIds.length;
    bool isMyTurn = (officialTurnIndex == myIndex);
    
    // 自分がドローした本人かどうか
    bool iAmDrawer = false;
    if (isDrawCompetitive) {
      int drawerIndex = (currentTurnIndex - 1 + playerIds.length) % playerIds.length;
      if (myId == playerIds[drawerIndex]) iAmDrawer = true;
    }

    String turnText = isMyTurn ? "あなたの番です" : "待機中...";
    if (isDrawCompetitive) turnText = (isMyTurn || iAmDrawer) ? "ドロー競争中！" : "相手がドローしました";

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Text(isHost ? 'もり (ホスト)' : 'もり (ゲスト)'),
        backgroundColor: Colors.transparent,
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('山札: ${firebaseDeck.length}')))],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(turnText, style: TextStyle(color: (isMyTurn || iAmDrawer) ? Colors.orange : Colors.white70, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: isMyTurn ? _drawCard : null,
              child: Container(
                width: 70, height: 100,
                decoration: BoxDecoration(
                  color: !isMyTurn || isInitialPhase ? Colors.grey : Colors.blueGrey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Center(child: Text('ドロー', style: TextStyle(color: Colors.white))),
              ),
            ),
          ),
          Column(
            children: [
              Text(isInitialPhase ? '【初期】数字を合わせろ' : '場: ${fieldSuit.name} $fieldNumber', 
                style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              CardWidget(card: CardModel(suit: fieldSuit, number: fieldNumber), onTap: () {}),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: _canMori() ? () => _showResultDialog("もり！", "上がりです！") : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                  child: const Text('もり！'),
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: myHand.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: CardWidget(card: c, onTap: () => _playCard(c)),
                    )).toList(),
                  ),
                ),
                Text('手札: ${myHand.length}/7', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}