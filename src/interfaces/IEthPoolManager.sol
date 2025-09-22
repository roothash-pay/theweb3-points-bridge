// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IEthPoolManager {
    event WithdrawEth(
        address indexed sender,
        address indexed withdrawAddress,
        uint256 amount
    );

    event DepositEth(address indexed sender, uint256 amount);

    event InitiateEth(
        uint256 sourceChainId,
        uint256 destChainId,
        address from,
        address to,
        uint256 amount
    );

    event FinalizeEth(
        uint256 sourceChainId,
        uint256 destChainId,
        address from,
        address to,
        uint256 amount
    );

    event SetMinTransferAmount(uint256 minTransferAmount);

    event SetValidChainId(uint256 chainId, bool isValid);

    event SetPerFee(uint256 perFee);

    error ChainIdIsNotSupported(uint256 id);

    error ChainIdNotSupported(uint256 chainId);

    error NotEnoughToken(address ERC20Address);

    error ErrorBlockChain();

    error LessThanMinTransferAmount(uint256 MinTransferAmount, uint256 value);

    error sourceChainIdError();

    error sourceChainIsDestChainError();

    error TransferEthFailed();

    function BridgeInitiateEth(
        uint256 sourceChainId,
        uint256 destChainId,
        address to
    ) external payable returns (bool);

    function BridgeFinalizeEth(
        uint256 sourceChainId,
        uint256 destChainId,
        address from,
        address to,
        uint256 amount,
        uint256 _fee,
        uint256 _nonce
    ) external payable returns (bool);

    function setMinTransferAmount(uint256 _MinTransferAmount) external;

    function setValidChainId(uint256 chainId, bool isValid) external;

    function setPerFee(uint256 _PerFee) external;

    function pause() external;

    function unpause() external;

    function getEthPoolBalance() external view returns (uint256);
}
