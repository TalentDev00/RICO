pragma solidity ^0.4.18;
import "./SafeMath.sol";
import "./RICOToken.sol";
/// @title Dutch auction contract - distribution of a fixed number of tokens using an auction.
/// The contract code is inspired by the Gnosis auction contract. Main difference is that the
/// auction ends if a fixed number of tokens was sold.
/// @notice contract based on Raiden-Project. Thanks to hard commit ethereum-communities!
/// https://github.com/raiden-network/raiden-token/blob/master/contracts/auction.sol
contract DutchAuction {
  /// using safemath
  using SafeMath for uint256;

  /*
   * Storage
   */

  address public owner;
  address public wallet;
  RICOToken public token;
  // Price decay function parameters to be changed depending on the desired outcome

  // Starting price in WEI; e.g. 2 * 10 ** 18
  uint public priceStart;
  uint public startBlock;
  uint public startTime;
  uint public endTime;
  uint public finalPrice;


  // Divisor constant; e.g. 524880000
  uint public priceConstant;
  // Divisor exponent; e.g. 3
  uint32 public priceExponent;

  // For calculating elapsed time for price

  // Keep track of all ETH received in the bids
  uint public receivedWei;

  // Keep track of cumulative ETH funds for which the tokens have been claimed
  uint public fundsClaimed;

  uint public tokenMultiplier;

  // Total number of Rei (RDN * token_multiplier) that will be auctioned
  uint public numTokensAuctioned;

  // Wei per RDN (Rei * token_multiplier)

  uint public nowPrice;

  // Bidder address => bid value
  mapping(address => uint) public bids;
  mapping (address => uint256) balances;

  Stages public stage;

  /*
   * Enums
   */
  enum Stages {
    AuctionInit,
    AuctionDeployed,
    AuctionSetUp,
    AuctionStarted,
    AuctionEnded,
    TokensDistributed
  }

  /*
   * Modifiers
   */
  modifier atStage(Stages _stage) {
    require(stage == _stage);
    _;
  }

  modifier isOwner() {
    require(msg.sender == owner);
    _;
  }

  /*
   * Events
   */

  event Deployed(uint indexed _startPrice, uint indexed _priceConstant, uint32 indexed _priceExponent);
  event Setup();
  event AuctionStarted(uint indexed _startTime, uint indexed _blockNumber);
  event BidSubmission(address indexed _sender, uint _amount, uint _missingFunds);
  event ClaimedTokens(address indexed _recipient, uint _sentAmount);
  event AuctionEnded(uint _finalPrice);

  /*
   * Public functions
   */

  /// @dev Contract constructor function sets the starting price, divisor constant and
  /// divisor exponent for calculating the Dutch Auction price.

  function DutchAuction() {
    owner = msg.sender;
  }


  /// @param _wallet Wallet address to which all contributed ETH will be forwarded.
  /// @param _priceStart High price in WEI at which the auction starts.
  /// @param _priceConstant Auction price divisor constant.
  /// @param _priceExponent Auction price divisor exponent.
  function init(
    address _wallet,
    uint256 _tokenSupply,
    uint256 _priceStart,
    uint256 _priceConstant,
    uint32 _priceExponent
  )
  public isOwner() atStage(Stages.AuctionInit) returns (bool)
  {
    require(_wallet != 0x0 && _tokenSupply != 0);
    wallet = _wallet;
    numTokensAuctioned = _tokenSupply;
    changeSettings(_priceStart, _priceConstant, _priceExponent);
    stage = Stages.AuctionDeployed;

    Deployed(_priceStart, _priceConstant, _priceExponent);

    return true;
  }

  /// @notice Set `_price_start`, `_price_constant` and `_price_exponent` as
  /// the new starting price, price divisor constant and price divisor exponent.
  /// @dev Changes auction price function parameters before auction is started.
  /// @param _priceStart Updated start price.
  /// @param _priceConstant Updated price divisor constant.
  /// @param _priceExponent Updated price divisor exponent.
  function changeSettings(uint _priceStart, uint _priceConstant, uint32 _priceExponent) internal {
    require(stage == Stages.AuctionDeployed || stage == Stages.AuctionSetUp);
    require(_priceStart > 0);
    require(_priceConstant > 0);

    priceStart = _priceStart;
    priceConstant = _priceConstant;
    priceExponent = _priceExponent;
  }


  /// @notice Set `_token_address` as the token address to be used in the auction.
  /// @dev Setup function sets external contracts addresses.
  /// @param _token Token address.
  function setup(address _token) public isOwner atStage(Stages.AuctionDeployed) {
    require(_token != 0x0);
    token = RICOToken(_token);
    // Get number of Rei (RDN * token_multiplier) to be auctioned from token auction balance
    //num_tokens_auctioned = token.balanceOf(address(this));

    // Set the number of the token multiplier for its decimals
    tokenMultiplier = 10 ** uint256(token.decimals());

    stage = Stages.AuctionSetUp;
    Setup();
  }

  /// --------------------------------- Auction Functions ------------------



  /// @notice Start the auction.
  /// @dev Starts auction and sets start_time.
  function startAuction() public isOwner atStage(Stages.AuctionSetUp) {
    stage = Stages.AuctionStarted;
    startTime = now;
    startBlock = block.number;
    AuctionStarted(startTime, startBlock);
  }

  /// @notice Finalize the auction - sets the final RDN token price and changes the auction
  /// stage after no bids are allowed anymore.
  /// @dev Finalize auction and set the final RDN token price.
  function finalizeAuction() public atStage(Stages.AuctionStarted) {
    // Missing funds should be 0 at this point
    uint missingFunds = missingFundsToEndAuction();
    require(missingFunds == 0);

    // Calculate the final price = WEI / RDN = WEI / (Rei / token_multiplier)
    // Reminder: num_tokens_auctioned is the number of Rei (RDN * token_multiplier) that are auctioned
    finalPrice = tokenMultiplier * receivedWei / numTokensAuctioned;

    endTime = now;
    stage = Stages.AuctionEnded;
    AuctionEnded(finalPrice);

    assert(finalPrice > 0);
  }



  /// @notice Send `msg.value` WEI to the auction from the `msg.sender` account.
  /// @dev Allows to send a bid to the auction.
  function bid(address _receiver) public payable isOwner() atStage(Stages.AuctionStarted) {
    require(msg.value > 0);
    require(_receiver != 0x0);
    assert(bids[msg.sender] + msg.value >= msg.value);

    // Missing funds without the current bid value
    uint missingFunds = missingFundsToEndAuction();

    // We require bid values to be less than the funds missing to end the auction
    // at the current price.
    require(msg.value <= missingFunds);

    bids[msg.sender] += msg.value;
    receivedWei += msg.value;

    // Send bid amount to wallet
    wallet.transfer(msg.value);

    BidSubmission(msg.sender, msg.value, missingFunds);

    assert(receivedWei >= msg.value);
  }

  /// @notice Claim auction tokens for `msg.sender` after the auction has ended.
  /// @dev Claims tokens for `msg.sender` after auction. To be used if tokens can
  /// be claimed by beneficiaries, individually.
  function claimTokens(address _receiver) public isOwner() atStage(Stages.AuctionEnded) returns(bool) {

    require(_receiver != 0x0);

    if (bids[_receiver] == 0) {
      return false;
    }

    // Number of Rei = bid_wei / Rei = bid_wei / (wei_per_RDN * token_multiplier)
    uint num = (tokenMultiplier * bids[_receiver]) / finalPrice;
   
    // Update the total amount of funds for which tokens have been claimed
    fundsClaimed += bids[_receiver];

    balances[_receiver] = balances[_receiver].add(num);

    // Set receiver bid to 0 before assigning tokens
    bids[_receiver] = 0;

    ClaimedTokens(_receiver, num);

    return true;
  }

  function getTokenBalance(address _user) constant public returns (uint) {
    return balances[_user];
  }


  /// @notice Get the RDN price in WEI during the auction, at the time of
  /// calling this function. Returns `0` if auction has ended.
  /// Returns `price_start` before auction has started.
  /// @dev Calculates the current RDN token price in WEI.
  /// @return Returns WEI per RDN (token_multiplier * Rei).
  function price() public constant returns(uint) {
    if (stage == Stages.AuctionEnded ||
      stage == Stages.TokensDistributed) {
      return 0;
    }
    return calcTokenPrice();
  }

  /// @notice Get the missing funds needed to end the auction,
  /// calculated at the current RDN price in WEI.
  /// @dev The missing funds amount necessary to end the auction at the current RDN price in WEI.
  /// @return Returns the missing funds amount in WEI.
  function missingFundsToEndAuction() constant public returns(uint) {

    // num_tokens_auctioned = total number of Rei (RDN * token_multiplier) that is auctioned
    nowPrice = price();
    uint requiredWeiAtPrice = numTokensAuctioned * nowPrice / tokenMultiplier;
    if (requiredWeiAtPrice <= receivedWei) {
      return 0;
    }

    // assert(required_wei_at_price - received_wei > 0);
    return requiredWeiAtPrice - receivedWei;
  }

  /*
   *  Private functions
   */

  /// @dev Calculates the token price (WEI / RDN) at the current timestamp
  /// during the auction; elapsed time = 0 before auction starts.
  /// Based on the provided parameters, the price does not change in the first
  /// `price_constant^(1/price_exponent)` seconds due to rounding.
  /// Rounding in `decay_rate` also produces values that increase instead of decrease
  /// in the beginning; these spikes decrease over time and are noticeable
  /// only in first hours. This should be calculated before usage.
  /// @return Returns the token price - Wei per RDN.
  function calcTokenPrice() constant private returns(uint) {
    uint elapsed;
    if (stage == Stages.AuctionStarted) {
      elapsed = now - startTime;
    }

    uint decayRate = elapsed ** priceExponent / priceConstant;
    return priceStart * (1 + elapsed) / (1 + elapsed + decayRate);
  }
}