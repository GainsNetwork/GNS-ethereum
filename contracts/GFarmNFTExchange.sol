// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "./GFarmNFTInterface.sol";
import "./GFarmTokenInterface.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract GFarmNFTExchange {

    using SafeMath for uint;

    // 1. Tokens
    GFarmNFTInterface public immutable nft;
    GFarmTokenInterface public immutable token;
    IUniswapV2Pair public immutable lp;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IUniswapV2Pair constant ETH_USDC_PAIR = IUniswapV2Pair(0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc);

    // 2. Store all NFTs for sale
    struct Bidding{
        uint nftID;
        address payable seller;
        uint start; // block
        uint duration; // blocks
        uint minBid; // 1e18
        uint highestBid; // 1e18
        uint highestBidMinusFees; // 1e18
        address payable highestBidder;
        uint bidCount;
    }
    mapping(uint => Bidding[]) public biddingsByLeverage;
    mapping(uint => uint) public idToBiddingsByLeverageIndex; // nft id => index in biddingsByLeverage

    // 3. GFARM2 pool
    uint public accETHperGFARM; // 1e18
    struct User{
        uint provided; //1e18
        uint debt; //1e18
    }
    mapping(address => User) public users;

    // 4. Fees
    uint public BID_FEE_P = 5;
    uint public HIGHEST_BID_FEE_P = 25;
    address public GOV;

    // 5. Stats & Events
    uint public totalEthDistributed;

    event NewBidding(
        address indexed seller,
        uint nftID,
        uint leverage,
        uint duration,
        uint minBid
    );

    event NewBid(
        address indexed seller,
        address indexed bidder,
        uint nftID,
        uint leverage,
        uint amount
    );

    constructor(
        GFarmNFTInterface _nft,
        GFarmTokenInterface _token,
        IUniswapV2Pair _lp,
        address _gov){
        nft = _nft;
        token = _token;
        lp = _lp;
        GOV = _gov;
    }

    // UPDATE FEE PERCENTAGES - GOVERNANCE (EXCHANGE)

    modifier onlyGov(){
        require(msg.sender == GOV);
        _;
    }
    function set_GOV(address _gov) external onlyGov{
        GOV = _gov;
    }
    function set_BID_FEE_P(uint _fee) external onlyGov{
        BID_FEE_P = _fee;
    }
    function set_HIGHEST_BID_FEE_P(uint _fee) external onlyGov{
        HIGHEST_BID_FEE_P = _fee;
    }

    // PRIVATE FUNCTIONS (EXCHANGE)

    function removeBidding(uint _nftID) private{
        uint leverage = nft.idToLeverage(_nftID);
        Bidding[] storage leverageBiddings = biddingsByLeverage[leverage];

        // 1. Update index of the last bidding of the array to this nft's index in the array
        idToBiddingsByLeverageIndex[leverageBiddings[leverageBiddings.length - 1].nftID] = idToBiddingsByLeverageIndex[_nftID];

        // 2. Copy last bidding of the array to replace this nft ID's listings with the last one
        leverageBiddings[idToBiddingsByLeverageIndex[_nftID]] = leverageBiddings[leverageBiddings.length - 1];

        // 3. Remove the last element of the biddings array
        leverageBiddings.pop();

        // 4. Remove index from mapping for this NFT
        delete idToBiddingsByLeverageIndex[_nftID];

    }

    // EXTERNAL FUNCTIONS (EXCHANGE)

    // 0. Modifiers
    modifier notContract(){
        require(tx.origin == msg.sender, "Contracts not allowed.");
        _;
    }
    modifier listed(uint id){
        require(isListed(id), "This NFT isn't listed.");
        _;
    }

    // 1. Put an NFT for sale
    function sell(uint _nftID, uint _minBid, uint _bidDuration) external notContract{
        // 1. Bidding duration should be between 100 blocks and 100k blocks
        require(_bidDuration >= 100 && _bidDuration <= 100000, "Bidding duration should be between 100 and 100k blocks.");

        // 2. Transfer the NFT to this contract
        nft.transferFrom(msg.sender, address(this), _nftID);

        // 3. Store bidding
        uint leverage = nft.idToLeverage(_nftID);
        Bidding memory b = Bidding(_nftID, msg.sender, block.number, _bidDuration, _minBid, 0, 0, address(0), 0);

        biddingsByLeverage[leverage].push(b);
        idToBiddingsByLeverageIndex[_nftID] = biddingsByLeverage[leverage].length - 1;

        // 4. Emit event
        emit NewBidding(
            msg.sender,
            _nftID,
            leverage,
            _bidDuration,
            _minBid
        );
    }

    // 2. Place a bid for an NFT
    function bid(uint _nftID) external payable notContract listed(_nftID){
        uint leverage = nft.idToLeverage(_nftID);
        Bidding storage b = biddingsByLeverage[leverage][idToBiddingsByLeverageIndex[_nftID]];

        // 1. Verify msg.sender isn't the seller
        require(msg.sender != b.seller, "You can't bid for your own NFT.");

        // 2. Verify the bid hasn't ended
        require(block.number < b.start.add(b.duration), "Bidding has already ended.");

        // 3. Verify the bid is higher than the min bid
        require(msg.value >= b.minBid && msg.value > b.highestBid, "You must bid higher than the min bid and the highest bid.");

        // 4. If there was already a bid, send back the ETH to old bidder
        if(b.highestBidder != address(0) && b.highestBid != 0){
            b.highestBidder.transfer(b.highestBidMinusFees);
        }

        // 5. Set highest bidder & highest bid & add 1 to bid count
        // 5% in fees go to GFARM2 stakers in the pool
        uint fee = msg.value.mul(BID_FEE_P).div(100);
        b.highestBid = msg.value;
        b.highestBidMinusFees = msg.value.sub(fee);
        b.highestBidder = msg.sender;
        b.bidCount = b.bidCount.add(1);

        // 6. Update pool accETHperGFARM
        uint tokenBalance = token.balanceOf(address(this));
        if(tokenBalance > 0){
            accETHperGFARM = accETHperGFARM.add(
                fee.mul(1e18).div(tokenBalance)
            );
        }

        // 7. Store stats
        totalEthDistributed = totalEthDistributed.add(fee);

        // 8. Emit event
        emit NewBid(
            b.seller,
            msg.sender,
            _nftID,
            leverage,
            msg.value
        );
    }

    // 3. Claim an NFT after the bid has ended
    function claim(uint _nftID) external notContract listed(_nftID){
        Bidding memory b = biddingsByLeverage[nft.idToLeverage(_nftID)][idToBiddingsByLeverageIndex[_nftID]];

        // 1. Verify the bid has ended
        require(block.number >= b.start.add(b.duration), "Bidding hasn't ended.");

        // 2. Verify there was at least one bid
        require(b.bidCount > 0, "No bid was made.");

        // 3. Transfer the ETH to the seller (25% fee)
        uint fee = b.highestBidMinusFees.mul(HIGHEST_BID_FEE_P).div(100);
        b.seller.transfer(b.highestBidMinusFees.sub(fee));

        // 4. Transfer the NFT to the highest bidder
        nft.transferFrom(address(this), b.highestBidder, _nftID);

        // 5. Remove the bidding
        removeBidding(_nftID);

        // 6. Pool
        uint tokenBalance = token.balanceOf(address(this));
        if(tokenBalance > 0){
            accETHperGFARM = accETHperGFARM.add(
                fee.mul(1e18).div(tokenBalance)
            );
        }

        // 7. Store stats
        totalEthDistributed = totalEthDistributed.add(fee);
    }

    // 4. Claim unsold NFT after bidding ends
    function claimBack(uint _nftID) external notContract listed(_nftID){
        Bidding memory b = biddingsByLeverage[nft.idToLeverage(_nftID)][idToBiddingsByLeverageIndex[_nftID]];

        // 1. Verify there was 0 bid
        require(b.bidCount == 0, "Bids were made.");

        // 2. Verify the bid has ended
        require(block.number >= b.start.add(b.duration), "Bidding hasn't ended.");

        // 3. Send the NFT back to the seller
        nft.transferFrom(address(this), b.seller, _nftID);

        // 4. Remove the bidding
        removeBidding(_nftID);
    }

    // 5. Biddings count for a leverage
    function biddingsCountLeverage(uint _leverage) external view returns(uint){
        return biddingsByLeverage[_leverage].length;
    }

    // PUBLIC FUNCTIONS (EXCHANGE)

    function isListed(uint _nftID) public view returns(bool){
        return biddingsByLeverage[nft.idToLeverage(_nftID)].length > 0 &&
        biddingsByLeverage[nft.idToLeverage(_nftID)][idToBiddingsByLeverageIndex[_nftID]].nftID == _nftID;
    }

    // PUBLIC FUNCTIONS (POOL)

    // 1. Harvest pending ETH rewards
    function harvest() public notContract{
        uint pending = pendingReward();
        if(pending == 0){ return; }

        // 1. Send pending rewards
        msg.sender.transfer(pendingReward());

        // 2. Update debt
        User storage u = users[msg.sender];
        u.debt = u.provided.mul(accETHperGFARM).div(1e18);
    }

    // 2. Get ETH pending reward
    function pendingReward() view public returns(uint){
        User memory u = users[msg.sender];
        return u.provided.mul(accETHperGFARM).div(1e18).sub(u.debt);
    }

    // EXTERNAL FUNCTIONS (POOL)

    // 1. Stake GFARM2 + harvest
    function stake(uint amount) external notContract{
        // 1. Transfer the GFARM2 to the contract
        token.transferFrom(msg.sender, address(this), amount);

        // 2. Harvest pending rewards
        uint pending = pendingReward();
        if(pending > 0){ msg.sender.transfer(pendingReward()); }

        // 3. Set user provided & debt
        User storage u = users[msg.sender];
        u.provided = u.provided.add(amount);
        u.debt = u.provided.mul(accETHperGFARM).div(1e18);
    }

    // 2. Unstake GFARM2 + harvest
    function unstake(uint amount) external notContract{
        // 1. Verify he doesn't unstake more than provided
        User storage u = users[msg.sender];
        require(amount <= u.provided, "Unstaking more than provided.");

        // 2. Harvest pending rewards
        uint pending = pendingReward();
        if(pending > 0){ msg.sender.transfer(pendingReward()); }

        // 3. Set user provided & debt
        u.provided = u.provided.sub(amount);
        u.debt = u.provided.mul(accETHperGFARM).div(1e18);

        // 4. Transfer the GFARM2 to the address
        token.transfer(msg.sender, amount);

        // 5. Burn 10%
        token.burn(msg.sender, amount.mul(10).div(100));
    }

    // USEFUL FRONT-END FUNCTIONS

    // 1. ETH/USD price (1e5)
    function getEthPrice() private view returns(uint){
        (uint112 reserves0, uint112 reserves1, ) = ETH_USDC_PAIR.getReserves();
        uint reserveUSDC;
        uint reserveETH;

        if(WETH == ETH_USDC_PAIR.token0()){
            reserveETH = reserves0;
            reserveUSDC = reserves1;
        }else{
            reserveUSDC = reserves0;
            reserveETH = reserves1;
        }
        // Divide number of USDC by number of ETH
        // we multiply by 1e12 because USDC only has 6 decimals
        return reserveUSDC.mul(1e12).mul(1e5).div(reserveETH);
    }

    // 2. GFARM/ETH price (1e5)
    function getGFarmPriceEth() private view returns(uint){
        (uint112 reserves0, uint112 reserves1, ) = lp.getReserves();

        uint reserveETH;
        uint reserveGFARM;

        if(WETH == lp.token0()){
            reserveETH = reserves0;
            reserveGFARM = reserves1;
        }else{
            reserveGFARM = reserves0;
            reserveETH = reserves1;
        }

        return reserveETH.mul(1e5).div(reserveGFARM);
    }

    // TVL of GFARM2 staked in $ (1e5)
    function TVL() external view returns(uint){
        return token.balanceOf(address(this)).mul(getGFarmPriceEth()).mul(getEthPrice()).div(1e23);
    }

}
