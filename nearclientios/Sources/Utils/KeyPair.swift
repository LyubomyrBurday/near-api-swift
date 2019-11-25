//
//  KeyPair.swift
//  nearclientios
//
//  Created by Dmitry Kurochka on 10/30/19.
//  Copyright © 2019 NEAR Protocol. All rights reserved.
//

import Foundation
import TweetNacl

internal protocol SignatureProtocol {
  var signature: [UInt8] {get}
  var publicKey: PublicKey {get}
}

internal struct Signature: SignatureProtocol {
  let signature: [UInt8]
  let publicKey: PublicKey
}

/** All supported key types */
internal enum KeyType: String, Codable, BorshCodable {
  case ED25519 = "ed25519"

  func serialize(to writer: inout Data) throws {
    switch self {
    case .ED25519: return try UInt8(0).serialize(to: &writer)
    }
  }

  init(from reader: inout BinaryReader) throws {
    let value = try UInt8(from: &reader)
    switch value {
    case 0: self = .ED25519
    default: throw BorshDecodingError.unknownData
    }
  }
}

internal enum PublicKeyDecodeError: Error {
  case invalidKeyFormat(String)
  case unknowKeyType
}

internal struct PublicKeyPayload: FixedLengthByteArray, BorshCodable {
  static let fixedLength: UInt32 = 32
  let bytes: [UInt8]
}

/**
 * PublicKey representation that has type and bytes of the key.
 */
internal struct PublicKey {
  private let keyType: KeyType
  internal let data: PublicKeyPayload

  init(keyType: KeyType, data: [UInt8]) {
    self.keyType = keyType
    self.data = PublicKeyPayload(bytes: data)
  }

  static func fromString(encodedKey: String) throws -> PublicKey {
    let parts = encodedKey.split(separator: ":").map {String($0)}
    if parts.count == 1 {
      return PublicKey(keyType: .ED25519, data: parts[0].baseDecoded)
    } else if parts.count == 2 {
      guard let keyType = KeyType(rawValue: parts[0]) else {throw PublicKeyDecodeError.unknowKeyType}
      return PublicKey(keyType: keyType, data: parts[1].baseDecoded)
    } else {
      throw PublicKeyDecodeError.invalidKeyFormat("Invlaid encoded key format, must be <curve>:<encoded key>")
    }
  }

  func toString() -> String {
    return "\(keyType):\(data.bytes.baseEncoded)"
  }
}

extension PublicKey: BorshCodable {
  func serialize(to writer: inout Data) throws {
    try keyType.serialize(to: &writer)
    try data.serialize(to: &writer)
  }

  init(from reader: inout BinaryReader) throws {
    self.keyType = try .init(from: &reader)
    self.data = try .init(from: &reader)
  }
}

internal enum KeyPairDecodeError: Error {
  case invalidKeyFormat(String)
  case unknowCurve(String)
}

internal protocol KeyPair {
  func sign(message: [UInt8]) throws -> SignatureProtocol
  func verify(message: [UInt8], signature: [UInt8]) throws -> Bool
  func toString() -> String
  func getPublicKey() -> PublicKey
}

func keyPairFromRandom(curve: KeyType) throws -> KeyPair{
  switch curve {
  case .ED25519: return try KeyPairEd25519.fromRandom()
  }
}

func keyPairFromString(encodedKey: String) throws -> KeyPair {
  let parts = encodedKey.split(separator: ":").map {String($0)}
  if parts.count == 1 {
    return try KeyPairEd25519(secretKey: parts[0])
  } else if parts.count == 2 {
    guard let curve = KeyType(rawValue: parts[0]) else {
      throw KeyPairDecodeError.unknowCurve("Unknown curve: \(parts[0])")
    }
    switch curve {
    case .ED25519: return try KeyPairEd25519(secretKey: parts[1])
    }
  } else {
    throw KeyPairDecodeError.invalidKeyFormat("Invalid encoded key format, must be <curve>:<encoded key>")
  }
}

/**
* This struct provides key pair functionality for Ed25519 curve:
* generating key pairs, encoding key pairs, signing and verifying.
*/
internal struct KeyPairEd25519 {
  private let publicKey: PublicKey
  private let secretKey: String

  /**
   * Construct an instance of key pair given a secret key.
   * It's generally assumed that these are encoded in base58.
   * - Parameter secretKey: SecretKey to be used for KeyPair
   */
  init(secretKey: String) throws {
    let keyPair = try NaclSign.KeyPair.keyPair(fromSecretKey: secretKey.baseDecoded.data)
    self.publicKey = PublicKey(keyType: .ED25519, data: keyPair.publicKey.bytes);
    self.secretKey = secretKey;
  }

  /**
   Generate a new random keypair.
   ```
   let keyRandom = KeyPair.fromRandom()
   keyRandom.publicKey
      - Returns: publicKey
   ```
   ```
   let keyRandom = KeyPair.fromRandom()
   keyRandom.secretKey
      - Returns: secretKey
   ```
   */
  static func fromRandom() throws -> Self {
    let newKeyPair = try NaclSign.KeyPair.keyPair()
    return try KeyPairEd25519(secretKey: newKeyPair.secretKey.baseEncoded)
  }
}

extension KeyPairEd25519: KeyPair {
  func sign(message: [UInt8]) throws -> SignatureProtocol {
    let signature = try NaclSign.signDetached(message: message.data, secretKey: secretKey.baseDecoded.data)
    return Signature(signature: signature.bytes, publicKey: publicKey)
  }

  func verify(message: [UInt8], signature: [UInt8]) throws -> Bool {
    return try NaclSign.signDetachedVerify(message: message.data, sig: signature.data, publicKey: publicKey.data.bytes.data)
  }

  func toString() -> String {
    return "ed25519:\(secretKey)"
  }

  func getPublicKey() -> PublicKey {
    return publicKey
  }
}
