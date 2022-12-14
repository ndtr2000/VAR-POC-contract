// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./token/NFT.sol";

/** 
* @title Store
* @author ndtr2000
* @dev This is smart contract for Shirt minting Store
*/

contract CollectionController is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    address public feeTo;
    address public verifier;
    uint256 public totalCollection;

    struct Collection{
        uint256 keyId;
        address artist;
        address collectionAddress;
        address paymentToken;
        uint256 mintCap;
        uint256 startTime;
        uint256 endTime;
    }

    // mapping index to collection
    mapping (uint256 => Collection) public collections; 
    
    // mapping of minted layer id hash
    mapping (bytes => bool) private layerHashes;

    // mapping owner address to own collections set
    mapping (address => EnumerableSetUpgradeable.UintSet) private artistToCollection;
    
    /* ========== EVENTS ========== */

    event FeeToAddressChanged(address oldAddress, address newAddress);
    event VerifierAddressChanged(address oldAddress, address newAddress);
    event CollectionCreated(uint256 keyId, uint256 collectionId, string name, string symbol, string baseUri, address artist, address collectionAddress, address paymentToken, uint256 mintCap);
    event MintCapUpdated(uint256 indexed collectionId, uint256 oldMintCap, uint256 newMintCap);
    event StartTimeUpdated(uint256 indexed collectionId, uint256 oldStartTime, uint256 newStartTime);
    event EndTimeUpdated(uint256 indexed collectionId, uint256 oldEndTime, uint256 newEndTime);
    event NFTMinted(uint256 indexed collectionId, address collectionAddress, address receivers, string uris, uint256 tokenId);

    /* ========== MODIFIERS ========== */

    /* ========== GOVERNANCE ========== */

    /**
     * @dev Initialize function
     * must call right after contract is deployed
     * @param _feeTo address to receive revenue
     * @param _verifier address to verify signature
     */
    function initialize(address _feeTo, address _verifier) public initializer{
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        feeTo = _feeTo;
        verifier = _verifier;
    }

    /**
    * @dev function to whitelist NFTs that set their whitelist status to true
    * @param name name of collection
    * @param symbol collection's symbol
    * @param baseUri collection's base metadata uri
    * @param paymentToken payment token address to mint NFT from this collection
    * 
    * Emits {CollectionCreated}
    *
    */
    function createCollection(
        uint256 keyId,
        string memory name, 
        string memory symbol, 
        string memory baseUri, 
        address paymentToken,
        uint256 mintCap,
        uint256 startTime,
        uint256 endTime
    ) external {
        require(startTime > block.timestamp || startTime == 0, "CollectionController: invalid start time");
        require(endTime > startTime || endTime == 0, "CollectionController: invalid end time");
        NFT newNFT = new NFT(name, symbol, baseUri);
        address collectionAddress = address(newNFT);
        Collection memory newCollection  = Collection(
            keyId, 
            _msgSender(), 
            collectionAddress, 
            paymentToken, 
            mintCap, 
            startTime,
            endTime
        );
        totalCollection ++;
        collections[totalCollection] = newCollection;
        artistToCollection[_msgSender()].add(totalCollection);

        emit CollectionCreated(keyId, totalCollection, name, symbol, baseUri, _msgSender(), collectionAddress, paymentToken, mintCap);
    }

    /**
     * @dev function to mint NFT from a collection
     * @param collectionId ID of collection to mint
     * @param uri uris of minted NFT
     * 
     * Emits {CollectionMinted} events indicating NFTs minted
     * 
     * Requirements:
     * 
     * - length of 'receivers' and 'uris' must be the same
     * - transfer enough minting cost
     */
    function mintNFT(uint256 collectionId, string calldata uri, uint256 fee, bytes memory layerHash, bytes memory signature) payable external nonReentrant {        
        require(!layerHashes[layerHash], "CollectionController: Layer combination already minted");
        Collection memory collection = collections[collectionId];
        require(collection.startTime <= block.timestamp || collection.startTime == 0, "CollectionController: collection not started yet");
        require(collection.endTime > block.timestamp || collection.endTime == 0, "CollectionController: collection ended");
        NFT nft = NFT(collection.collectionAddress);
        if(collection.paymentToken == address(0)){
            require(msg.value == fee, "CollectionController: wrong fee");
            (bool sent,) = feeTo.call{value: fee}("");
            require(sent, "CollectionController: Failed to send");
        } else {
            IERC20Upgradeable(collection.paymentToken).safeTransferFrom(_msgSender(), feeTo, fee);
        }
        uint256 tokenId = nft.totalSupply() + 1;
        require(tokenId <= collection.mintCap, "CollectionController: max total supply exeeds");
        require(verifyMessage(collectionId,_msgSender(), fee, tokenId, layerHash, signature), "CollectionController: invalid signature");
        layerHashes[layerHash] = true;
        nft.mint(_msgSender(), uri);
        emit NFTMinted(collectionId, collection.collectionAddress, _msgSender(), uri, tokenId);
    }

    /**
     * @dev Function to withdraw balance from this smart contract
     */
    function withDraw(address token) external onlyOwner nonReentrant {
        if(token == address(0)){
            (bool sent,) = msg.sender.call{value: address(this).balance}("");
            require(sent, "Failed to withdraw");
        } else {
            IERC20Upgradeable(token).safeTransfer(_msgSender(), IERC20Upgradeable(token).balanceOf(address(this)));
        }
    }
    /* ========== VIEW FUNCTIONS ========== */
    /**
     * @dev Returns all collectionID of an artist
     * @param artist artist address to view
     */
    function collectionsByArtist(address artist) public view returns(uint256[] memory) {
        return artistToCollection[artist].values();
    }

    /**
     * @dev Returns NFT detail by collectionId and TokenId
     */
    function getNFTInfo(uint256 collectionId, uint256 tokenId) public view returns(address, string memory){
        Collection memory collection = collections[collectionId];
        NFT nFT = NFT(collection.collectionAddress);
        string memory uri = nFT.tokenURI(tokenId);
        address tokenOwner = nFT.ownerOf(tokenId);
        return (tokenOwner, uri);
    }

    /**
     * @dev get next token will be minted by collection
     */
    function getNextTokenId(uint256 collectionId) public view returns(uint256){
        Collection memory collection = collections[collectionId];
        return NFT(collection.collectionAddress).totalSupply() + 1;
    }

    /**
     * @dev check if layer combination is minted
     */
    function isLayerMinted(bytes memory layerHash) public view returns(bool){
        return layerHashes[layerHash];
    }
    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev function to set mintCap to collection
     * @param collectionId id of collection to set
     * @param _mintCap new mint capability to set
     * 
     * Emits {MintCapUpdated} events indicating payment changed
     * 
     */
    function updateMintCap(uint256 collectionId, uint256 _mintCap) external {
        Collection memory collection = collections[collectionId];
        
        require(_msgSender() == collection.artist, "CollectionController: caller is not collection artist");
        require(_mintCap != collection.mintCap && _mintCap > NFT(collection.collectionAddress).totalSupply(), "CollectionController: invalid mint capability");
        
        emit MintCapUpdated(collectionId, collection.mintCap, _mintCap);

        collection.mintCap = _mintCap;
        collections[collectionId] = collection; 
    }

    /**
     * @dev function to set mintCap to collection
     * @param collectionId id of collection to set
     * @param _startTime new startTime to set
     * 
     * Emits {MintCapUpdated} events indicating payment changed
     * 
     */
    function updateStartTime(uint256 collectionId, uint256 _startTime) external {
        Collection memory collection = collections[collectionId];
        
        require(_msgSender() == collection.artist, "CollectionController: caller is not collection artist");
        require(collection.startTime > block.timestamp || collection.startTime == 0, "CollectionController: collection already started");
        require(_startTime > block.timestamp || _startTime == 0, "CollectionController: invalid start time");

        emit StartTimeUpdated(collectionId, collection.startTime, _startTime);

        collection.startTime = _startTime;
        collections[collectionId] = collection; 
    }

    /**
     * @dev function to set mintCap to collection
     * @param collectionId id of collection to set
     * @param _endTime new startTime to set
     * 
     * Emits {MintCapUpdated} events indicating payment changed
     * 
     */
    function updateEndTime(uint256 collectionId, uint256 _endTime) external {
        Collection memory collection = collections[collectionId];
        
        require(_msgSender() == collection.artist, "CollectionController: caller is not collection artist");
        require(collection.startTime > block.timestamp, "CollectionController: collection already started");
        require(_endTime > collection.startTime || _endTime == 0, "CollectionController: invalid end time");

        emit EndTimeUpdated(collectionId, collection.endTime, _endTime);

        collection.endTime = _endTime;
        collections[collectionId] = collection; 
    }

    /**
     * @dev function to set feeTo address
     * @param _feeTo new feeTo address
     */
    function setFeeTo(address _feeTo) external onlyOwner {
        address oldFeeTo = feeTo;
        require(_feeTo != address(0), "CollectionController: set to zero address");
        require(_feeTo != oldFeeTo, "CollectionController: feeTo address set");
        feeTo = _feeTo;
        emit FeeToAddressChanged(oldFeeTo, _feeTo);
    }

    /**
     * @dev function to set feeTo address
     * @param _verifier new feeTo address
     */
    function setVerifier(address _verifier) external onlyOwner {
        address oldVerifier = verifier;
        require(_verifier != address(0), "CollectionController: set to zero address");
        require(_verifier != oldVerifier, "CollectionController: feeTo address set");
        feeTo = _verifier;
        emit FeeToAddressChanged(oldVerifier, _verifier);
    }

    function verifyMessage(
        uint256 collectionID,
        address sender,
        uint256 fee,
        uint256 tokenId,
        bytes memory layerHash,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 dataHash = encodeData(
            collectionID,
            sender,
            fee,
            tokenId,
            layerHash
        );
        bytes32 signHash = ECDSA.toEthSignedMessageHash(dataHash);
        address recovered = ECDSA.recover(signHash, signature);
        return recovered == verifier;
    }

    function encodeData(
        uint256 collectionID,
        address sender,
        uint256 fee,
        uint256 tokenId,
        bytes memory layerHash
    ) public view returns (bytes32) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return
            keccak256(
                abi.encode(id, collectionID, sender, fee, tokenId, layerHash)
            );
    }


}