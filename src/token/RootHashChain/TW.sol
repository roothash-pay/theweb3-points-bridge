// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title TW Token (ERC20) for RootHashChain
/// @notice Simple ERC20 with owner-controlled minting and token burning
/// @dev Initial supply minted to 0x118967ae62d4cEa0e208681B69C3594F0dB717bd
contract TWToken is
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable
{
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        // Mint initial discovered supply: 21,000,000 tokens (18 decimals)
        __ERC20_init("TW Token", "TW");
        __ERC20Burnable_init();
        __Ownable_init(owner);
        uint256 initial = 21_000_000 * 10 ** decimals();
        _mint(0x118967ae62d4cEa0e208681B69C3594F0dB717bd, initial);
    }

    /// @notice Mint new tokens (only owner)
    /// @dev Use sparingly — minting increases total supply
    /// @param to recipient address
    /// @param amount token amount in wei (include decimals)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller (inherited from ERC20Burnable)
    /// @dev burn and burnFrom are available via ERC20Burnable
    /// @param amount token amount in wei (include decimals)
    function burn(uint256 amount) public override onlyOwner {
        super.burn(amount);
    }

    // Optional: owner rescue function for accidentally sent ERC20s
    function recoverERC20(
        address token,
        uint256 amount,
        address to
    ) external onlyOwner {
        require(token != address(this), "Cannot recover native TW tokens");
        (bool success, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success, "ERC20 recover failed");
    }
}
