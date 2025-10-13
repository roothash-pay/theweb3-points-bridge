// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWrappedERC20 {
    // === 视图方法 ===
    function bridgeAddress() external view returns (address);

    // === 权限方法 ===
    function setBridgeAddress(address _bridgeAddress) external;

    // === ERC20 方法 ===
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    // === ERC20 Burnable ===
    function burn(uint256 amount) external;

    // === Owner / Bridge 方法 ===
    function mint(address to, uint256 amount) external;

    // === Rescue ===
    function recoverERC20(address token, uint256 amount, address to) external;
}
