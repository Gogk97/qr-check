/**
 * ============================================================================
 * GOOGLE APPS SCRIPT - MULTI-SPREADSHEET BACKEND FOR QRIS DETECTOR
 * ============================================================================
 *
 * ⚠️ LEGACY / TIDAK DIPAKAI LAGI OLEH APLIKASI.
 *    Backend aplikasi sekarang Supabase. Skrip ini hanya referensi.
 *    Kalau deployment lama masih hidup, MATIKAN (Deploy > Manage deployments
 *    > Archive) karena endpoint-nya bisa ditulis siapa pun yang tahu URL.
 *
 * Spreadsheet ID TIDAK lagi ditulis di file ini. Isi lewat
 * File > Project Settings > Script Properties:
 *    SHEET_TRANSAKSI    = <id spreadsheet transaksi>
 *    SHEET_USER_GOOGLE  = <id spreadsheet user google>
 *    SHEET_USER_GUEST   = <id spreadsheet user guest>
 *    SYNC_TOKEN         = <string acak panjang, dipakai klien sebagai "token">
 *
 * ----------------------------------------------------------------------------
 * ATURAN KEAMANAN & INTEGRITAS DATA (STRICT POLICY):
 * 1. HANYA MENAMBAH (append) dan MEMPERBARUI (update) data.
 * 2. DILARANG KERAS MENGHAPUS DATA (Zero-Deletion Guarantee).
 * 3. Semua request doPost WAJIB menyertakan "token" yang cocok dengan
 *    Script Property SYNC_TOKEN (tanpa itu → 401).
 * 4. Foto bukti pembayaran diupload ke Google Drive folder milik Anda.
 * ============================================================================
 */

// Konfigurasi dibaca dari Script Properties (jangan hardcode di source).
var _props = PropertiesService.getScriptProperties();

var CONFIG = {
  SPREADSHEETS: {
    TRANSAKSI: _props.getProperty('SHEET_TRANSAKSI') || '',
    USER_GOOGLE: _props.getProperty('SHEET_USER_GOOGLE') || '',
    USER_GUEST: _props.getProperty('SHEET_USER_GUEST') || ''
  },
  SYNC_TOKEN: _props.getProperty('SYNC_TOKEN') || '',
  DRIVE_FOLDER_NAME: 'Bukti Pembayaran QRIS Detector'
};

function doPost(e) {
  var lock = LockService.getScriptLock();
  // Cegah race condition antar user (tunggu hingga 30 detik)
  lock.tryLock(30000);

  try {
    if (!e || !e.postData || !e.postData.contents) {
      return jsonResponse({
        status: 'error',
        message: 'Payload kosong / tidak ada data yang diterima.'
      });
    }

    var data = JSON.parse(e.postData.contents);

    // Autentikasi wajib: token harus sama dengan Script Property SYNC_TOKEN.
    if (!CONFIG.SYNC_TOKEN || data.token !== CONFIG.SYNC_TOKEN) {
      return jsonResponse({
        status: 'error',
        message: 'Unauthorized'
      });
    }

    var action = data.action || 'RECORD_PAYMENT';

    // ─────────────────────────────────────────────────────────────
    // 1. ACTION: SINKRONISASI USER (GOOGLE ATAU GUEST)
    // ─────────────────────────────────────────────────────────────
    if (action === 'SYNC_USER') {
      var isGoogle = (data.userType === 'GOOGLE');
      var targetSheetId = isGoogle ? CONFIG.SPREADSHEETS.USER_GOOGLE : CONFIG.SPREADSHEETS.USER_GUEST;
      var sheet = getSheetById(targetSheetId);

      if (isGoogle) {
        initGoogleUserHeaders(sheet);
        upsertGoogleUser(sheet, data);
      } else {
        initGuestUserHeaders(sheet);
        upsertGuestUser(sheet, data);
      }

      return jsonResponse({
        status: 'success',
        message: 'Data user berhasil disinkronisasi ke Google Sheet (' + (isGoogle ? 'Google' : 'Guest') + ').',
        userId: data.userId
      });
    }

    // ─────────────────────────────────────────────────────────────
    // 2. ACTION: UPDATE KUOTA PENGGUNA
    // ─────────────────────────────────────────────────────────────
    if (action === 'UPDATE_QUOTA') {
      var isGoogleUser = (data.userType === 'GOOGLE');
      var sheetId = isGoogleUser ? CONFIG.SPREADSHEETS.USER_GOOGLE : CONFIG.SPREADSHEETS.USER_GUEST;
      var targetSheet = getSheetById(sheetId);

      updateUserQuota(targetSheet, data.userId, data.remainingQuota);

      return jsonResponse({
        status: 'success',
        message: 'Kuota user ' + data.userId + ' berhasil diperbarui ke ' + data.remainingQuota
      });
    }

    // ─────────────────────────────────────────────────────────────
    // 3. ACTION: CATAT TRANSAKSI PEMBAYARAN & UPLOAD BUKTI KE DRIVE
    // ─────────────────────────────────────────────────────────────
    var txSheet = getSheetById(CONFIG.SPREADSHEETS.TRANSAKSI);
    initTransactionHeaders(txSheet);

    var proofDriveUrl = '-';

    // Upload bukti transfer base64 ke Google Drive jika ada
    if (data.imageBase64 && data.imageBase64.length > 50) {
      var folders = DriveApp.getFoldersByName(CONFIG.DRIVE_FOLDER_NAME);
      var folder = folders.hasNext() ? folders.next() : DriveApp.createFolder(CONFIG.DRIVE_FOLDER_NAME);

      var decodedBytes = Utilities.base64Decode(data.imageBase64);
      var fileName = (data.orderId || ('ORD-' + Date.now())) + '_' + (data.senderBank || 'transfer') + '.jpg';
      var blob = Utilities.newBlob(decodedBytes, data.mimeType || 'image/jpeg', fileName);
      var file = folder.createFile(blob);

      // Atur hak akses agar link Drive dapat langsung dibuka oleh pemilik sheet
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      proofDriveUrl = file.getUrl();
    }

    // Tambah baris transaksi baru (HANYA APPEND / NO DELETION)
    txSheet.appendRow([
      new Date(),
      data.orderId || ('ORD-' + Date.now()),
      data.userId || '-',
      data.userName || '-',
      data.userEmail || '-',
      data.senderBank || '-',
      data.amount || 15000,
      data.status || 'PENDING',
      proofDriveUrl,
      data.notes || '-'
    ]);

    return jsonResponse({
      status: 'success',
      message: 'Transaksi berhasil dicatat ke Data Transaksi & Bukti tersimpan di Google Drive!',
      orderId: data.orderId,
      proofUrl: proofDriveUrl
    });

  } catch (err) {
    return jsonResponse({
      status: 'error',
      message: 'Gagal memproses ke Google Sheets / Drive: ' + err.toString()
    });

  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  return jsonResponse({
    status: 'online',
    service: 'QRIS Detector Multi-Sheet Google Cloud Sync',
    timestamp: new Date().toISOString()
  });
}

// ─────────────────────────────────────────────────────────────────
// HELPER FUNCTIONS & SHEET MANAGERS (STRICT NO-DELETE IMPLEMENTATION)
// ─────────────────────────────────────────────────────────────────

function getSheetById(spreadsheetId) {
  try {
    var ss = SpreadsheetApp.openById(spreadsheetId);
    return ss.getActiveSheet();
  } catch (e) {
    // Fallback jika dijalankan langsung di container spreadsheet aktif
    return SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  }
}

function initTransactionHeaders(sheet) {
  if (sheet.getLastRow() === 0) {
    var headers = [
      'Waktu Submit',
      'Order ID',
      'User ID',
      'Nama User',
      'Email User',
      'Bank / E-Wallet Pengirim',
      'Nominal (IDR)',
      'Status Pembayaran',
      'Link Foto Bukti (Google Drive)',
      'Catatan'
    ];
    sheet.appendRow(headers);
    styleHeaderRange(sheet, headers.length, '#0F172A');
  }
}

function initGoogleUserHeaders(sheet) {
  if (sheet.getLastRow() === 0) {
    var headers = [
      'Waktu Pertama Login',
      'User ID',
      'Nama Akun Google',
      'Email Google',
      'Foto Profil URL',
      'Sisa Kuota Hapus',
      'Status PRO',
      'Perangkat / OS',
      'Terakhir Aktif'
    ];
    sheet.appendRow(headers);
    styleHeaderRange(sheet, headers.length, '#1E3A8A');
  }
}

function initGuestUserHeaders(sheet) {
  if (sheet.getLastRow() === 0) {
    var headers = [
      'Waktu Pertama Login',
      'Guest ID',
      'Nama Tamu',
      'Tipe Akun',
      'Sisa Kuota Hapus',
      'Status PRO',
      'Perangkat / OS',
      'Terakhir Aktif'
    ];
    sheet.appendRow(headers);
    styleHeaderRange(sheet, headers.length, '#065F46');
  }
}

function styleHeaderRange(sheet, colCount, hexColor) {
  var range = sheet.getRange(1, 1, 1, colCount);
  range.setBackground(hexColor);
  range.setFontColor('#FFFFFF');
  range.setFontWeight('bold');
  range.setHorizontalAlignment('center');
  sheet.setFrozenRows(1);
}

// UPDATE OR INSERT (UPSERT) USER GOOGLE (NO DELETION)
function upsertGoogleUser(sheet, data) {
  var lastRow = sheet.getLastRow();
  var userId = data.userId;
  var rowIndex = -1;

  if (lastRow > 1) {
    var userIds = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < userIds.length; i++) {
      if (userIds[i][0] == userId) {
        rowIndex = i + 2; // offset header
        break;
      }
    }
  }

  if (rowIndex > 0) {
    // UPDATE baris eksisting (hanya mengubah kuota, pro status, terakhir aktif)
    sheet.getRange(rowIndex, 6).setValue(data.remainingQuota != null ? data.remainingQuota : 10);
    sheet.getRange(rowIndex, 7).setValue(data.isPro ? 'TRUE' : 'FALSE');
    sheet.getRange(rowIndex, 8).setValue(data.devicePlatform || '-');
    sheet.getRange(rowIndex, 9).setValue(new Date());
  } else {
    // APPEND baris baru
    sheet.appendRow([
      new Date(),
      userId,
      data.userName || '-',
      data.userEmail || '-',
      data.avatarUrl || '-',
      data.remainingQuota != null ? data.remainingQuota : 10,
      data.isPro ? 'TRUE' : 'FALSE',
      data.devicePlatform || '-',
      new Date()
    ]);
  }
}

// UPDATE OR INSERT (UPSERT) USER GUEST (NO DELETION)
function upsertGuestUser(sheet, data) {
  var lastRow = sheet.getLastRow();
  var guestId = data.userId;
  var rowIndex = -1;

  if (lastRow > 1) {
    var guestIds = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < guestIds.length; i++) {
      if (guestIds[i][0] == guestId) {
        rowIndex = i + 2;
        break;
      }
    }
  }

  if (rowIndex > 0) {
    // UPDATE baris eksisting
    sheet.getRange(rowIndex, 5).setValue(data.remainingQuota != null ? data.remainingQuota : 5);
    sheet.getRange(rowIndex, 6).setValue(data.isPro ? 'TRUE' : 'FALSE');
    sheet.getRange(rowIndex, 7).setValue(data.devicePlatform || '-');
    sheet.getRange(rowIndex, 8).setValue(new Date());
  } else {
    // APPEND baris baru
    sheet.appendRow([
      new Date(),
      guestId,
      data.userName || 'Tamu',
      'GUEST',
      data.remainingQuota != null ? data.remainingQuota : 5,
      data.isPro ? 'TRUE' : 'FALSE',
      data.devicePlatform || '-',
      new Date()
    ]);
  }
}

// UPDATE KUOTA USER TERPILIH (NO DELETION)
function updateUserQuota(sheet, userId, newQuota) {
  var lastRow = sheet.getLastRow();
  if (lastRow <= 1) return;

  var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  var quotaCol = -1;
  var lastActiveCol = -1;

  for (var c = 0; c < headers.length; c++) {
    var h = String(headers[c]).toLowerCase();
    if (h.indexOf('kuota') >= 0) quotaCol = c + 1;
    if (h.indexOf('aktif') >= 0) lastActiveCol = c + 1;
  }

  if (quotaCol === -1) quotaCol = 5;
  if (lastActiveCol === -1) lastActiveCol = headers.length;

  var ids = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
  for (var i = 0; i < ids.length; i++) {
    if (ids[i][0] == userId) {
      var row = i + 2;
      sheet.getRange(row, quotaCol).setValue(newQuota);
      sheet.getRange(row, lastActiveCol).setValue(new Date());
      break;
    }
  }
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
