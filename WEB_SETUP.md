# Scrole Web

## Préparer l'environnement Web

La version Web utilise le même schéma SQLite local que les applications mobiles, avec l'implémentation WASM persistée dans IndexedDB. Après récupération de la branche :

```bash
flutter pub get
bash tool/setup_web_sqlite.sh
flutter run -d chrome
```

Pour produire les fichiers de déploiement :

```bash
flutter build web --release
```

Le script SQLite génère `web/sqlite3.wasm` et `web/sqflite_sw.js`. Ces deux fichiers doivent être présents dans le dossier `web/` au moment du build. Garder le même port pendant les tests locaux : IndexedDB est isolé par origine/port.

## Limites actuellement connues

- Les notifications dans l'application utilisent Supabase Realtime. Les notifications push navigateur ne sont pas activées : elles nécessitent les options Firebase Web, une clé VAPID et le service worker Firebase.
- Les médias et fichiers de conversation doivent encore être adaptés aux API navigateur (XFile/bytes/Blob) avant de considérer la messagerie multimédia comme prête pour la production.
- Le moteur E2EE Rust/OpenMLS doit être compilé et validé pour WebAssembly avant d'activer la messagerie chiffrée sur navigateur. Le chiffrement n'est jamais désactivé en remplacement.
- Les URLs partagées sont lues depuis l'URL initiale du navigateur. L'hébergement doit réécrire les routes applicatives vers `index.html` pour permettre l'ouverture directe d'un lien.
- `sqflite_common_ffi_web` utilise SQLite/WASM et IndexedDB. Sa documentation signale encore des limites expérimentales et l'absence de support de plusieurs connexions persistantes au même fichier.

La branche mobile conserve son implémentation SQLite native et ses services natifs.
