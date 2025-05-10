import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'
    hide EmailAuthProvider, PhoneAuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'guest_book_message.dart';

enum Attending {
  yes,
  no,
  unknown
}

class ApplicationState extends ChangeNotifier {

  ApplicationState() {
    init();
  }

  bool _loggedIn = false;
  bool get loggedIn => _loggedIn;

  StreamSubscription<QuerySnapshot>? _guestBookSubscription;
  List<GuestBookMessage> _guestBookMessages = [];
  List<GuestBookMessage> get guestBookMessages => _guestBookMessages;

  int _attendees = 0;
  int get attendees => _attendees;

  Attending _attending = Attending.unknown;
  StreamSubscription<DocumentSnapshot>? _attendingSubscription;
  Attending get attending => _attending;
  set attending(Attending attending) {
    final userDoc = FirebaseFirestore.instance
        .collection('attendees')
        .doc(FirebaseAuth.instance.currentUser!.uid);
    if (attending == Attending.yes)
      userDoc.set(<String, dynamic>{'attending': true});
    else
      userDoc.set(<String, dynamic>{'attending': false});
  }

  StreamSubscription<QuerySnapshot>? _listenerCountSub;

  Future<void> init() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseUIAuth.configureProviders([
      EmailAuthProvider(),
    ]);

    // Query without logging in to determine the number of attendees
    /*
    This is not the most efficient way to get the attendees count.
    If the app had thousands of users and queries, it would be more efficient
    to have a Single Attendees Value that is stored in a separate
    Firestore document (i.e., collection), and then I could increment or
    decrement that value depending on whether or not somebody decides to attend.
     */
    _listenerCountSub = FirebaseFirestore.instance
        .collection('attendees')
        .where('attending', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
          _attendees = snapshot.docs.length;
          notifyListeners();
    });

    FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null) {
        _loggedIn = true;
        _guestBookSubscription = FirebaseFirestore.instance
            .collection('guestbook')
            .orderBy('timestamp', descending: true)
            .limit(100) /* Optional. For advanced usage apply pagination. */
            .snapshots()
            .listen((snapshot) {
          _guestBookMessages = [];
          for (final document in snapshot.docs) {
            _guestBookMessages.add(
              GuestBookMessage(
                  name: document.data()['name'] as String,
                  message: document.data()['text'] as String
              ),
            );
          }
          notifyListeners();
        });

        // Query that's only active while a user is logged in
        // to determine whether the user is attending
        _attendingSubscription = FirebaseFirestore.instance
            .collection('attendees')
            .doc(user.uid)
            .snapshots()
            .listen((snapshot) {
              if (snapshot.data() != null) {
                if (snapshot.data()!['attending'] as bool) {
                  _attending = Attending.yes;
                } else {
                  _attending = Attending.no;
                }
              } else {
                _attending = Attending.unknown;
              }
              notifyListeners();
            }
        );

      } else {
        _loggedIn = false;
        _guestBookMessages = [];
        _guestBookSubscription?.cancel();
        _attendingSubscription?.cancel();
      }

      notifyListeners();
    });
  }

  Future<DocumentReference> addMessageToGuestBook(String message) {
    if (!_loggedIn) {
      throw Exception('Must be logged in');
    }

    return FirebaseFirestore.instance
        .collection('guestbook')
        .add(<String, dynamic>{
      'text': message,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'name': FirebaseAuth.instance.currentUser!.displayName,
      'userId': FirebaseAuth.instance.currentUser!.uid,
    });
  }

  @override
  void dispose() {
    _listenerCountSub?.cancel(); // Optional - Best practice
    super.dispose();
  }
}
