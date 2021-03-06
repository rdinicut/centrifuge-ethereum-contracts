pragma solidity 0.5.3;
pragma experimental ABIEncoderV2;

import "zos-lib/contracts/Initializable.sol";
import "contracts/lib/MerkleProof.sol";
import "contracts/erc721/UserMintableERC721.sol";
import "contracts/Identity.sol";


contract PaymentObligation is Initializable, UserMintableERC721 {

  event PaymentObligationMinted(
    address to,
    uint256 tokenId,
    string tokenURI
  );

  struct PODetails {
    bytes grossAmount;
    bytes currency;
    bytes dueDate;
  }

  /** @dev Indexes of the mint method arrays
  */
  uint8 constant internal GROSS_AMOUNT_IDX = 0;
  uint8 constant internal CURRENCY_IDX = 1;
  uint8 constant internal DUE_DATE_IDX = 2;
  uint8 constant internal SENDER_IDX = 3;
  uint8 constant internal STATUS_IDX = 4;
  uint8 constant internal NEXT_VERSION_IDX = 5;
  uint8 constant internal NFT_UNIQUE_IDX = 6;
  uint8 constant internal READ_ROLE_IDX = 7;
  uint8 constant internal READ_ROLE_ACTION_IDX = 8;
  uint8 constant internal TOKEN_ROLE_IDX = 9;

  // Token details, specific field values
  mapping(uint256 => PODetails) internal _poDetails;

  /**
  * @dev Returns the values associated with a token
  * @param grossAmount bytes The gross amount of the invoice
  * @param currency bytes The currency used in the invoice
  * @param dueDate bytes The Due data of the invoice
  * @param anchorId uint256 The ID of the document as identified
  * by the set up anchorRegistry
  * @param documentRoot bytes32 The root hash of the merkle proof/doc
  */
  function getTokenDetails(uint256 tokenId)
  external
  view
  returns (
    bytes memory grossAmount,
    bytes memory currency,
    bytes memory dueDate,
    uint256 anchorId,
    bytes32 documentRoot
  )
  {
    return (
      _poDetails[tokenId].grossAmount,
      _poDetails[tokenId].currency,
      _poDetails[tokenId].dueDate,
      _tokenDetails[tokenId].anchorId,
      _tokenDetails[tokenId].rootHash
    );
  }


  /**
   * @param anchorRegistry address The address of the anchor registry
   * @param identityFactory address The address of the identity factory
   * that is backing this token's mint method.
   * that ensures that the sender is authorized to mint the token
   */
  function initialize(
    address anchorRegistry,
    address identityFactory
  )
  public
  initializer
  {
    //@dev Order is important. Any change will impact the mint method
    // compact property for "invoice.gross_amount",invoice = 1, gross_amount = 14
    _mandatoryFields.push(hex"000100000000000e");
    // compact property for invoice.currency, invoice = 1, currency = 13
    _mandatoryFields.push(hex"000100000000000d");
    // compact property for  invoice.due_date, invoice = 1, due_date = 22
    _mandatoryFields.push(hex"0001000000000016");

    UserMintableERC721.initialize(
      "Centrifuge Payment Obligations",
      "CENT_PAY_OB",
      anchorRegistry,
      identityFactory
    );
  }

  /**
   * @dev Mints a token after validating the given merkle proofs
   * and comparing it to the anchor registry's stored hash/doc ID.
   * @param to address The recipient of the minted token
   * @param tokenId uint256 The ID for the minted token
   * @param tokenURI string The metadata uri
   * @param anchorId uint256 The ID of the document as identified
   * by the set up anchorRegistry.
   * @param properties bytes[] The properties of the leafs that are being proved
   * using precise-proofs
   * @param values bytes[] The values of the leafs that are being proved
   * using precise-proofs
   * @param salts bytes32[] The salts for the field that is being proved
   * Will be concatenated for proof verification as outlined in
   * precise-proofs library.
   * @param proofs bytes32[][] Documents proofs that are needed
   * for proof verification as outlined in precise-proofs library.
   */
  function mint(
    address to,
    uint256 tokenId,
    string memory tokenURI,
    uint256 anchorId,
    bytes[] memory properties,
    bytes[] memory values,
    bytes32[] memory salts,
    bytes32[][] memory proofs
  )
  public
  {
    // First check if the tokenId exists
    require(
      !_exists(tokenId),
      "Token exists"
    );

    // Get the document root from AnchorRepository
    bytes32 merkleRoot_ = super._getDocumentRoot(
      anchorId
    );


    // Check if status of invoice is unpaid
    require(
      MerkleProof.verifySha256(
        proofs[STATUS_IDX],
        merkleRoot_,
        sha256(
          abi.encodePacked(
            hex"0001000000000002", // compact property for  invoice.status, invoice = 1, status = 2
            hex"756e70616964", // bytes value for "unpaid"
            salts[STATUS_IDX]
          )
        )
      ),
      "Invoice status is not unpaid"
    );

    // Check if sender is a registered identity
    super._requireValidIdentity(
      merkleRoot_,
      hex"0001000000000013", // compact property for  invoice.sender, invoice = 1, sender = 19
      values[SENDER_IDX],
      salts[SENDER_IDX],
      proofs[SENDER_IDX]
    );

    // Enforce that there is not a newer version of the document on chain
    super._requireIsLatestDocumentVersion(
      merkleRoot_,
      bytesToUint(values[NEXT_VERSION_IDX]),
      salts[NEXT_VERSION_IDX],
      proofs[NEXT_VERSION_IDX]
    );

    // Verify that only one token per document/registry is minted
    super._requireOneTokenPerDocument(
      merkleRoot_,
      tokenId,
      salts[NFT_UNIQUE_IDX],
      proofs[NFT_UNIQUE_IDX]
    );

    // Check if document has a read rule defined
    bytes8 readRoleIndex = super._requireReadRole(
      merkleRoot_,
      properties[READ_ROLE_IDX],
      values[READ_ROLE_IDX],
      salts[READ_ROLE_IDX],
      proofs[READ_ROLE_IDX]
    );

    // Check if the read rule has a read action
    super._requireReadAction(
      merkleRoot_,
      readRoleIndex,
      salts[READ_ROLE_ACTION_IDX],
      proofs[READ_ROLE_ACTION_IDX]
    );

    // Check if the token has the read role assigned to it
    super._requireTokenHasRole(
      merkleRoot_,
      tokenId,
      properties[TOKEN_ROLE_IDX],
      values[READ_ROLE_IDX], // the value from read role proof
      salts[TOKEN_ROLE_IDX],
      proofs[TOKEN_ROLE_IDX]
    );

    super._mintAnchor(
      to,
      tokenId,
      anchorId,
      merkleRoot_,
      tokenURI,
      values,
      salts,
      proofs
    );

    _poDetails[tokenId] = PODetails(
      values[GROSS_AMOUNT_IDX],
      values[CURRENCY_IDX],
      values[DUE_DATE_IDX]
    );

    emit PaymentObligationMinted(
      to,
      tokenId,
      tokenURI
    );
  }

}

