// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

interface GFarmNFTInterface{
    function balanceOf(address owner) external view returns (uint256 balance);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);
    function leverageID(uint8 _leverage) external pure returns(uint8);
    function idToLeverage(uint id) external view returns(uint8);
    function transferFrom(address from, address to, uint256 tokenId) external;
}