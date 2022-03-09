// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

interface GFarmInterface{
	function NFT_CREDITS_amount(address a) external view returns(uint);
	function spendCredits(address a, uint requiredCredits) external;
}