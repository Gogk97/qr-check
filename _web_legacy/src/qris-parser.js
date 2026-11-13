/**
 * QRIS & EMVCo MPM (Merchant-Presented Mode) Parser
 * Standar Nasional QR Code Pembayaran Indonesia (Bank Indonesia / ASPI)
 */

class QRISParser {
  /**
   * Hitung CRC16-CCITT (0x1021, init 0xFFFF) sesuai spesifikasi EMVCo
   * @param {string} str - Teks payload tanpa 4 karakter CRC terakhir
   * @returns {string} - Hex 4 digit uppercase
   */
  static calculateCRC16(str) {
    let crc = 0xFFFF;
    for (let i = 0; i < str.length; i++) {
      let c = str.charCodeAt(i);
      crc ^= (c << 8);
      for (let j = 0; j < 8; j++) {
        if ((crc & 0x8000) !== 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toString(16).toUpperCase().padStart(4, '0');
  }

  /**
   * Parse TLV (Tag-Length-Value) string secara rekursif
   * @param {string} payload 
   * @returns {Object} map of tag -> { tag, length, value }
   */
  static parseTLV(payload) {
    const tags = {};
    let index = 0;

    while (index < payload.length - 3) {
      const tag = payload.substring(index, index + 2);
      const lenStr = payload.substring(index + 2, index + 4);
      const len = parseInt(lenStr, 10);

      if (isNaN(len)) break;

      const value = payload.substring(index + 4, index + 4 + len);
      tags[tag] = {
        tag,
        length: len,
        value
      };

      index += 4 + len;
    }

    return tags;
  }

  /**
   * Analisis teks QR untuk menentukan apakah ini QRIS resmi atau QR biasa
   * @param {string} rawText 
   * @returns {Object} Hasil analisis
   */
  static analyze(rawText) {
    if (!rawText || typeof rawText !== 'string') {
      return {
        isQR: false,
        isQRIS: false,
        type: 'invalid',
        raw: ''
      };
    }

    const trimmed = rawText.trim();

    // Cek format EMVCo dasar: dimulai dengan "000201"
    const isEMVCoStart = trimmed.startsWith('000201');
    const tags = this.parseTLV(trimmed);

    // QRIS Indonesia ciri khas:
    // 1. Tag 00 = "01" (Payload Format Indicator)
    // 2. Tag 58 = "ID" (Country Code)
    // 3. Tag 53 = "360" (Currency IDR) atau adanya Tag 26/51 dengan NMID/ID.CO.QRIS
    const country = tags['58']?.value;
    const currency = tags['53']?.value;
    const formatInd = tags['00']?.value;

    const hasQRISIdentifier = 
      trimmed.includes('ID.CO.QRIS') || 
      trimmed.includes('ID10') || 
      (country === 'ID' && (currency === '360' || tags['51'] || tags['26']));

    const isQRIS = isEMVCoStart && formatInd === '01' && (country === 'ID' || hasQRISIdentifier);

    if (isQRIS) {
      // Validasi CRC16
      const crcTag = tags['63'];
      let isValidCRC = false;
      if (crcTag && trimmed.length >= 8) {
        const payloadBeforeCRC = trimmed.substring(0, trimmed.length - 4);
        const expectedCRC = this.calculateCRC16(payloadBeforeCRC);
        isValidCRC = (expectedCRC === crcTag.value.toUpperCase());
      }

      // Ambil detail merchant
      const pointOfInitiation = tags['01']?.value; // 11: Static, 12: Dynamic
      const merchantName = tags['59']?.value || 'Merchant Tanpa Nama';
      const merchantCity = tags['60']?.value || '-';
      const postalCode = tags['61']?.value || '-';
      const mcc = tags['52']?.value || '-';
      const amount = tags['54']?.value ? parseFloat(tags['54'].value) : null;

      // Cari NMID / Merchant Account Info
      let nmid = '';
      let acquirer = '';
      if (tags['51']) {
        const sub = this.parseTLV(tags['51'].value);
        nmid = sub['02']?.value || tags['51'].value;
      }
      if (!nmid && tags['26']) {
        const sub = this.parseTLV(tags['26'].value);
        nmid = sub['01']?.value || sub['02']?.value || '';
        acquirer = sub['00']?.value || '';
      }

      return {
        isQR: true,
        isQRIS: true,
        type: 'qris',
        isDynamic: pointOfInitiation === '12',
        merchantName,
        merchantCity,
        postalCode,
        mcc,
        amount,
        nmid,
        acquirer,
        isValidCRC,
        tags,
        raw: trimmed
      };
    }

    // Jika bukan QRIS, identifikasi tipe QR biasa
    let qrType = 'text';
    if (/^https?:\/\//i.test(trimmed)) {
      qrType = 'url';
    } else if (/^WIFI:/i.test(trimmed)) {
      qrType = 'wifi';
    } else if (/^mailto:/i.test(trimmed)) {
      qrType = 'email';
    } else if (/^tel:/i.test(trimmed)) {
      qrType = 'tel';
    }

    return {
      isQR: true,
      isQRIS: false,
      type: qrType,
      raw: trimmed
    };
  }
}

// Export for browser / module
if (typeof window !== 'undefined') {
  window.QRISParser = QRISParser;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = QRISParser;
}
