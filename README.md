# StudyGo MMORPG — Aetheria

Fondasi teknis untuk MMORPG **Aetheria**, modul permainan terpisah dari fitur pendidikan StudyGo AI.

## Arah produk
- Gameplay 2D dalam dunia berbasis instance.
- Preview karakter dan equipment 3D.
- PvE dan PvP; dunia dibagi menjadi shard/instance agar dapat diskalakan.
- Tidak ada karakter starter gratis: pemain melihat koleksi dan preview, lalu memperoleh karakter melalui toko sebelum masuk gameplay.
- Fitur pendidikan StudyGo tetap dapat digunakan tanpa membeli karakter atau item game.

## Arsitektur awal
- **Flutter**: aplikasi StudyGo dan akses akun.
- **Unity**: klien game 2D dan viewer karakter 3D.
- **PHP Native + MySQL/MariaDB**: akun game, katalog karakter, inventaris, transaksi, IAP dan administrasi.
- **Dedicated realtime server**: simulasi dunia, gerakan, combat dan sinkronisasi.
- **Redis**: cache, presence, antrean dan koordinasi sementara.
- **CDN/Object Storage**: sprite, model, audio dan asset game.

## Status
Repositori ini berisi fondasi dan prototipe awal, bukan game yang sudah playable. Setiap modul akan dikembangkan dan diuji bertahap.

## Prinsip keamanan
Server menjadi otoritas untuk saldo, kepemilikan karakter, equipment, combat penting, transaksi dan hasil PvP. Jangan pernah menaruh secret/API key di klien Unity atau Flutter.
