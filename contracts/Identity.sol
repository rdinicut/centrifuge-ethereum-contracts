pragma solidity ^0.4.24;

import "zos-lib/contracts/Initializable.sol";
import "contracts/KeyManager.sol";
import "openzeppelin-eth/contracts/cryptography/ECDSA.sol";
import "openzeppelin-eth/contracts/ownership/Ownable.sol";


contract Identity is Ownable, KeyManager {
  using ECDSA for bytes32;

  constructor() public{
    Ownable.initialize(msg.sender);
  }

  // @param _toSign Hash to be signed. Must be generated with abi.encodePacked(arg1, arg2, arg3)
  // @param _signature Signed data
  function isSignatureValid(
    bytes32 _toSign,
    bytes _signature
  )
  public
  view
  returns (bool valid)
  {
    bytes32 pbKey = bytes32(
      _toSign.toEthSignedMessageHash().recover(_signature)
    ) << 96; // Shift zeros to the end

    if (!keyHasPurpose(pbKey, ETH_MESSAGE_AUTH) || keys[pbKey].revokedAt > 0) {
      return false;
    }
    return true;
  }
}
