# AdMob Integration — Qristal

Dokumen ini menjelaskan integrasi iklan AdMob nyata (rewarded, interstitial,
banner) di aplikasi Qristal, cara mengaktifkan unit produksi, serta batasan
teknis yang harus diketahui sebelum rilis.

---

## 1. Ringkasan arsitektur

| Format | Tempat | Gating |
| :--- | :--- | :--- |
| **Rewarded** | Tombol "+1 Kuota" & opsi "Nonton Iklan" pada hapus massal | Reward hanya diberikan bila Google mengonfirmasi iklan selesai (`onUserEarnedReward`) |
| **Interstitial** | Setelah aksi hapus berhasil | Min. **3 aksi** dan jeda **120 detik**; tidak pernah untuk PRO |
| **Banner (adaptive)** | Di atas bottom navigation bar home | Tidak dimuat untuk PRO; hilang otomatis bila no fill |

Prinsip yang dipegang:

1. **Tidak pernah memblokir fitur inti.** Semua kegagalan iklan (no fill,
   offline, tanpa GMS) dikembalikan sebagai `false`, bukan exception.
2. **Tidak pernah memberi reward tanpa iklan.** Kuota hanya bertambah setelah
   callback reward Google.
3. **PRO bebas iklan 100%.** Semua titik iklan memeriksa `isProUser()`.
4. **Test ads sebagai default.** Mencegah invalid traffic saat development.

---

## 2. File yang terlibat

| File | Fungsi |
| :--- | :--- |
| `lib/constants/ads_config.dart` | Unit ID (test/produksi), kebijakan frekuensi |
| `lib/services/ad_service.dart` | Init SDK, preload, show rewarded/interstitial |
| `lib/widgets/ad_banner.dart` | Banner adaptif, sadar status PRO |
| `lib/services/monetization_service.dart` | Interstitial & rewarded untuk alur hapus massal |
| `lib/services/quota_service.dart` | Rewarded → `addQuota(1)` → RPC `claim_ad_reward` |
| `lib/main.dart` | `AdService.initialize()` saat startup |
| `android/app/src/main/AndroidManifest.xml` | `APPLICATION_ID`, INTERNET, flag optimasi |
| `android/app/build.gradle` | `manifestPlaceholders["admobAppId"]` |

---

## 3. Setup di AdMob (sekali saja)

1. Buka <https://admob.google.com> dengan akun yang sama seperti Play Console.
2. **Apps → Add app → Android** → pilih "App not listed on a store yet" bila
   app belum terbit, isi nama `Qristal` dan package `com.qrcheck.app.qr_check`.
3. Buat 3 ad unit:

   | Nama | Format |
   | :--- | :--- |
   | `qristal_rewarded_quota` | Rewarded |
   | `qristal_interstitial_delete` | Interstitial |
   | `qristal_banner_home` | Banner |

4. Catat **App ID** (`ca-app-pub-XXXX~YYYY`) dan ketiga **Ad unit ID**
   (`ca-app-pub-XXXX/ZZZZ`).
5. Setelah app terbit di Play, tautkan app AdMob ke listing Play Store
   (Apps → App settings → Link to store) agar pembayaran & policy check normal.

> App baru biasanya butuh beberapa jam sampai unit iklan bisa mengisi
> (no fill di awal adalah normal).

---

## 4. Build produksi (mengaktifkan unit asli)

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_TEST_MODE=false \
  --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXXXXXX/1111111111 \
  --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-XXXXXXXX/2222222222 \
  --dart-define=ADMOB_BANNER_ID=ca-app-pub-XXXXXXXX/3333333333 \
  -PadmobAppId=ca-app-pub-XXXXXXXX~4444444444
```

Tanpa flag di atas, build memakai **test ads** (aman, tanpa pendapatan).

Verifikasi cepat setelah build:

```bash
# App ID benar-benar masuk ke manifest gabungan
grep -r "com.google.android.gms.ads.APPLICATION_ID" -A1 \
  build/app/intermediates/merged_manifests/release/AndroidManifest.xml
```

---

## 5. Server-Side Verification (SSV) — langkah berikutnya

Saat ini reward diverifikasi **di klien** lalu diklaim ke server melalui RPC
`claim_ad_reward` yang sudah punya pertahanan:

- batas harian (5 reward/hari),
- rate limit (`check_rate_limit`),
- terikat `device_id` (pool kuota per perangkat),
- `ref_id` unik untuk idempotensi.

Artinya eksploit maksimum hanya 5 kuota/hari — sama dengan menonton 5 iklan.

Untuk pertahanan penuh, aktifkan SSV:

1. Deploy Edge Function `admob-ssv` (`verify_jwt = false`).
2. Verifikasi signature ECDSA memakai
   <https://www.gstatic.com/admob/reward/verifier-keys.json>
   (`kid` pada query string → public key).
3. Cek `transaction_id` belum pernah dipakai (tabel
   `ad_ssv_transactions`, unique), lalu panggil RPC `grant_ad_reward`
   sebagai `service_role`.
4. Daftarkan URL function ke AdMob → Ad unit → *Server-side verification URL*.
5. Setelah aktif, klien **tidak lagi** memanggil `claim_ad_reward`
   (server yang menambah kuota).

`AdService.showRewarded()` sudah mengirim `userId` + `customData`
(`quota_reward`) sehingga siap dipakai SSV tanpa perubahan klien.

---

## 6. Kepatuhan kebijakan Google Play

| Aturan | Status implementasi |
| :--- | :--- |
| Iklan tidak boleh menutupi tombol/aksi utama | Banner di atas bottom bar, bukan overlay |
| Interstitial tidak muncul saat app dibuka/ditutup | Hanya setelah aksi hapus |
| Tidak ada iklan "palsu"/menyesatkan | Unit asli AdMob, bukan simulasi |
| Tidak memaksa klik | Tidak ada skema insentif klik |
| Reward hanya setelah iklan selesai | Callback `onUserEarnedReward` |
| Data safety Play Console | Deklarasikan "Advertising/Device ID" saat submit |
| Family policy | `tagForChildDirectedTreatment: unspecified`, rating maksimum G |

---

## 7. Batasan teknis yang perlu diketahui

- **Versi plugin terkunci**: Flutter 3.24 hanya kompatibel dengan
  `google_mobile_ads` **5.3.1**, yang membawa **Google Mobile Ads SDK 23.6.0**.
  Status SDK tersebut: **deprecated sejak 17 Feb 2026**, **sunset 30 Juni 2027**.
  Setelah tanggal itu iklan berisiko `no fill` otomatis.
  → Rencanakan upgrade Flutter (≥ 3.27) + `google_mobile_ads` ≥ 6.x sebelum
  pertengahan 2027.
- **Emulator tanpa Play Services** tidak akan menampilkan iklan; uji di
  perangkat fisik.
- **Jangan klik iklan sendiri** saat memakai unit produksi — risiko suspend
  akun AdMob. Selalu uji dengan test ads.
- **eCPM Indonesia** untuk rewarded berkisar USD 1–3; banner lebih rendah.
  Pendapatan nyata baru terasa setelah volume harian ribuan tayangan.

---

## 8. Troubleshooting

| Gejala | Penyebab umum | Solusi |
| :--- | :--- | :--- |
| "Iklan belum tersedia" terus | Belum ada fill / unit baru | Tunggu beberapa jam, uji dengan test ads |
| Banner tidak muncul | PRO aktif, no fill, atau GMS tidak ada | Cek `isProUser()`, uji perangkat fisik |
| App crash saat start | `APPLICATION_ID` tidak ada di manifest | Pastikan `manifestPlaceholders` terpasang |
| Reward tidak menambah kuota | `claim_ad_reward` menolak (batas harian/rate limit/offline) | Cek pesan `QuotaService.lastError` |
| Interstitial tidak muncul | Belum 3 aksi / < 120 detik / no fill | Sesuai desain (anti-spam) |
