# QR Check (QRIS Detector & Cleaner)

Aplikasi Flutter untuk mendeteksi, membaca isi data, dan membersihkan galeri dari foto QRIS transaksi secara otomatis dengan alokasi kuota aman berbasis Supabase.

---

## 🌿 Git Branching Strategy

Proyek ini menerapkan pemisahan branch untuk menjaga stabilitas rilis:

| Branch | Lingkungan / Tujuan | Deskripsi |
| :--- | :--- | :--- |
| **`main`** | **Production** | Branch stabil rilis production. Hanya menerima merge dari `develop` saat rilis atau `hotfix/*` saat ada bug kritis. |
| **`develop`** | **Development** | Branch integrasi pengembangan aktif sehari-hari. Semua fitur baru dan perbaikan digabungkan ke sini terlebih dahulu. |
| **`feature/*`** | Fitur Baru | Dicabangkan dari `develop`, dibuat untuk pengerjaan fitur spesifik, dan di-merge kembali ke `develop`. |
| **`hotfix/*`** | Perbaikan Kritis | Dicabangkan dari `main` saat ada isu mendesak di production, lalu di-merge ke `main` dan `develop`. |

### Alur Pengembangan Harian:
1. Pastikan selalu berada di branch `develop` sebelum membuat fitur baru:
   ```bash
   git checkout develop
   git pull origin develop
   ```
2. Buat branch fitur baru:
   ```bash
   git checkout -b feature/nama-fitur
   ```
3. Setelah selesai, commit dan merge/PR ke `develop`:
   ```bash
   git push origin feature/nama-fitur
   ```

---

## 🛠️ Stack & Backend

- **Frontend**: Flutter (Mobile Android & iOS)
- **Backend & Database**: Supabase (PostgreSQL, Row Level Security, Storage Bucket, RPC Functions)
- **State & Local Storage**: SharedPreferences (Offline Fallback & Fast Cache)

---

## 🚀 Getting Started

1. Pastikan Flutter SDK sudah terpasang:
   ```bash
   flutter doctor
   ```
2. Ambil dependensi proyek:
   ```bash
   flutter pub get
   ```
3. Jalankan pengujian:
   ```bash
   flutter test
   ```
4. Jalankan aplikasi:
   ```bash
   flutter run
   ```

---

## 💳 Monetisasi (Google Play Billing)

Fitur PRO lifetime dijual sebagai **one-time product** `pro_lifetime` melalui Google Play
Billing Library 8.3.0 (native bridge, tanpa plugin `in_app_purchase`).

- Hak PRO **hanya** diberikan server-side: `verify-play-purchase` (Play Developer API +
  acknowledge) → RPC `grant_pro_from_play`. Client tidak pernah menulis `is_pro`.
- Refund/chargeback dicabut otomatis lewat RTDN (`play-rtdn` + Pub/Sub).
- QRIS manual tetap ada, tetapi hanya dipakai di luar Android (iOS/Web/APK non-Play),
  karena Play mewajibkan Play Billing untuk barang digital.

Panduan lengkap (Play Console, service account, Pub/Sub, signing, testing):
**`docs/google-play-billing.md`**

Deploy backend sekali jalan:

```bash
SUPABASE_PROJECT_REF=<ref> \
RTDN_AUDIENCE="https://<ref>.supabase.co/functions/v1/play-rtdn" \
RTDN_SERVICE_ACCOUNT_EMAIL="play-rtdn-push@<gcp>.iam.gserviceaccount.com" \
./scripts/deploy-play-billing.sh
```
