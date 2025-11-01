// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleTestNFT
 * @dev 极简测试用 NFT，用于桥接测试。
 * 支持 mint、burn、approve、transfer。
 */

// ******* 实际的NFT要能同时给桥权限，也能给管理员权限

contract NonMintNFT is ERC721, ERC721Burnable, Ownable {
    uint256 private _nextTokenId;

    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner
    ) ERC721(name_, symbol_) Ownable(initialOwner) {}

    /**
     * @dev mint NFT 给指定地址（仅合约所有者或桥合约在测试中可调用）
     */
    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = ++_nextTokenId;
        _safeMint(to, tokenId);
    }

    /**
     * @dev 自定义 mint 指定 tokenId（桥测试场景下常用）
     */

    /**
     * @dev 获取当前已分配的最大 tokenId（测试辅助）
     */
    function currentTokenId() external view returns (uint256) {
        return _nextTokenId;
    }
}
