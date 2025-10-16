// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IPoolManager.sol";
import "../interfaces/IWrappedERC20.sol";
import "./PoolManagerRootHashStorage.sol";

contract PoolManagerRootHash is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    PoolManagerRootHashStorage
{
    using SafeERC20 for IERC20;

    modifier onlyReLayer() {
        require(
            msg.sender == address(relayerAddress),
            "TreasureManager:onlyReLayer only relayer call this function"
        );
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
        depositNativeTokenToBridge();
    }

    function initialize(
        address initialOwner,
        address _messageManager,
        address _relayerAddress,
        address _withdrawManager
    ) public initializer {
        __ReentrancyGuard_init();

        periodTime = 21 days;
        MinTransferAmount = 0.1 ether;
        PerFee[NativeTokenAddress] = 10000;
        stakingMessageNumber = 1;

        __Ownable_init(initialOwner);
        __Pausable_init();
        _PoolManagerRootHashStorageInit();

        messageManager = IMessageManager(_messageManager);
        relayerAddress = _relayerAddress;
        withdrawManager = _withdrawManager;
    }

    // Deposit native token or erc20 token to bridge
    function depositNativeTokenToBridge()
        public
        payable
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        FundingPoolBalance[NativeTokenAddress] += msg.value;
        emit DepositToken(NativeTokenAddress, msg.sender, msg.value);
        return true;
    }

    // Deposit erc20 token to bridge
    function depositErc20ToBridge(
        address tokenAddress,
        uint256 amount
    ) public whenNotPaused nonReentrant returns (bool) {
        if (!IsSupportToken[tokenAddress]) {
            revert TokenIsNotSupported(tokenAddress);
        }
        IERC20(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        FundingPoolBalance[tokenAddress] += amount;
        emit DepositToken(tokenAddress, msg.sender, amount);
        return true;
    }

    // Withdraw native token token from bridge
    // only withdrawManager can call this function
    function withdrawNativeTokenFromBridge(
        address payable withdrawAddress,
        uint256 amount
    ) public payable whenNotPaused onlyWithdrawManager returns (bool) {
        require(
            address(this).balance >= amount,
            "PoolManager withdrawNativeTokenFromBridge: insufficient NativeToken balance in contract"
        );
        FundingPoolBalance[NativeTokenAddress] -= amount;
        (bool success, ) = withdrawAddress.call{value: amount}("");
        if (!success) {
            return false;
        }
        emit WithdrawToken(
            NativeTokenAddress,
            msg.sender,
            withdrawAddress,
            amount
        );
        return true;
    }

    // Withdraw erc20 token from bridge
    function withdrawErc20FromBridge(
        address tokenAddress,
        address withdrawAddress,
        uint256 amount
    ) public whenNotPaused onlyWithdrawManager returns (bool) {
        require(
            FundingPoolBalance[tokenAddress] >= amount,
            "PoolManager withdrawNativeTokenFromBridge: Insufficient token balance in contract"
        );
        FundingPoolBalance[tokenAddress] -= amount;
        IERC20(tokenAddress).safeTransfer(withdrawAddress, amount);
        emit WithdrawToken(tokenAddress, msg.sender, withdrawAddress, amount);
        return true;
    }

    // Withdraw Fee Value token from bridge
    function withdrawFeeValue(
        address tokenAddress,
        address withdrawAddress,
        uint256 amount
    ) public whenNotPaused onlyWithdrawManager returns (bool) {
        require(
            FeePoolValue[tokenAddress] >= amount,
            "PoolManager withdrawNativeTokenFromBridge: Insufficient token balance in contract"
        );
        FeePoolValue[tokenAddress] -= amount;
        if (tokenAddress != NativeTokenAddress) {
            IERC20(tokenAddress).safeTransfer(withdrawAddress, amount);
        } else {
            (bool success, ) = payable(withdrawAddress).call{value: amount}("");
            require(success == true, "native token withdraw failed");
        }
        return true;
    }

    // User initiate native token transfer to other chain
    function BridgeInitiateNativeToken(
        uint256 sourceChainId,
        uint256 destChainId,
        address destTokenAddress,
        address to
    ) external payable whenNotPaused nonReentrant returns (bool) {
        // Check source chain id
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        // if (block.timestamp - BridgeNativeTokenTimeStamp[msg.sender] < 1 days) {
        //     revert TimeIntervalNotReached();
        // }

        // Check dest chain id
        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (msg.value < MinTransferAmount) {
            revert LessThanMinTransferAmount(MinTransferAmount, msg.value);
        }

        if (msg.value > MaxPointsTransferAmount) {
            revert MoreThanMaxTransferAmount(
                MaxPointsTransferAmount,
                msg.value
            );
        }

        FundingPoolBalance[NativeTokenAddress] += msg.value;

        //  Calculate fee
        uint256 fee = (msg.value * PerFee[NativeTokenAddress]) / 1_000_000;
        uint256 amount = msg.value - fee;

        FeePoolValue[NativeTokenAddress] += fee;

        messageManager.sendMessage(
            block.chainid,
            destChainId,
            NativeTokenAddress,
            destTokenAddress,
            msg.sender,
            to,
            amount,
            fee
        );

        emit InitiateNativeToken(
            sourceChainId,
            destChainId,
            destTokenAddress,
            msg.sender,
            to,
            amount
        );

        return true;
    }

    // User initiate erc20 token transfer to other chain
    function BridgeInitiateWrappedERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address to,
        address sourceTokenAddress,
        address destTokenAddress,
        uint256 value
    ) external whenNotPaused nonReentrant returns (bool) {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        // if (block.timestamp - BridgeERC20TokenTimeStamp[msg.sender] < 1 days) {
        //     revert TimeIntervalNotReached();
        // }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (!IsSupportToken[sourceTokenAddress]) {
            revert TokenIsNotSupported(sourceTokenAddress);
        }

        if (value < MinTransferAmount) {
            revert LessThanMinTransferAmount(MinTransferAmount, value);
        }

        if (value > MaxERC20TransferAmount) {
            revert MoreThanMaxTransferAmount(MaxERC20TransferAmount, value);
        }

        IERC20(sourceTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            value
        );

        // Burn the wrapped token
        IWrappedERC20(sourceTokenAddress).burn(value);

        // Calculate fee
        uint256 fee = (value * PerFee[sourceTokenAddress]) / 1_000_000;

        uint256 amount = value - fee;
        FeePoolValue[destTokenAddress] += fee;

        messageManager.sendMessage(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            msg.sender,
            to,
            amount,
            fee
        );

        emit InitiateERC20(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            msg.sender,
            to,
            amount
        );

        return true;
    }

    // User initiate erc20 token transfer to other chain for USDT
    function BridgeInitiateERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address to,
        address sourceTokenAddress,
        address destTokenAddress,
        uint256 value
    ) external whenNotPaused nonReentrant returns (bool) {
        if (sourceChainId != block.chainid) {
            revert sourceChainIdError();
        }

        // if (block.timestamp - BridgeERC20TokenTimeStamp[msg.sender] < 1 days) {
        //     revert TimeIntervalNotReached();
        // }

        if (!IsSupportChainId(destChainId)) {
            revert ChainIdIsNotSupported(destChainId);
        }

        if (!IsSupportToken[sourceTokenAddress]) {
            revert TokenIsNotSupported(sourceTokenAddress);
        }

        if (value < MinTransferAmount) {
            revert LessThanMinTransferAmount(MinTransferAmount, value);
        }

        if (value > MaxERC20TransferAmount) {
            revert MoreThanMaxTransferAmount(MaxERC20TransferAmount, value);
        }

        uint256 BalanceBefore = IERC20(sourceTokenAddress).balanceOf(
            address(this)
        );
        IERC20(sourceTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            value
        );
        uint256 BalanceAfter = IERC20(sourceTokenAddress).balanceOf(
            address(this)
        );

        uint256 amount = BalanceAfter - BalanceBefore;
        FundingPoolBalance[sourceTokenAddress] += value;

        // Convert to USDT amount
        uint256 usdtAmount = (amount *
            TokenUSDTExchangeRate[sourceTokenAddress]) / (1e6 * 1e12); // assuming token has 18 decimals

        // Calculate fee
        uint256 fee = (usdtAmount * PerFee[sourceTokenAddress]) / 1_000_000;
        usdtAmount -= fee;
        FeePoolValue[destTokenAddress] += fee;

        messageManager.sendMessage(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            msg.sender,
            to,
            usdtAmount,
            fee
        );

        emit InitiateERC20(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            msg.sender,
            to,
            usdtAmount
        );

        return true;
    }

    function BridgeFinalizeNativeToken(
        uint256 sourceChainId,
        uint256 destChainId,
        address sourceTokenAddress,
        address from,
        address to,
        uint256 amount,
        uint256 _fee,
        uint256 _nonce
    ) external payable whenNotPaused onlyReLayer returns (bool) {
        // check dest chain id
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        // send native token to user
        (bool _ret, ) = payable(to).call{value: amount}("");
        if (!_ret) {
            revert TransferNativeTokenFailed();
        }

        FundingPoolBalance[NativeTokenAddress] -= amount;

        messageManager.claimMessage(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            NativeTokenAddress,
            from,
            to,
            amount,
            _fee,
            _nonce
        );

        emit FinalizeNativeToken(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            address(this),
            to,
            amount
        );

        return true;
    }

    function BridgeFinalizeWrappedERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address from,
        address to,
        address sourceTokenAddress,
        address destTokenAddress,
        uint256 amount,
        uint256 _fee,
        uint256 _nonce
    ) external whenNotPaused onlyReLayer returns (bool) {
        // check dest chain id
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        // check dest token is supported
        if (!IsSupportToken[destTokenAddress]) {
            revert TokenIsNotSupported(destTokenAddress);
        }

        // mint erc20 token to user
        IWrappedERC20(destTokenAddress).mint(to, amount);

        messageManager.claimMessage(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            from,
            to,
            amount,
            _fee,
            _nonce
        );

        emit FinalizeERC20(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            address(this),
            to,
            amount
        );

        return true;
    }

    // finalize USDT from other chain for erc20
    function BridgeFinalizeERC20(
        uint256 sourceChainId,
        uint256 destChainId,
        address from,
        address to,
        address sourceTokenAddress,
        address destTokenAddress,
        uint256 _amount,
        uint256 _fee,
        uint256 _nonce
    ) external whenNotPaused onlyReLayer returns (bool) {
        // check dest chain id
        if (destChainId != block.chainid) {
            revert sourceChainIdError();
        }

        if (!IsSupportChainId(sourceChainId)) {
            revert ChainIdIsNotSupported(sourceChainId);
        }

        // check dest token is supported
        if (!IsSupportToken[destTokenAddress]) {
            revert TokenIsNotSupported(destTokenAddress);
        }

        // Calculate the amount of dest token to send to user
        uint256 amount = (_amount * 1e12 * 1e6) /
            TokenUSDTExchangeRate[destTokenAddress]; // assuming token has 18 decimals

        // transfer erc20 token to user
        require(
            IERC20(destTokenAddress).balanceOf(address(this)) >= amount,
            "PoolManager: insufficient token balance for transfer"
        );
        IERC20(destTokenAddress).safeTransfer(to, amount);

        FundingPoolBalance[destTokenAddress] -= amount;

        messageManager.claimMessage(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            from,
            to,
            _amount,
            _fee,
            _nonce
        );

        emit FinalizeERC20(
            sourceChainId,
            destChainId,
            sourceTokenAddress,
            destTokenAddress,
            address(this),
            to,
            amount
        );

        return true;
    }

    function setMinTransferAmount(
        uint256 _MinTransferAmount
    ) external onlyReLayer {
        MinTransferAmount = _MinTransferAmount;
        emit SetMinTransferAmount(_MinTransferAmount);
    }

    function setMaxTransferAmount(
        uint256 _MaxTransferAmount,
        bool isERC20
    ) external onlyReLayer {
        if (isERC20) {
            MaxERC20TransferAmount = _MaxTransferAmount;
        } else {
            MaxPointsTransferAmount = _MaxTransferAmount;
        }
        emit SetMaxTransferAmount(_MaxTransferAmount, isERC20);
    }

    function setValidChainId(
        uint256 chainId,
        bool isValid
    ) external onlyReLayer {
        IsSupportedChainId[chainId] = isValid;
        emit SetValidChainId(chainId, isValid);
    }

    function setSupportERC20Token(
        address ERC20Address,
        bool isValid
    ) external onlyReLayer {
        IsSupportToken[ERC20Address] = isValid;
        if (isValid) {
            SupportTokens.push(ERC20Address);
        }
        emit SetSupportTokenEvent(ERC20Address, isValid, block.chainid);
    }

    function setPerFee(
        uint256 _PerFee,
        address _tokenAddress
    ) external onlyReLayer {
        require(_PerFee < 1_000_000);
        PerFee[_tokenAddress] = _PerFee;
        emit SetPerFee(_PerFee, _tokenAddress);
    }

    function setTokenUSDTExchangeRate(
        uint256 _rate,
        address _tokenAddress
    ) external onlyReLayer {
        require(_rate > 0);
        TokenUSDTExchangeRate[_tokenAddress] = _rate;
        emit SetTokenUSDTExchangeRate(_rate, _tokenAddress);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /***************************************
     ***** Other function *****
     ***************************************/
    function QuickSendAssertToUser(
        address _token,
        address to,
        uint256 _amount
    ) external onlyWithdrawManager {
        SendAssertToUser(_token, to, _amount);
    }

    function SendAssertToUser(
        address _token,
        address to,
        uint256 _amount
    ) internal returns (bool) {
        if (!IsSupportToken[_token]) {
            revert TokenIsNotSupported(_token);
        }

        require((FundingPoolBalance[_token] >= _amount), "Not enough balance");
        FundingPoolBalance[_token] -= _amount;
        if (_token == address(NativeTokenAddress)) {
            if (address(this).balance < _amount) {
                revert NotEnoughNativeToken();
            }
            (bool _ret, ) = payable(to).call{value: _amount}("");
            if (!_ret) {
                revert TransferNativeTokenFailed();
            }
        } else {
            if (IERC20(_token).balanceOf(address(this)) < _amount) {
                revert NotEnoughToken(_token);
            }
            IERC20(_token).safeTransfer(to, _amount);
        }
        return true;
    }

    function IsSupportChainId(uint256 chainId) internal view returns (bool) {
        return IsSupportedChainId[chainId];
    }
}
