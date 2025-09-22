// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import "../interfaces/IPoolManager.sol";
import "./Points_PoolManagerStorage.sol";

contract PointsPoolManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    PoolManagerStorage
{
    using SafeERC20 for IERC20;

    modifier onlyReLayer() {
        require(msg.sender == address(relayerAddress), "TreasureManager:onlyReLayer only relayer call this function");
        _;
    }

    modifier onlyWithdrawManager() {
        require(
            msg.sender == address(withdrawManager),
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        depositPointsToBridge();
    }

    function initialize(
        address initialOwner,
        address _messageManager,
        address _relayerAddress,
        address _withdrawManager
    ) public initializer {
        __ReentrancyGuard_init();

        MinTransferAmount = 0.1 ether;
        PerFee = 10000;

        __Ownable_init(initialOwner);

        messageManager = IMessageManager(_messageManager);
        relayerAddress = _relayerAddress;
        withdrawManager = _withdrawManager;
    }

    function depositPointsToBridge() public payable whenNotPaused nonReentrant returns (bool) {
        PointsPoolBalance += msg.value;
        emit DepositPoints(msg.sender, msg.value);
        return true;
    }

    function withdrawPointsFromBridge(address payable withdrawAddress, uint256 amount)
        public
        payable
        whenNotPaused
        onlyWithdrawManager
        returns (bool)
    {
        require(
            address(this).balance >= amount,
            "PoolManager withdrawPointsFromBridge: insufficient Points balance in contract"
        );
        PointsPoolBalance -= amount;
        (bool success,) = withdrawAddress.call{value: amount}("");
        if (!success) {
            return false;
        }
        emit WithdrawPoints(msg.sender, withdrawAddress, amount);
        return true;
    }

    function BridgeInitiatePoints(uint256 sourceChainId, uint256 destChainId, address to)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (to == address(0)) {
            to = msg.sender;
        }

        if (msg.value < MinTransferAmount) {
            revert LessThanMinTransferAmount(MinTransferAmount, msg.value);
        }

        PointsPoolBalance += msg.value;

        uint256 fee = (msg.value * PerFee) / 1_000_000;
        uint256 amount = msg.value - fee;

        messageManager.sendMessage(block.chainid, destChainId, msg.sender, to, amount, fee);

        emit InitiatePoints(sourceChainId, destChainId, msg.sender, to, amount);

        return true;
    }

    function BridgeFinalizePoints(
        uint256 sourceChainId,
        uint256 destChainId,
        address from,
        address to,
        uint256 amount,
        uint256 _fee,
        uint256 _nonce
    ) external payable whenNotPaused onlyReLayer returns (bool) {
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        (bool _ret,) = payable(to).call{value: amount}("");
        if (!_ret) {
            revert TransferPointsFailed();
        }

        PointsPoolBalance -= amount;

        messageManager.claimMessage(sourceChainId, destChainId, from, to, amount, _fee, _nonce);

        emit FinalizePoints(sourceChainId, destChainId, address(this), to, amount);

        return true;
    }

    function setMinTransferAmount(uint256 _MinTransferAmount) external onlyReLayer {
        MinTransferAmount = _MinTransferAmount;
        emit SetMinTransferAmount(_MinTransferAmount);
    }

    function setValidChainId(uint256 chainId, bool isValid) external onlyReLayer {
        IsSupportedChainId[chainId] = isValid;
        emit SetValidChainId(chainId, isValid);
    }

    function setPerFee(uint256 _PerFee) external onlyReLayer {
        require(_PerFee < 1_000_000);
        PerFee = _PerFee;
        emit SetPerFee(_PerFee);
    }

    function IsSupportChainId(uint256 chainId) internal view returns (bool) {
        return IsSupportedChainId[chainId];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getPointsPoolBalance() public view returns (uint256) {
        return PointsPoolBalance;
    }
}
