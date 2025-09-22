// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IMessageManager.sol";
import "../interfaces/IEthPoolManager.sol";

abstract contract PoolManagerStorage is IEthPoolManager {
    // address public constant PointsAddress =
    //     address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint256 public MinTransferAmount;
    uint256 public PerFee; // 0.1%

    address public relayerAddress;

    IMessageManager public messageManager;

    // address public assetBalanceMessager;
    address public withdrawManager;

    mapping(uint256 => bool) public IsSupportedChainId;
    uint256 public EthPoolBalance;

    // mapping(address => uint256) public FeePoolValue;
}
