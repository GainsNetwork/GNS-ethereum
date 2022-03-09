// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

pragma solidity 0.7.5;

interface GFarmNftInterface{
    function idToLeverage(uint id) external view returns(uint8);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface GFarmBridgeableNftInterface{
    function ownerOf(uint256 tokenId) external view returns (address);
	function mint(address to, uint tokenId) external;
	function burn(uint tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;

}

contract GFarmNftSwap{

	GFarmNftInterface public nft;
	GFarmBridgeableNftInterface[5] public bridgeableNfts;
	address public gov;

	event NftToBridgeableNft(uint nftType, uint tokenId);
	event BridgeableNftToNft(uint nftType, uint tokenId);

	constructor(GFarmNftInterface _nft){
		nft = _nft;
		gov = msg.sender;
	}

	function setBridgeableNfts(GFarmBridgeableNftInterface[5] calldata _bridgeableNfts) external{
		require(msg.sender == gov, "ONLY_GOV");
		require(bridgeableNfts[0] == GFarmBridgeableNftInterface(0), "BRIDGEABLE_NFTS_ALREADY_SET");
		bridgeableNfts = _bridgeableNfts;
	}

	function leverageToType(uint leverage) pure private returns(uint){
		// 150 => 5
		if(leverage == 150){ return 5; }
		
		// 25 => 1, 50 => 2, 75 => 3, 100 => 4
		return leverage / 25;
	}

	// Important: nft types = 1,2,3,4,5 (25x, 50x, 75x, 100x, 150x)
	modifier correctNftType(uint nftType){
		require(nftType > 0 && nftType < 6, "NFT_TYPE_BETWEEN_1_AND_5");
		_;
	}

	// Swap non-bridgeable nft for bridgeable nft
	function getBridgeableNft(uint nftType, uint tokenId) public correctNftType(nftType){
		// 1. token id corresponds to type provided
		require(leverageToType(nft.idToLeverage(tokenId)) == nftType, "WRONG_TYPE");

		// 2. transfer nft to this contract
		nft.transferFrom(msg.sender, address(this), tokenId);

		// 3. mint bridgeable nft of same type
		bridgeableNfts[nftType-1].mint(msg.sender, tokenId);

		emit NftToBridgeableNft(nftType, tokenId);
	}

	// Swap non-bridgeable nfts for bridgeable nfts
	function getBridgeableNfts(uint nftType, uint[] calldata ids) external correctNftType(nftType){
		// 1. max 10 at the same time
		require(ids.length <= 10, "MAX_10");

		// 2. loop over ids
		for(uint i = 0; i < ids.length; i++){
			getBridgeableNft(nftType, ids[i]);
		}
	}

	// Swap bridgeable nft for unbridgeable nft
	function getNft(uint nftType, uint tokenId) public correctNftType(nftType){
		// 1. Verify he owns the NFT
		require(bridgeableNfts[nftType-1].ownerOf(tokenId) == msg.sender, "NOT_OWNER");

		// 2. Burn bridgeable nft
		bridgeableNfts[nftType-1].burn(tokenId);

		// 3. transfer nft to msg.sender
		nft.transferFrom(address(this), msg.sender, tokenId);

		emit BridgeableNftToNft(nftType, tokenId);
	}

	// Swap bridgeable nft for unbridgeable nfts
	function getNfts(uint nftType, uint[] calldata ids) external correctNftType(nftType){
		// 1. max 10 at the same time
		require(ids.length <= 10, "MAX_10");

		// 2. loop over ids
		for(uint i = 0; i < ids.length; i++){
			getNft(nftType, ids[i]);
		}
	}

}