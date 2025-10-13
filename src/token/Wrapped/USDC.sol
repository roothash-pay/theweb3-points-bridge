// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title USDC Token (ERC20) for RootHashChain
/// @notice Simple ERC20 with owner-controlled minting and token burning
contract USDCToken is
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable
{
    address public bridgeAddress;

    constructor() {
        _disableInitializers();
    }

    modifier onlyBridge() {
        require(
            msg.sender == bridgeAddress || msg.sender == owner(),
            "Not called from bridge address or owner"
        );
        _;
    }

    function initialize(address owner) external initializer {
        __ERC20_init("USDC Token", "USDC");
        __ERC20Burnable_init();
        __Ownable_init(owner);
    }

    /// @notice Mint new tokens (only owner)
    /// @dev Use sparingly — minting increases total supply
    /// @param to recipient address
    /// @param amount token amount in wei (include decimals)
    function mint(address to, uint256 amount) external onlyBridge {
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller (inherited from ERC20Burnable)
    /// @dev burn and burnFrom are available via ERC20Burnable
    /// @param amount token amount in wei (include decimals)
    function burn(uint256 amount) public override onlyBridge {
        super.burn(amount);
    }

    function setBridgeAddress(address _bridgeAddress) public onlyOwner {
        bridgeAddress = _bridgeAddress;
    }

    // Optional: owner rescue function for accidentally sent ERC20s
    function recoverERC20(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(token != address(this), "Cannot recover native USDC tokens");
        (bool success, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success, "ERC20 recover failed");
    }
}
