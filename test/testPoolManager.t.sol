// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {MessageManager} from "../src/core/MessageManager.sol";
import {mockToken} from "../script/utils/mockERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/interfaces/IPoolManager.sol";
import {SimpleTestNFT} from "./token/nftDemo.sol";

contract PoolManagerTest is Test {
    PoolManager public sourcePoolManager;
    PoolManager public destPoolManager;
    MessageManager public sourceMessageManager;
    MessageManager public destMessageManager;

    mockToken public erc20Token;
    address public constant NativeTokenAddress =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint256 constant SOURCE_CHAIN_ID = 1;
    uint256 constant DEST_CHAIN_ID = 10;

    address cat = makeAddr("cat");
    address seek = makeAddr("seek");

    address bridge_cat = makeAddr("bridge_cat");
    address bridge_seek = makeAddr("bridge_seek");

    address admin;
    address ReLayer;

    SimpleTestNFT nftCollection;
    SimpleTestNFT mirrorNft;
    SimpleTestNFT fakeMirrorNft;

    function setUp() public {
        admin = makeAddr("admin");
        ReLayer = makeAddr("ReLayer");

        vm.deal(admin, 1000 ether);
        vm.deal(ReLayer, 1000 ether);
        vm.deal(cat, 1000 ether);

        PoolManager poolManagerLogic = new PoolManager();
        MessageManager messageManagerLogic = new MessageManager();
        erc20Token = new mockToken("CAT", "CAT");

        vm.startPrank(admin);
        TransparentUpgradeableProxy sourcePoolManagerProxy = new TransparentUpgradeableProxy(
                address(poolManagerLogic),
                admin,
                ""
            );
        TransparentUpgradeableProxy sourceMessageManagerProxy = new TransparentUpgradeableProxy(
                address(messageManagerLogic),
                admin,
                ""
            );
        TransparentUpgradeableProxy destPoolManagerProxy = new TransparentUpgradeableProxy(
                address(poolManagerLogic),
                admin,
                ""
            );
        TransparentUpgradeableProxy destMessageManagerProxy = new TransparentUpgradeableProxy(
                address(messageManagerLogic),
                admin,
                ""
            );

        sourcePoolManager = PoolManager(
            payable(address(sourcePoolManagerProxy))
        );
        destPoolManager = PoolManager(payable(address(destPoolManagerProxy)));
        sourceMessageManager = MessageManager(
            address(sourceMessageManagerProxy)
        );
        destMessageManager = MessageManager(address(destMessageManagerProxy));

        sourcePoolManager.initialize(
            admin,
            address(sourceMessageManager),
            ReLayer,
            admin
        );
        destPoolManager.initialize(
            admin,
            address(destMessageManager),
            ReLayer,
            admin
        );
        sourceMessageManager.initialize(admin, address(sourcePoolManager));
        destMessageManager.initialize(admin, address(destPoolManager));
        vm.stopPrank();

        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(DEST_CHAIN_ID, true);
        destPoolManager.setValidChainId(SOURCE_CHAIN_ID, true);
        sourcePoolManager.setPerFee(
            3000,
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ); // 0.3%
        destPoolManager.setPerFee(
            3000,
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ); // 0.3%
        sourcePoolManager.setSupportERC20Token(address(erc20Token), true);
        destPoolManager.setSupportERC20Token(address(erc20Token), true);
        sourcePoolManager.setSupportERC20Token(NativeTokenAddress, true);
        destPoolManager.setSupportERC20Token(NativeTokenAddress, true);
        sourcePoolManager.setPerFee(3000, address(erc20Token)); // 0.3%
        destPoolManager.setPerFee(3000, address(erc20Token)); // 0.3%
        // sourcePoolManager.setMaxTransferAmount(1000 ether, false);
        sourcePoolManager.depositNativeTokenToBridge{value: 500 ether}(); // 起始原始代币储备500 ETH
        destPoolManager.depositNativeTokenToBridge{value: 500 ether}();

        mockToken(address(erc20Token)).mint(cat, 1000 ether);
        vm.stopPrank();

        vm.startPrank(cat);
        erc20Token.approve(address(sourcePoolManager), 1000 ether);
        erc20Token.approve(address(destPoolManager), 1000 ether);
        sourcePoolManager.depositErc20ToBridge(address(erc20Token), 200 ether); // 起始erc20储备200 e18
        destPoolManager.depositErc20ToBridge(address(erc20Token), 200 ether);
        vm.stopPrank();

        nftCollection = new SimpleTestNFT(
            "LocalNFT",
            "LNFT",
            address(sourcePoolManager)
        );
        mirrorNft = new SimpleTestNFT(
            "MirrorNFT",
            "MNFT",
            address(sourcePoolManager)
        );
        fakeMirrorNft = new SimpleTestNFT(
            "FakeMirrorNFT",
            "FMNFT",
            address(sourcePoolManager)
        );
    }

    // Test bridging ETH from source to destination chain
    function test_Bridge_ETH() public {
        _bridge_ETH(10, cat, seek);
    }

    // Test bridging ERC20 tokens from source to destination chain
    function test_Bridge_ERC20() public {
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(address(erc20Token), true);
        destPoolManager.setSupportERC20Token(address(erc20Token), true);
        vm.stopPrank();

        _bridge_ERC20(10, cat, seek);
    }

    function _bridge_ETH(uint256 amount, address from, address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        vm.deal(from, bridgeAmount);

        address ethTokenAddress = address(
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
        );
        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(
            ethTokenAddress
        );
        uint256 nextMessageNumberBefore = sourceMessageManager
            .nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.prank(from);
        sourcePoolManager.BridgeInitiateNativeToken{value: bridgeAmount}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            ethTokenAddress,
            seek
        );

        assertEq(
            sourcePoolManager.FundingPoolBalance(ethTokenAddress),
            balanceBefore + bridgeAmount,
            "FundingPoolBalance for ETH should increase by bridgeAmount"
        );
        assertEq(
            sourceMessageManager.nextMessageNumber(),
            nextMessageNumberBefore + 1,
            "nextMessageNumber should be incremented"
        );

        uint256 perFee = sourcePoolManager.PerFee(ethTokenAddress);
        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = nextMessageNumberBefore;
        bytes32 messageHash = keccak256(
            abi.encode(
                SOURCE_CHAIN_ID,
                DEST_CHAIN_ID,
                ethTokenAddress,
                ethTokenAddress,
                from,
                to,
                fee,
                amountAfterFee,
                messageNonce
            )
        );

        assertTrue(
            sourceMessageManager.sentMessageStatus(messageHash),
            "Message hash should be marked as sent"
        );
    }

    function _bridge_ERC20(uint256 amount, address from, address to) internal {
        uint256 bridgeAmount = amount * 1 ether;
        erc20Token.mint(from, bridgeAmount);

        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(
            address(erc20Token)
        );
        uint256 nextMessageNumberBefore = sourceMessageManager
            .nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(from);
        erc20Token.approve(address(sourcePoolManager), bridgeAmount);
        sourcePoolManager.BridgeInitiateERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            to,
            address(erc20Token),
            address(erc20Token),
            bridgeAmount
        );
        vm.stopPrank();

        assertEq(
            erc20Token.balanceOf(address(sourcePoolManager)),
            balanceBefore + bridgeAmount,
            "Contract ERC20 balance should equal bridgeAmount"
        );
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(erc20Token)),
            balanceBefore + bridgeAmount,
            "FundingPoolBalance for ERC20 should equal bridgeAmount"
        );
        assertEq(
            sourceMessageManager.nextMessageNumber(),
            nextMessageNumberBefore + 1,
            "nextMessageNumber should be incremented"
        );

        uint256 perFee = sourcePoolManager.PerFee(address(erc20Token));
        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = 1;
        bytes32 messageHash = keccak256(
            abi.encode(
                SOURCE_CHAIN_ID,
                DEST_CHAIN_ID,
                address(erc20Token),
                address(erc20Token),
                from,
                to,
                fee,
                amountAfterFee,
                messageNonce
            )
        );

        assertTrue(
            sourceMessageManager.sentMessageStatus(messageHash),
            "Message hash for ERC20 bridge should be marked as sent"
        );
    }

    function test_Revert_Bridge_Unsupported_Token() public {
        address unsupportedToken = address(
            0x1234567890123456789012345678901234567890
        );
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(unsupportedToken, false);
        vm.stopPrank();

        uint256 bridgeAmount = 10 ether;
        erc20Token.mint(cat, bridgeAmount);

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(cat);
        erc20Token.approve(address(sourcePoolManager), bridgeAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.TokenIsNotSupported.selector, // 注意这里是 `.selector`
                unsupportedToken
            )
        );
        sourcePoolManager.BridgeInitiateERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            seek,
            unsupportedToken,
            unsupportedToken,
            bridgeAmount
        );
        vm.stopPrank();
    }

    function test_depositNativeTokenToBridge() public {
        vm.deal(address(sourcePoolManager), 100 ether);
        vm.deal(address(destPoolManager), 100 ether);
        vm.prank(admin);
        sourcePoolManager.depositNativeTokenToBridge{value: 100 ether}();
        vm.prank(admin);
        destPoolManager.depositNativeTokenToBridge{value: 100 ether}();
        assertEq(address(sourcePoolManager).balance, 200 ether);
        assertEq(address(destPoolManager).balance, 200 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(NativeTokenAddress),
            600 ether
        );
        assertEq(
            destPoolManager.FundingPoolBalance(NativeTokenAddress),
            600 ether
        );
    }

    function test_depositErc20ToBridge() public {
        erc20Token.mint(address(sourcePoolManager), 100 ether);
        erc20Token.mint(address(destPoolManager), 100 ether);
        vm.prank(cat);
        sourcePoolManager.depositErc20ToBridge(address(erc20Token), 100 ether);
        vm.prank(cat);
        destPoolManager.depositErc20ToBridge(address(erc20Token), 100 ether);
        assertEq(erc20Token.balanceOf(address(sourcePoolManager)), 400 ether);
        assertEq(erc20Token.balanceOf(address(destPoolManager)), 400 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(erc20Token)),
            300 ether
        );
        assertEq(
            destPoolManager.FundingPoolBalance(address(erc20Token)),
            300 ether
        );
    }

    function test_withdrawNativeTokenFromBridge() public {
        uint256 beforeBalance = admin.balance;
        vm.prank(admin);
        sourcePoolManager.withdrawNativeTokenFromBridge(
            payable(admin),
            100 ether
        );
        assertEq(admin.balance, beforeBalance + 100 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(NativeTokenAddress),
            400 ether
        );

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        sourcePoolManager.withdrawNativeTokenFromBridge(
            payable(cat),
            100 ether
        );
    }

    function test_withdrawErc20FromBridge() public {
        uint256 beforeBalance = erc20Token.balanceOf(admin);
        vm.prank(admin);
        sourcePoolManager.withdrawErc20FromBridge(
            address(erc20Token),
            admin,
            100 ether
        );
        assertEq(erc20Token.balanceOf(admin), beforeBalance + 100 ether);
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(erc20Token)),
            100 ether
        );

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        sourcePoolManager.withdrawErc20FromBridge(
            address(erc20Token),
            cat,
            100
        );
    }

    function test_setMinandMaxTransferAmount() public {
        vm.prank(ReLayer);
        sourcePoolManager.setMinTransferAmount(1 ether);
        assertEq(sourcePoolManager.MinTransferAmount(), 1 ether);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setMinTransferAmount(2 ether);
    }

    function test_setMaxTransferAmount() public {
        vm.startPrank(ReLayer);
        sourcePoolManager.setMaxTransferAmount(1000 ether, false);
        assertEq(sourcePoolManager.MaxPointsTransferAmount(), 1000 ether);
        sourcePoolManager.setMaxTransferAmount(5000 ether, true);
        assertEq(sourcePoolManager.MaxERC20TransferAmount(), 5000 ether);
        vm.stopPrank();

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.setMaxTransferAmount(2000 ether, true);
    }

    function test_setValidChainId() public {
        vm.prank(ReLayer);
        sourcePoolManager.setValidChainId(999, true);
        assertTrue(sourcePoolManager.IsSupportedChainId(999));

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setValidChainId(998, true);
    }

    function test_setSupportERC20Token() public {
        address newToken = address(0x1234567890123456789012345678901234567890);
        vm.prank(ReLayer);
        sourcePoolManager.setSupportERC20Token(newToken, true);
        assertTrue(sourcePoolManager.IsSupportToken(newToken));
        assertEq(sourcePoolManager.SupportTokens(2), newToken);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setSupportERC20Token(newToken, false);
    }

    function test_setPerFee() public {
        vm.prank(ReLayer);
        sourcePoolManager.setPerFee(5000, address(erc20Token));
        assertEq(sourcePoolManager.PerFee(address(erc20Token)), 5000);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        vm.prank(cat);
        sourcePoolManager.setPerFee(6000, address(erc20Token));
    }

    function test_onlyOwnerCanPause() public {
        vm.prank(admin);
        sourcePoolManager.pause();
        assertTrue(sourcePoolManager.paused());

        vm.chainId(SOURCE_CHAIN_ID);
        vm.expectRevert();
        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 1 ether}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );

        vm.prank(admin);
        sourcePoolManager.unpause();
        assertFalse(sourcePoolManager.paused());

        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 1 ether}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );
        assertEq(
            sourcePoolManager.FundingPoolBalance(NativeTokenAddress),
            501 ether
        );
    }

    function test_QuickSendAssertToUser() public {
        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            address(erc20Token),
            seek,
            100 ether
        );
        assertTrue(
            erc20Token.balanceOf(address(sourcePoolManager)) == 100 ether
        );
        assertTrue(erc20Token.balanceOf(seek) == 100 ether);

        vm.expectRevert(
            "TreasureManager:onlyWithdrawManager only withdraw manager can call this function"
        );
        vm.prank(cat);
        sourcePoolManager.QuickSendAssertToUser(
            address(erc20Token),
            cat,
            100 ether
        );

        address unsupportedToken = address(
            0x1234567890123456789012345678901234567890
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolManager.TokenIsNotSupported.selector, // 注意这里是 `.selector`
                unsupportedToken
            )
        );
        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            unsupportedToken,
            cat,
            100 ether
        );

        vm.expectRevert("Not enough balance");
        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            address(erc20Token),
            cat,
            10000 ether
        );

        vm.prank(admin);
        sourcePoolManager.QuickSendAssertToUser(
            NativeTokenAddress,
            seek,
            1 ether
        );
        assertTrue(seek.balance == 1 ether);
    }

    // ========== 3️⃣ Test finalize ETH by relayer ==========
    function test_Finalize_ETH() public {
        uint256 amount = 10 ether;
        vm.deal(address(destPoolManager), amount);

        vm.chainId(DEST_CHAIN_ID);
        vm.startPrank(ReLayer);
        destPoolManager.BridgeFinalizeNativeToken(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            cat,
            seek,
            amount,
            0,
            1
        );
        vm.stopPrank();

        assertEq(seek.balance, amount, "Receiver should get bridged ETH");
    }

    // ========== 4️⃣ Test finalize ERC20 by relayer ==========
    function test_Finalize_ERC20() public {
        uint256 amount = 100 ether;
        erc20Token.mint(address(destPoolManager), amount);

        vm.chainId(DEST_CHAIN_ID);
        vm.startPrank(ReLayer);
        destPoolManager.BridgeFinalizeERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            cat,
            seek,
            address(erc20Token),
            address(erc20Token),
            amount,
            0,
            1
        );
        vm.stopPrank();

        assertEq(
            erc20Token.balanceOf(seek),
            amount,
            "Receiver should get bridged ERC20 tokens"
        );
    }

    // ========== 5️⃣ Test unauthorized finalize revert ==========
    function test_Revert_Finalize_ETH_Unauthorized() public {
        uint256 amount = 5 ether;
        vm.deal(address(destPoolManager), amount);

        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        destPoolManager.BridgeFinalizeNativeToken(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            cat,
            seek,
            amount,
            0,
            1
        );
    }

    // ========== 6️⃣ Test withdraw function by admin ==========
    function test_Withdraw_ETH() public {
        uint256 depositAmount = 5 ether;
        vm.deal(address(sourcePoolManager), depositAmount);

        uint256 beforeBalance = admin.balance;

        vm.prank(admin);
        sourcePoolManager.withdrawNativeTokenFromBridge(
            payable(admin),
            depositAmount
        );

        assertEq(admin.balance, beforeBalance + depositAmount);
    }

    // ========== 7️⃣ Test invalid chain revert ==========
    function test_Revert_InvalidChain() public {
        vm.deal(cat, 1 ether);
        vm.chainId(SOURCE_CHAIN_ID);

        vm.expectRevert();
        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 1 ether}(
            999, // wrong source chain id
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );
    }

    // ========== 8️⃣ Test less than min transfer amount revert ==========
    function test_Revert_LessThanMin() public {
        vm.deal(cat, 0.01 ether);
        vm.chainId(SOURCE_CHAIN_ID);

        vm.expectRevert();
        vm.prank(cat);
        sourcePoolManager.BridgeInitiateNativeToken{value: 0.01 ether}(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            NativeTokenAddress,
            seek
        );
    }

    function test_IsSupportChainId() public view {
        assertTrue(sourcePoolManager.IsSupportedChainId(DEST_CHAIN_ID));
        assertFalse(sourcePoolManager.IsSupportedChainId(999));
    }

    function test_BridgeInitiateLocalNFT_AllPaths() public {
        uint256 tokenId = 700;
        uint256 baseFee = 1 ether;
        uint256 customFee = 1.5 ether;

        // ========== 准备阶段 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(2222, true); // 支持目标链
        sourcePoolManager.setNftFeeToken(address(erc20Token));
        sourcePoolManager.setNFTBridgeBaseFee(baseFee);
        sourcePoolManager.setCollectionBridgeFee(
            address(nftCollection),
            customFee
        );
        vm.stopPrank();

        // mint NFT 给 cat
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, tokenId);

        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), tokenId);

        // 给 cat 足够手续费 Token
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        uint256 beforeBalance = erc20Token.balanceOf(cat);

        // ========== ✅ 正常路径 ==========
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(fakeMirrorNft),
            tokenId,
            seek
        );

        // ✅ 检查 NFT 被锁入桥合约
        assertEq(nftCollection.ownerOf(tokenId), address(sourcePoolManager));

        // ✅ 检查手续费被正确扣除
        assertEq(erc20Token.balanceOf(cat), beforeBalance - customFee);

        // ✅ 检查 fee 池更新
        assertEq(sourcePoolManager.NFTFeePool(address(erc20Token)), customFee);

        vm.stopPrank();

        // ========== ❌ 测试1：sourceChainId 错误 ==========
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 701);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 701);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        vm.expectRevert(); // sourceChainIdError()
        sourcePoolManager.BridgeInitiateLocalNFT(
            9999, // 错误源链
            2222,
            address(nftCollection),
            address(fakeMirrorNft),
            701,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试2：destChainId 不支持 ==========
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 702);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 702);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        vm.expectRevert(); // ChainIdIsNotSupported()
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            3333, // 未设置支持
            address(nftCollection),
            address(fakeMirrorNft),
            702,
            seek
        );
        vm.stopPrank();

        // ========== ✅ 测试3：collectionBridgeFee 为 0 → fallback 到 baseFee ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setCollectionBridgeFee(address(nftCollection), 0);
        vm.stopPrank();

        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 703);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 703);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        uint256 beforeBalance2 = erc20Token.balanceOf(cat);

        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(fakeMirrorNft),
            703,
            seek
        );

        assertEq(erc20Token.balanceOf(cat), beforeBalance2 - baseFee);
        assertEq(
            sourcePoolManager.NFTFeePool(address(erc20Token)),
            customFee + baseFee
        );
        vm.stopPrank();

        // ========== ❌ 测试4：手续费代币余额不足 ==========
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(bridge_cat, 704);
        vm.startPrank(bridge_cat);
        nftCollection.approve(address(sourcePoolManager), 704);

        vm.expectRevert(); // safeTransferFrom revert
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(fakeMirrorNft),
            704,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试5：手续费过低（人为设置更低的 collectionFee） ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setNFTBridgeBaseFee(1 ether);
        sourcePoolManager.setCollectionBridgeFee(
            address(nftCollection),
            0.5 ether
        );
        vm.stopPrank();

        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 705);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 705);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        vm.expectRevert("Fee too low");
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(fakeMirrorNft),
            705,
            seek
        );
        vm.stopPrank();
    }

    function test_BridgeFinalizeLocalNFT_AllPaths() public {
        uint256 tokenId = 800;
        uint256 feeAmount = 1 ether;
        uint256 nonce = 1;

        // ========== 准备阶段 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, true); // 支持源链（假设是 Sepolia）
        vm.stopPrank();

        // ========== ✅ 场景1：桥合约已经持有 NFT ==========
        // 桥合约作为 owner 持有 NFT
        vm.prank(address(sourcePoolManager));
        fakeMirrorNft.mint(address(sourcePoolManager), tokenId);
        assertEq(fakeMirrorNft.ownerOf(tokenId), address(sourcePoolManager));

        vm.prank(ReLayer);
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId,
            feeAmount,
            nonce
        );

        // ✅ 用户成功获得 NFT
        assertEq(fakeMirrorNft.ownerOf(tokenId), seek);

        // ========== ✅ 场景2：桥合约没有该 NFT（首次跨链） ==========
        uint256 tokenId2 = 801;
        vm.prank(ReLayer);
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(fakeMirrorNft), // Wrapped collection
            address(nftCollection),
            cat,
            seek,
            tokenId2,
            feeAmount,
            nonce + 1
        );

        // ✅ 新 NFT 被 mint 出来
        assertEq(nftCollection.ownerOf(tokenId2), seek);

        // ========== ✅ 场景3：ownerOf revert（NFT尚未存在） ==========
        uint256 tokenId3 = 802;
        vm.prank(ReLayer);
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(fakeMirrorNft),
            address(nftCollection),
            cat,
            seek,
            tokenId3,
            feeAmount,
            nonce + 2
        );

        // ✅ 新 NFT 被 mint 出来（即便 ownerOf revert）
        assertEq(nftCollection.ownerOf(tokenId3), seek);

        // ========== ❌ 测试1：destChainId 错误 ==========
        vm.prank(ReLayer);
        vm.expectRevert(); // sourceChainIdError()
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            9999, // 错误目标链
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            900,
            feeAmount,
            nonce + 3
        );

        // ========== ❌ 测试2：sourceChainId 不被支持 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, false);
        vm.stopPrank();

        vm.prank(ReLayer);
        vm.expectRevert(); // ChainIdIsNotSupported()
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            901,
            feeAmount,
            nonce + 4
        );

        // ========== ❌ 测试3：非 relayer 调用 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, true);
        vm.stopPrank();

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            902,
            feeAmount,
            nonce + 5
        );
    }

    function test_SetNFTBridgeFeeFunctions_AllPaths() public {
        address testToken = address(erc20Token);
        address testCollection = address(nftCollection);

        // ========== ✅ 测试1：ReLayer 正常调用 ==========
        vm.startPrank(ReLayer);

        // 1️⃣ setNFTBridgeBaseFee

        sourcePoolManager.setNFTBridgeBaseFee(2 ether);
        assertEq(sourcePoolManager.NFTBridgeBaseFee(), 2 ether);

        // 2️⃣ setNftFeeToken

        sourcePoolManager.setNftFeeToken(testToken);
        assertEq(sourcePoolManager.nftFeeToken(), testToken);

        // 3️⃣ setCollectionBridgeFee

        sourcePoolManager.setCollectionBridgeFee(testCollection, 3 ether);
        assertEq(
            sourcePoolManager.collectionBridgeFee(testCollection),
            3 ether
        );

        vm.stopPrank();

        // ========== ❌ 测试2：非 ReLayer 调用应 revert ==========
        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.setNFTBridgeBaseFee(5 ether);

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.setNftFeeToken(address(erc20Token));

        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.setCollectionBridgeFee(testCollection, 1 ether);
    }
}
