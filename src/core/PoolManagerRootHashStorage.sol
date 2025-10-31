// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IMessageManager.sol";
import "../interfaces/IPoolManager.sol";

abstract contract PoolManagerRootHashStorage is IPoolManager {
    function _PoolManagerRootHashStorageInit() internal {
        MaxPointsTransferAmount = 100 * 10e18;
        MaxERC20TransferAmount = 100 * 10e18;
    }

    // Native Token Address
    address public constant NativeTokenAddress =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint32 public periodTime;

    uint256 public MinTransferAmount;
    uint256 public MaxPointsTransferAmount;
    uint256 public MaxERC20TransferAmount;

    // uint256 public PerFee; // 0.1%
    uint256 public stakingMessageNumber;

    address public relayerAddress;

    IMessageManager public messageManager;

    address[] public SupportTokens;
    address public assetBalanceMessager;
    address public withdrawManager;

    mapping(uint256 => bool) public IsSupportedChainId;
    mapping(address => bool) public IsSupportToken;
    mapping(address => uint256) public FundingPoolBalance;
    mapping(address => uint256) public FeePoolValue;
    mapping(address => uint256) public MinStakeAmount;
    mapping(address => uint256) public BridgeNativeTokenTimeStamp;
    mapping(address => uint256) public BridgeERC20TokenTimeStamp;

    mapping(address => uint256) public PerFee;
    mapping(address => uint256) public TokenUSDTExchangeRate; // token => how many token for 1 USDT

    address public nftFeeToken;
    mapping(address => uint256) public collectionBridgeFee; // nft collection => bridge fee
    uint256 public NFTBridgeBaseFee; // base fee for nft bridge
    mapping(address => uint256) public NFTFeePool; // fee pool for nft bridge

    uint256[50] private __gap;
}
