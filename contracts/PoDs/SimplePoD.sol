pragma solidity ^0.4.18;
import "../PoD.sol";

/// @title SimplePoD - SimplePoD contract
/// @author - Yusaku Senga - <senga@dri.network>
/// license let's see in LICENSE

contract SimplePoD is PoD {

  function SimplePoD() public {
    name = "SimplePoD strategy token price = capToken/capWei";
    version = "0.1";
    period = 7 days;
  }

  function processDonate(address _user) internal returns (bool) {

    if (totalReceivedWei.add(msg.value) > proofOfDonationCapOfWei) {
      return false;
    }
    
    if (block.timestamp > startTime + period) {
      return false;
    }

    tokenPrice = proofOfDonationCapOfToken / proofOfDonationCapOfWei;
    
    weiBalances[_user] = weiBalances[_user].add(msg.value);

    return true;
  }


  function getBalanceOfToken(address _user) public constant returns (uint256) {
    return weiBalances[_user].div(tokenPrice);
  }
}
