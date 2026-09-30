import 'package:firebase_core/firebase_core.dart';
  
import '../../firebase_options.dart';

class FirebaseInitializer {
  static Future<void> ensureInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }
}
