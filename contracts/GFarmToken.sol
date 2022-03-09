// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/access/AccessControlTimeLock.sol";

contract GFarmToken is ERC20Capped, AccessControlTimeLock {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    constructor(address _GOV, address _farm, address _trading)
    ERC20Capped(100000*10**18)
    ERC20("Gains V2", "GFARM2"){
        _setupRole(DEFAULT_ADMIN_ROLE, _GOV);
        _mint(_GOV, 1e16); // Create pair on Uniswap with 0.01 gfarm
        
        _setupRole(MINTER_ROLE, _farm);
        _setupRole(BURNER_ROLE, _farm);

        _setupRole(MINTER_ROLE, _trading);
        _setupRole(BURNER_ROLE, _trading);
    }

    // 1. Mint GFARM tokens (GFarm & GFarmTrading contracts)
    function mint(address to, uint amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(to, amount);
    }

    // 2. Burn GFARM tokens (GFarm & GFarmTrading contracts)
    function burn(address from, uint amount) external {
        require(hasRole(BURNER_ROLE, msg.sender), "Caller is not a burner");
        _burn(from, amount);
    }
}
