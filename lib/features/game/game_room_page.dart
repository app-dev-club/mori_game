import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart'; // これが必要
import 'dart:async';
import '../../services/firebase_db.dart';
import 'game_board_view.dart';

class GameRoomPage extends StatefulWidget {
  final String roomId;
  final bool isPrivate;
  const GameRoomPage({super.key, required this.roomId, this.isPrivate = false});

  @override
  State<GameRoomPage> createState() => _GameRoomPageState();
}

class _GameRoomPageState extends State<GameRoomPage> {
  late final FirebaseDB _db;
  StreamSubscription? _sub;
  String myId = DateTime.now().millisecondsSinceEpoch.toString();

  String? hostId;
  List<CardWidget> deck = [];
  List<CardWidget> myHand = [];
  List<String> playerIds = [];
  Map<String, int> handCounts = {};
  int fieldNumber = -1;
  Suit fieldSuit = Suit.joker;
  bool isInitialPhase = true;
  int currentTurn = 0;
  String? lastPlayerId;

  @override
  void initState() {
    super.initState();
    _db = FirebaseDB(widget.roomId); // firebase_db.dartのFirebaseDBを正しく参照
    _initialize();
  }

  Future<void> _initialize() async {
    final snap = await _db.getSnapshot();
    if (!snap.exists) {
      await _setupNewRoom();
    } else {
      await _joinRoom();
    }
    _sub = _db.roomStream.listen(_onDataReceived);
  }

  void _onDataReceived(DatabaseEvent event) { // DatabaseEventが認識されます
    final data = event.snapshot.value as Map?;
    if (data == null || !mounted) return;

    setState(() {
      hostId = data['host'];
      playerIds = List<String>.from(data['players'] ?? []);
      currentTurn = data['currentTurnIndex'] ?? 0;
      lastPlayerId = data['lastPlayerId'];
      
      if (data['playerHands'] != null) handCounts = Map<String, int>.from(data['playerHands']);
      
      if (data['field'] != null) {
        fieldNumber = data['field']['number'];
        fieldSuit = Suit.values.firstWhere((e) => e.name == data['field']['suit'], orElse: () => Suit.joker);
      }
      
      if (data['deck'] != null) {
        deck = (data['deck'] as List).map((i) {
          return CardWidget(
            number: (i['number'] as num).toInt(), 
            suit: Suit.values.firstWhere((e) => e.name == i['suit'])
          );
        }).toList();
      } else {
        deck = [];
      }
    });
  }

  // (以下、_setupNewRoom, _joinRoom, _onPlay, _generateDeck は以前の通り)
  Future<void> _setupNewRoom() async {
    List<CardWidget> fullDeck = _generateDeck()..shuffle();
    final hand = fullDeck.sublist(0, 5);
    fullDeck.removeRange(0, 5);
    await _db.setupRoom(myId, fullDeck, widget.isPrivate);
    setState(() => myHand = hand);
  }

  Future<void> _joinRoom() async {
    final snap = await _db.getSnapshot();
    List<String> p = snap.child('players').exists ? List<String>.from(snap.child('players').value as List) : [];
    if (!p.contains(myId)) p.add(myId);
    await _db.updateGameStatus({'players': p, 'playerHands/$myId': 5});
    setState(() => myHand = deck.take(5).toList());
  }

  void _onPlay(CardWidget card) {
    if (fieldNumber == -1) return;
    setState(() => myHand.remove(card));
    _db.playCard((currentTurn + 1) % playerIds.length, card, myId);
    _db.updateGameStatus({'playerHands/$myId': myHand.length});
  }

  List<CardWidget> _generateDeck() {
    return [for (var s in Suit.values) if (s != Suit.joker) for (var i = 1; i <= 13; i++) CardWidget(number: i, suit: s), const CardWidget(number: 0, suit: Suit.joker)];
  }

  @override
  Widget build(BuildContext context) {
    return GameBoardView(
      roomId: widget.roomId, 
      fieldNumber: fieldNumber, 
      fieldSuit: fieldSuit,
      myHand: myHand, 
      playerIds: playerIds, 
      myId: myId, 
      handCounts: handCounts,
      isMyTurn: playerIds.isNotEmpty && currentTurn % playerIds.length == playerIds.indexOf(myId),
      isHost: myId == hostId, 
      lastPlayerId: lastPlayerId, 
      isInitialPhase: isInitialPhase,
      onPlay: _onPlay, 
      onDraw: () {}, 
      onFlip: () {
        if (deck.isEmpty) return;
        final first = deck.last;

        final remainingDeckData = deck
          .sublist(0, deck.length - 1)
          .map((c) => {'number': c.number, 'suit': c.suit.name})
          .toList();

        _db.updateGameStatus({
          'gameStarted': true, 
          'field': {
            'number': first.number, 
            'suit': first.suit.name
          },
          'deck': remainingDeckData,
          'isInitialPhase': false,
          'lastPlayerId': 'system',
        });
      },
      onMori: () => print("Win"),
    );
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}