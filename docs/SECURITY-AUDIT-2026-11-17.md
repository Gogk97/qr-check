# Security Audit — Qristal (qr-check)

**Tanggal:** 2026-11-17 · **Metode:** source review (read-only), tanpa uji ke production
**Scope:** 24 file Dart, `supabase/schema.sql` + 2 migrasi, 2 Edge Function, konfigurasi
Android/iOS, `docs/google_apps_script_code.js`, `pubspec.lock`

Tidak ada file diubah oleh audit ini.

---

## Temuan

### 🔴 HIGH

#### H-1 · Kuota bisa ditambah tanpa batas lewat fallback lokal
- **Lokasi:** `lib/services/quota_service.dart:170` (`claim_ad_reward`) & `:152-166` (fallback offline)
- **Mekanisme:** RPC `claim_ad_reward` **tidak ada** di database (yang ada `grant_ad_reward`,
  service_role only). Setiap panggilan gagal → `catch` → aplikasi menambah kuota **lokal**
  (`prefs +1`). Tombol "Nonton Iklan (+1 Kuota)" bisa ditekan berulang tanpa batas.
- **Dampak:** kuota gratis tak terbatas → tidak ada alasan membeli PRO; ledger server
  tidak pernah mencatat, sehingga Anda kehilangan revenue dan data.
- **Perbaikan:** buat RPC server-side `claim_ad_reward` yang memverifikasi AdMob SSV
  (atau hapus tombol selama iklan masih simulasi). Hapus fallback `+amount` lokal;
  saat offline, tampilkan state "butuh koneksi" bukan menambah kuota.

#### H-2 · `is_pro` lokal dipakai untuk melewati server
- **Lokasi:** `lib/services/quota_service.dart:111` (`hasEnoughQuota`) dan `:121` (`consumeQuota`)
- **Mekanisme:** `if (isPro) return true;` dievaluasi dari cache SharedPreferences
  **sebelum** memanggil `consume_quota`. Nilai cache bisa diubah lewat rooted device,
  ADB backup, atau restore backup lama.
- **Dampak:** user non-PRO bisa menghapus massal tanpa batas tanpa pernah menyentuh server.
- **Perbaikan:** selalu panggil RPC dan pakai `is_pro` dari respons server; cache hanya
  untuk tampilan (read-only UI), bukan keputusan otorisasi.

#### H-3 · Sesi auth tersimpan plaintext + `allowBackup` aktif
- **Lokasi:** `android/app/src/main/AndroidManifest.xml` (tidak ada `allowBackup`)
  · tidak ada `flutter_secure_storage` di dependensi
- **Mekanisme:** `supabase_flutter` menyimpan access+refresh token di SharedPreferences;
  Android default `allowBackup=true` sehingga data app bisa diekstrak lewat ADB backup /
  auto-backup. Prefs juga memuat `user_is_pro_status_v1`.
- **Dampak:** token sesi (dan status PRO) bisa diambil dari backup tanpa root.
- **Perbaikan:** `android:allowBackup="false"`, `android:fullBackupContent="false"`,
  tambahkan `dataExtractionRules` (API 31+); pindahkan sesi ke `flutter_secure_storage`
  (Keystore/Keychain).

### 🟠 MEDIUM

#### M-1 · Device quota farming (device_id dari client)
- **Lokasi:** `supabase/schema.sql:490-535` (`claim_device_welcome_quota`)
- **Mekanisme:** `p_device_id` dipercaya apa adanya. Device ID baru = 10 kuota baru
  (guest 5). Tidak ada batas jumlah device per akun maupun rate limit.
- **Dampak:** kuota gratis tak terbatas cukup dengan mengirim device_id acak.
- **Perbaikan:** batasi klaim per akun (mis. maks 1–2 device), rate limit per IP/uid,
  dan verifikasi integritas app (Play Integrity API) sebelum memberi bonus.

#### M-2 · `device_id` bisa ditulis client → mengganggu kuota user lain
- **Lokasi:** `supabase/schema.sql:154-164` (GRANT UPDATE `device_id`) +
  `consume_quota` baris `281-285`
- **Mekanisme:** client boleh mengubah `profiles.device_id`. `consume_quota` lalu
  menyinkronkan sisa kuota ke `device_allowances` dan ke **semua profil** dengan
  `device_id` yang sama.
- **Dampak:** dengan mengetahui device_id korban, penyerang bisa menurunkan kuota korban
  atau berbagi pool kuota.
- **Perbaikan:** cabut `device_id` dari daftar kolom yang bisa di-UPDATE client;
  set hanya lewat RPC yang memvalidasi kepemilikan.

#### M-3 · Google Apps Script Web App tanpa autentikasi
- **Lokasi:** `docs/google_apps_script_code.js:50` (`doPost`), `:160` (`doGet`)
- **Mekanisme:** `doPost` menerima `SYNC_USER` / `UPDATE_QUOTA` tanpa token/secret apa pun;
  `doGet` mengembalikan 3 spreadsheet ID. Script ini masih ada di repo (commit `3f30adc`).
  App sudah tidak memanggilnya (`CloudSyncService` deprecated), tapi deployment lama
  berpotensi masih hidup.
- **Dampak:** siapa pun yang tahu URL bisa menyuntik/menimpa baris data user di Sheets,
  dan ID spreadsheet terekspos publik.
- **Perbaikan:** **matikan deployment** Web App (atau tambahkan shared secret + validasi
  `e.parameter.token`), dan hapus spreadsheet ID dari repo publik.

#### M-4 · Tidak ada rate limiting pada RPC
- **Lokasi:** `consume_quota`, `claim_device_welcome_quota`, `submit_payment`
- **Mekanisme:** semua `GRANT EXECUTE TO authenticated`, tanpa batas frekuensi.
- **Dampak:** spam RPC → biaya database/egress naik, potensi DoS akun sendiri.
- **Perbaikan:** rate limit per uid (tabel counter + `now()`), atau pindahkan operasi
  sensitif ke Edge Function dengan pembatasan.

### 🟡 LOW

| # | Lokasi | Risiko | Perbaikan |
| :--- | :--- | :--- | :--- |
| L-1 | `lib/services/auth_service.dart:137` | `loginWithGoogleDevFallback()` masih ada di kode rilis (tidak dipanggil UI) — membuat akun "Google" palsu tanpa verifikasi | Hapus, atau bungkus `if (kDebugMode)` |
| L-2 | `lib/services/payment_service.dart:52-55` | Upload bukti gagal ditelan (`catch` → lanjut), payment tetap dibuat tanpa bukti | Batalkan submit bila upload gagal |
| L-3 | `lib/services/*` | `debugPrint` memuat detail error/path (bukan token) — terlihat di logcat | Matikan log verbose di build rilis |
| L-4 | `android/app/build.gradle` | Tidak ada certificate pinning | Opsional; pertimbangkan untuk app finansial-adjacent |

---

## Yang sudah benar (jangan diubah)

- RLS aktif di seluruh tabel; **tidak ada** policy `USING (true)`.
- Kolom sensitif `is_pro` / `remaining_quota` **tidak** di-grant UPDATE ke client.
- Semua RPC `SECURITY DEFINER` dengan `SET search_path = public`; EXECUTE dicabut dari
  `PUBLIC`/`anon`.
- `approve_payment` / `reject_payment` dijaga `is_admin()` dari `app_metadata`
  (server-controlled, bukan `user_metadata`).
- `submit_payment` memaksa nominal `15000` dan memvalidasi folder bukti = `auth.uid()`.
- Storage `payment-proofs`: privat, policy per-folder, limit 5 MB, MIME whitelist.
- `grant_ad_reward` hanya `service_role` (jalur SSV), `grant_pro_from_play` hanya
  `service_role` + proteksi token yang sudah diklaim akun lain.
- `quota_ledger` append-only (trigger menolak UPDATE/DELETE).
- Anon key yang dikirim di app memang `role: anon` (aman dipublikasikan); **tidak ada**
  service-role key di dalam aplikasi.
- iOS tanpa pengecualian ATS; tidak ada WebView / `url_launcher` → tidak ada vektor
  phishing dari isi QR.

---

## Roadmap perbaikan

| No | Komponen | Aksi | Prioritas |
| :--- | :--- | :--- | :--- |
| 1 | Kuota | Hapus fallback `+kuota` lokal; buat `claim_ad_reward` server-side (SSV) | **P0** |
| 2 | Otorisasi | `consumeQuota` selalu lewat server, jangan short-circuit `is_pro` lokal | **P0** |
| 3 | Android + storage | `allowBackup=false`, `fullBackupContent=false`, sesi → `flutter_secure_storage` | **P0** |
| 4 | Kuota device | Batas device per akun + rate limit + Play Integrity | P1 |
| 5 | Database | Cabut GRANT UPDATE `device_id`; set via RPC tervalidasi | P1 |
| 6 | Apps Script | Matikan deployment lama / tambah secret; hapus spreadsheet ID dari repo | P1 |
| 7 | RPC | Rate limiting `consume_quota` & `claim_device_welcome_quota` | P2 |
| 8 | Kode | Hapus `loginWithGoogleDevFallback`; perbaiki alur upload bukti | P2 |
| 9 | Transport | Certificate pinning (opsional) | P2 |

---

## Status perbaikan — 2026-11-17

| Temuan | Status | Perubahan yang diterapkan |
| :--- | :--- | :--- |
| **H-1** kuota gratis tak terbatas | ✅ Fixed | RPC baru `claim_ad_reward()` (maks 5/hari + rate limit 20/jam); `addQuota()` tidak lagi menambah kuota lokal |
| **H-2** `is_pro` lokal bypass server | ✅ Fixed | `consumeQuota()` selalu memanggil server; kuota dipotong **sebelum** foto dihapus; `refund_quota()` mengembalikan kuota bila penghapusan dibatalkan |
| **H-3** token plaintext + backup | ✅ Fixed | `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules`; sesi auth pindah ke `flutter_secure_storage` (dengan migrasi otomatis dari SharedPreferences) |
| **M-1** device quota farming | ✅ Fixed | `claim_device_welcome_quota()` menolak `DEVICE_MISMATCH`, batas 2 device/akun, rate limit 10/jam |
| **M-2** cross-user quota | ✅ Fixed | `GRANT UPDATE (device_id)` dicabut; `update_device_info()` hanya mengikat device sekali |
| **M-3** Apps Script tanpa auth | 🟡 Mitigated | Skrip: `SYNC_TOKEN` wajib, ID spreadsheet pindah ke Script Properties, `doGet` tidak lagi membocorkan ID. **Aksi manual tersisa: arsipkan deployment lama** |
| **M-4** tanpa rate limit | ✅ Fixed | `check_rate_limit()` dipakai `consume_quota`, `submit_payment`, `claim_ad_reward`, `claim_device_welcome_quota` |
| **L-1** dev Google fallback | ✅ Fixed | `loginWithGoogleDevFallback()` dihapus |
| **L-2** payment tanpa bukti | ✅ Fixed | Upload bukti gagal → `submitPayment` dibatalkan (tidak membuat record) |
| **L-3** log verbose | ✅ Fixed | `AppLog.d()` (no-op di build rilis) menggantikan 46 pemanggilan `debugPrint` |
| **L-4** certificate pinning | ⚠️ Accepted risk | Tidak diterapkan: rotasi sertifikat berisiko mematikan app; koneksi sudah TLS ke Supabase/Google |

### Bukti verifikasi

| Cek | Hasil |
| :--- | :--- |
| `flutter analyze lib` | No issues found |
| `flutter test` | 9/9 passed (test kuota diperbarui: offline **harus** ditolak) |
| `flutter build apk --debug` | ✓ built |
| `flutter build appbundle --release` | ✓ built (38,3 MB) |
| Merged manifest | `allowBackup="false"`, `usesCleartextTraffic="false"`, `dataExtractionRules` ada |
| Parser SQL (3 migrasi) | 14 / 17 / 25 statement OK |
| `deno check` + `deno test` | bersih · 29/29 passed |

### Catatan trade-off (perlu diketahui)

1. **Hapus foto sekarang butuh koneksi** (user gratis). Tanpa jaringan, `consumeQuota`
   menolak dan UI menampilkan pesan. User **PRO tetap bisa hapus offline** karena
   tidak ada pemotongan kuota.
   **Keputusan (2026-11-17): dipertahankan apa adanya.** Alternatif (antrian offline /
   cache kuota lokal) mudah diakali; voucher offline bertanda tangan server dinilai
   over-engineering untuk produk Rp 15.000.
2. **Reward iklan masih client-trusted** (belum ada AdMob SSV). Batas 5/hari + rate limit
   membuat farming tidak ekonomis. Saat AdMob terpasang, ganti ke `grant_ad_reward`
   lewat Edge Function SSV dan hapus `claim_ad_reward`.
3. **Satu akun maksimal 2 device** untuk bonus kuota. Perangkat ketiga tetap bisa login,
   tetapi tidak menerima bonus (memakai sisa kuota server).
