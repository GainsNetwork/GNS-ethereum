// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "./GFarmInterface.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract GFarmNFT is ERC721{

	// VARIABLES & CONSTANTS

	// 1. Current supply for each leverage
	uint16[5] supply = [0, 0, 0, 0, 0];

	// 2. Get the corresponding leverage for each NFT minted
	mapping(uint => uint8) public idToLeverage;

	// 3. Farm contract to check NFT credits
	GFarmInterface public immutable farm;

	constructor(GFarmInterface _farm) ERC721("GFarmNFT V2", "GFARM2NFT"){
		farm = _farm;
	}

	// CONSTANT ARRAYS

	// 1. Required credits for each leverage (constant)
	function requiredCreditsArray() public pure returns(uint24[5] memory){
		// (blocks) => 1, 2, 5, 10, 20
		return [6400, 12800, 32000, 64000, 128000];
	}
	// 2. Max supply for each leverage (constant)
	function maxSupplyArray() public pure returns(uint16[5] memory){
		return [500, 400, 300, 200, 100];
	}

	// USEFUL HELPER FUNCTIONS

	// 1. Verify leverage value (25, 50, 75, 100, 150)
	modifier correctLeverage(uint8 _leverage){
		require(_leverage >= 25 
				&& _leverage <= 150 
				&& _leverage % 25 == 0 
				&& _leverage != 125,
				"Wrong leverage value");
		_;
	}

	// 2. Get ID from leverage (for arrays)
	function leverageID(uint8 _leverage) public pure correctLeverage(_leverage) returns(uint8){
		if(_leverage != 150){
			// 25: 0, 50: 1, 75: 2, 100: 3
			return (_leverage)/25-1;
		}
		// 150: 4
		return 4;
	}

	// 3. Get required credits from leverage based on the constant array
	function requiredCredits(uint8 _leverage) public pure returns(uint24){
		return requiredCreditsArray()[leverageID(_leverage)];
	}

	// 4. Get max supply from leverage based on the constant array
	function maxSupply(uint8 _leverage) public pure returns(uint16){
		return maxSupplyArray()[leverageID(_leverage)];
	}

	// 5. Get current supply from leverage
	function currentSupply(uint8 _leverage) public view returns(uint16){
		return supply[leverageID(_leverage)];
	}

	// ACTIONS

	// 1. Mint a leverage NFT to a user (only used internally)
	function mint(uint8 _leverage, uint _userCredits) private{
		require(_userCredits >= requiredCredits(_leverage), "Not enough NFT credits");
		require(currentSupply(_leverage) < maxSupply(_leverage), "Max supply reached for this leverage");

		uint nftID = totalSupply();
		_mint(msg.sender, nftID);

		idToLeverage[nftID] = _leverage;
		supply[leverageID(_leverage)] += 1;
	}

	// 2. Claim NFT (called externally)
	function claim(uint8 _leverage) external{
		require(tx.origin == msg.sender, "Contracts not allowed.");
		mint(_leverage, farm.NFT_CREDITS_amount(msg.sender));
		farm.spendCredits(msg.sender, requiredCredits(_leverage));
	}

    // EXTERNAL READ-ONLY FUNCTIONS

	// 1. Get full current supply array for each NFT
	function currentSupplyArray() external view returns(uint16[5] memory){
		return supply;
	}

	// 2. Amount of each NFTs owned by msg.sender
	function ownedCount() external view returns(uint[5] memory nfts){
    	for(uint i = 0; i < balanceOf(msg.sender); i++){
            uint id = leverageID(
                idToLeverage[(
                    tokenOfOwnerByIndex(msg.sender, i)
                )]
            );
            nfts[id] = nfts[id] + 1;
        }
    }
}