pragma solidity ^0.4.18;

import "./ContractManager.sol";
import "./PoDs/RICOStandardPoD.sol";
import "./RICO.sol";

/// @title Launcher - RICO Launcher contract
/// @author - Yusaku Senga - <senga@dri.network>
/// license - Please check the LICENSE at github.com/DRI-network/RICO

/**
 * @title   Launcher
 * @dev     Launcher for deploying the Proof of Donation (PoD) contracts with custom variables.
 *          RICO.sol, Launcher.sol and ContractManager.sol, are the three contracts
 *          that have to be deployed on the network on beforehand.
 *          Please see the 2_deploy_contracts.js migration for the details.
 *          
 * @usage   After deploying Launcher.sol and RICO.sol to the network it's important
 *          you register the addresse of RICO.sol and ContractManager.sol in this Launcher.
 *          Please see the 2_deploy_contracts.js migration for the details.
 */
contract Launcher {

  /**
   * Storage
   */
  string public name = "RICO Launcher";
  string public version = "0.9.3";
  RICO public rico;
  ContractManager public cm;
  bool public state = false;

  /**
   * constructor
   */
  function Launcher() public {}

  /**
   * @dev   Register the RICO contract address in the Launcher.
   * @param _rico        RICO's contract address
   */
  function init(address _rico, address _cm) public {
    require(!state);
    rico = RICO(_rico);
    cm = ContractManager(_cm);
    state = true;
  }

  /**
   * @dev standardICO uses 2 pods RICOStandardPoD and SimplePoD.
   * @param _name             Token name of RICO format.
   * @param _symbol           Token symbol of RICO format.
   * @param _decimals         Token decimals of RICO format.
   * @param _wallet           Project owner's multisig wallet.
   * @param _bidParams        array              params of RICOStandardPoD pod.
   *        _bidParams[0]     _startTimeOfPoD    (see RICOStandardPoD.sol)
   *        _bidParams[1]     _capOfToken        (see RICOStandardPoD.sol)
   *        _bidParams[2]     _capOfWei          (see RICOStandardPoD.sol)
   *        _bidParams[3]     _secondCapOfToken  (see RICOStandardPoD.sol)
   * @param _podParams        array              params of SimplePoD pod.
   *        _podParams[0]     _startTimeOfPoD    (see SimplePoD.sol)
   *        _podParams[1]     _capOfToken        (see SimplePoD.sol)
   *        _podParams[2]     _capOfWei          (see SimplePoD.sol)
   * @param _tobAddresses     array              owner addresses for the Take Over Bid (TOB).
   *        _tobAddresses[0]  TOB Funder
   *        _tobAddresses[1]  TOB Locker
   * @param _marketMakers     array of marketMakers address of project.
   */
  function standardICO(
    string _name, 
    string _symbol, 
    uint8 _decimals, 
    address _wallet,
    uint256[] _bidParams,
    uint256[] _podParams,
    address[2] _tobAddresses,
    address[] _marketMakers
  ) 
  public returns (address)
  {
    address[] memory pods = new address[](2);

    RICOStandardPoD rsp = new RICOStandardPoD();

    rsp.init(_decimals, _bidParams[0], _bidParams[1], _bidParams[2], _tobAddresses, _marketMakers, _bidParams[3]);
    rsp.transferOwnership(rico);

    pods[0] = address(rsp);
    pods[1] = cm.deploy(rico, 0, _decimals, _wallet, _podParams);

    return rico.newProject(_name, _symbol, _decimals, pods, _wallet);
  }

  /**
   * @dev simpleICO uses 2 pods SimplePoD and TokenMintPoD.
   * @param _name          Token name of RICO format.
   * @param _symbol        Token symbol of RICO format.
   * @param _decimals      Token decimals of RICO format.
   * @param _wallet        Project owner's multisig wallet.
   * @param _podParams     array             params of SimplePoD pod.
   *        _podParams[0]  _startTimeOfPoD   (see SimplePoD.sol)
   *        _podParams[1]  _capOfToken       (see SimplePoD.sol)
   *        _podParams[2]  _capOfWei         (see SimplePoD.sol)
   * @param _mintParams    array             params of TokenMintPoD pod.
   *        _mintParams[0] _capOfToken       (see TokenMintPod.sol)
   *        _mintParams[1] _lockTime         (see TokenMintPod.sol)
   */
  function simpleICO(
    string _name, 
    string _symbol, 
    uint8 _decimals, 
    address _wallet,
    uint256[] _podParams,
    uint256[] _mintParams
  ) 
  public returns (address)
  {
    address[] memory pods = new address[](2);
    pods[0] = cm.deploy(rico, 0, _decimals, _wallet, _podParams);
    pods[1] = cm.deploy(rico, 1, _decimals, _wallet, _mintParams);

    return rico.newProject(_name, _symbol, _decimals, pods, _wallet);
  }
}
