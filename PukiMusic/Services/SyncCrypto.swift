import Foundation
import CryptoKit

struct SyncDerivedKeys {
    let encKey: SymmetricKey
    let authKey: SymmetricKey
    let authVerifierHex: String
}

enum SyncCryptoError: Error {
    case invalidKeyLength
    case decryptionFailed
    case hexDecodingFailed
}

final class SyncCrypto {
    private static let kEncSalt = "puki_encryption_v1".data(using: .utf8)!
    private static let kAuthSalt = "puki_auth_v1".data(using: .utf8)!

    static func generateSyncSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func deriveKeys(syncSecretHex: String) throws -> SyncDerivedKeys {
        guard let secretData = dataFromHex(syncSecretHex), secretData.count == 32 else {
            throw SyncCryptoError.invalidKeyLength
        }

        let masterKey = SymmetricKey(data: secretData)
        let kEncMac = HMAC<SHA256>.authenticationCode(for: kEncSalt, using: masterKey)
        let kAuthMac = HMAC<SHA256>.authenticationCode(for: kAuthSalt, using: masterKey)

        let encKey = SymmetricKey(data: Data(kEncMac))
        let authKey = SymmetricKey(data: Data(kAuthMac))

        let authVerifierHex = Data(kAuthMac).map { String(format: "%02x", $0) }.joined()

        return SyncDerivedKeys(encKey: encKey, authKey: authKey, authVerifierHex: authVerifierHex)
    }

    static func encrypt(plaintext: String, key: SymmetricKey) throws -> String {
        let plaintextData = Data(plaintext.utf8)
        let sealedBox = try AES.GCM.seal(plaintextData, using: key)
        guard let combined = sealedBox.combined else {
            throw SyncCryptoError.decryptionFailed
        }
        return combined.base64EncodedString()
    }

    static func decrypt(ciphertextBase64: String, key: SymmetricKey) throws -> String {
        guard let combinedData = Data(base64Encoded: ciphertextBase64) else {
            throw SyncCryptoError.decryptionFailed
        }
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        guard let str = String(data: decryptedData, encoding: .utf8) else {
            throw SyncCryptoError.decryptionFailed
        }
        return str
    }

    static func signRequest(authKey: SymmetricKey, vaultId: String, timestamp: Int64, body: String) -> String {
        let signInput = "\(vaultId):\(timestamp):\(body)"
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signInput.utf8), using: authKey)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        var data = Data()
        var temp = ""
        for char in hex {
            temp.append(char)
            if temp.count == 2 {
                if let byte = UInt8(temp, radix: 16) {
                    data.append(byte)
                } else {
                    return nil
                }
                temp = ""
            }
        }
        return data
    }
}
