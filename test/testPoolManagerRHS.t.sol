// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PoolManager} from "../src/core/PoolManager.sol";
import {PoolManagerRootHash} from "../src/core/PoolManagerRootHash.sol";
import {MessageManager} from "../src/core/MessageManager.sol";
import {mockToken} from "../script/utils/mockERC20.sol";
import {USDCToken} from "../src/token/Wrapped/USDC.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/interfaces/IPoolManager.sol";
import {SimpleTestNFT} from "./token/nftDemo.sol";
import {NonBurnNFT} from "./token/nftDemo2.sol";
import {NonMintNFT} from "./token/nftDemo3.sol";

contract PoolManagerRHSTest is Test {
    PoolManagerRootHash public sourcePoolManager;
    PoolManager public destPoolManager;
    MessageManager public sourceMessageManager;
    MessageManager public destMessageManager;

    mockToken public erc20Token;
    USDCToken public usdcTokenImple;
    USDCToken public usdcToken;
    address public constant NativeTokenAddress =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    SimpleTestNFT nftCollection;
    SimpleTestNFT mirrorNft;
    SimpleTestNFT fakeMirrorNft;

    uint256 constant SOURCE_CHAIN_ID = 1;
    uint256 constant DEST_CHAIN_ID = 10;

    address cat = makeAddr("cat");
    address seek = makeAddr("seek");

    address bridge_cat = makeAddr("bridge_cat");
    address bridge_seek = makeAddr("bridge_seek");

    address admin;
    address ReLayer;

    function setUp() public {
        admin = makeAddr("admin");
        ReLayer = makeAddr("ReLayer");

        vm.deal(admin, 1000 ether);
        vm.deal(ReLayer, 1000 ether);
        vm.deal(cat, 1000 ether);

        PoolManager poolManagerLogic = new PoolManager();
        PoolManagerRootHash poolManagerRHLogic = new PoolManagerRootHash();
        MessageManager messageManagerLogic = new MessageManager();
        erc20Token = new mockToken("CAT", "CAT");
        usdcTokenImple = new USDCToken();

        vm.startPrank(admin);
        TransparentUpgradeableProxy sourcePoolManagerProxy = new TransparentUpgradeableProxy(
                address(poolManagerRHLogic),
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

        TransparentUpgradeableProxy usdcTokenProxy = new TransparentUpgradeableProxy(
                address(usdcTokenImple),
                admin,
                ""
            );

        usdcToken = USDCToken(address(usdcTokenProxy));
        usdcToken.initialize(ReLayer);
        sourcePoolManager = PoolManagerRootHash(
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
        usdcToken.mint(cat, 1000 ether);
        usdcToken.setBridgeAddress(address(sourcePoolManager));
        sourcePoolManager.setValidChainId(DEST_CHAIN_ID, true);
        sourcePoolManager.setTokenUSDTExchangeRate(1e5, address(erc20Token)); // 1 USDT = 10 CAT
        destPoolManager.setValidChainId(SOURCE_CHAIN_ID, true);
        sourcePoolManager.setPerFee(
            3000,
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ); // 0.3%
        destPoolManager.setPerFee(
            3000,
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
        ); // 0.3%
        sourcePoolManager.setPerFee(3000, address(erc20Token)); // 0.3%
        destPoolManager.setPerFee(3000, address(erc20Token)); // 0.3%
        sourcePoolManager.setSupportERC20Token(address(erc20Token), true);
        destPoolManager.setSupportERC20Token(address(erc20Token), true);
        sourcePoolManager.setSupportERC20Token(NativeTokenAddress, true);
        destPoolManager.setSupportERC20Token(NativeTokenAddress, true);
        sourcePoolManager.setSupportERC20Token(address(usdcToken), true);
        destPoolManager.setSupportERC20Token(address(usdcToken), true);
        // sourcePoolManager.setMaxTransferAmount(1000 ether, false);
        sourcePoolManager.depositNativeTokenToBridge{value: 500 ether}(); // 起始原始代币储备500 ETH
        destPoolManager.depositNativeTokenToBridge{value: 500 ether}();

        mockToken(address(erc20Token)).mint(cat, 1000 ether);
        vm.stopPrank();

        vm.startPrank(cat);
        usdcToken.approve(address(sourcePoolManager), 1000 ether);
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

    function test_Bridge_WrappedERC20() public {
        address wrappedToken = address(usdcToken);
        vm.startPrank(ReLayer);
        sourcePoolManager.setSupportERC20Token(wrappedToken, true);
        destPoolManager.setSupportERC20Token(wrappedToken, true);
        vm.stopPrank();

        _bridge_WrappedERC20(10, cat, seek);

        assertEq(usdcToken.balanceOf(cat), 990 ether);
        assertEq(usdcToken.totalSupply(), 990 ether);
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
        uint256 tokenUsdtRate = sourcePoolManager.TokenUSDTExchangeRate(
            address(erc20Token)
        );
        uint256 usdtAmount = (bridgeAmount * tokenUsdtRate) / (1e6 * 1e12); // 1e6 for USDT, 1e18 for CAT
        uint256 fee = (usdtAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = usdtAmount - fee;

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

    function _bridge_WrappedERC20(
        uint256 amount,
        address from,
        address to
    ) internal {
        uint256 bridgeAmount = amount * 1 ether;

        uint256 balanceBefore = sourcePoolManager.FundingPoolBalance(
            address(usdcToken)
        );
        assertEq(balanceBefore, 0);

        uint256 nextMessageNumberBefore = sourceMessageManager
            .nextMessageNumber();

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(from);

        sourcePoolManager.BridgeInitiateWrappedERC20(
            SOURCE_CHAIN_ID,
            DEST_CHAIN_ID,
            to,
            address(usdcToken),
            address(usdcToken),
            bridgeAmount
        );
        vm.stopPrank();

        assertEq(
            usdcToken.balanceOf(address(sourcePoolManager)),
            0,
            "Contract WrappedERC20 balance should equal 0"
        );
        assertEq(
            sourcePoolManager.FundingPoolBalance(address(usdcToken)),
            0,
            "FundingPoolBalance for ERC20 should equal 0"
        );
        assertEq(
            sourceMessageManager.nextMessageNumber(),
            nextMessageNumberBefore + 1,
            "nextMessageNumber should be incremented"
        );

        uint256 perFee = sourcePoolManager.PerFee(address(usdcToken));

        uint256 fee = (bridgeAmount * perFee) / 1_000_000;
        uint256 amountAfterFee = bridgeAmount - fee;

        uint256 messageNonce = 1;
        bytes32 messageHash = keccak256(
            abi.encode(
                SOURCE_CHAIN_ID,
                DEST_CHAIN_ID,
                address(usdcToken),
                address(usdcToken),
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
        assertEq(sourcePoolManager.SupportTokens(3), newToken);

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
        vm.deal(address(sourcePoolManager), amount);

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(ReLayer);
        sourcePoolManager.BridgeFinalizeNativeToken(
            DEST_CHAIN_ID,
            SOURCE_CHAIN_ID,
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
        uint256 amount = 1e6;
        erc20Token.mint(address(sourcePoolManager), 100 ether);

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(ReLayer);
        sourcePoolManager.BridgeFinalizeERC20(
            DEST_CHAIN_ID,
            SOURCE_CHAIN_ID,
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
            10 ether,
            "Receiver should get bridged ERC20 tokens"
        );
    }

    function test_Finalize_WrappedERC20() public {
        uint256 amount = 1 ether;

        vm.chainId(SOURCE_CHAIN_ID);
        vm.startPrank(ReLayer);
        sourcePoolManager.BridgeFinalizeWrappedERC20(
            DEST_CHAIN_ID,
            SOURCE_CHAIN_ID,
            cat,
            seek,
            address(usdcToken),
            address(usdcToken),
            amount,
            0,
            1
        );
        vm.stopPrank();

        assertEq(
            usdcToken.balanceOf(seek),
            1 ether,
            "Receiver should get bridged WrappedERC20 tokens"
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
        uint256 tokenId = 1;
        // uint256 defaultFee = sourcePoolManager.NFTBridgeBaseFee();
        uint256 customFee = 1.5 ether;

        // ========== 准备：配置参数 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(2222, true); // 允许跨到2222
        sourcePoolManager.setNftFeeToken(address(erc20Token));
        sourcePoolManager.setCollectionBridgeFee(
            address(nftCollection),
            customFee
        );

        sourcePoolManager.setNFTBridgeBaseFee(1 ether);

        vm.stopPrank();

        // mint NFT 给cat，授权bridge
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, tokenId);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), tokenId);

        // 给cat一些手续费token并授权
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        uint256 beforeUserFee = erc20Token.balanceOf(cat);

        // ========== ✅ 正常路径：collectionFee存在 ==========

        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(nftCollection),
            tokenId,
            seek
        );

        vm.stopPrank();

        // ✅ NFT 被锁入bridge
        assertEq(nftCollection.ownerOf(tokenId), address(sourcePoolManager));

        // ✅ 手续费被正确扣除
        assertEq(erc20Token.balanceOf(cat), beforeUserFee - customFee);

        // ✅ fee池更新正确
        assertEq(sourcePoolManager.NFTFeePool(address(erc20Token)), customFee);

        // ========== ❌ 测试1：错误的sourceChainId ==========
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 2);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 2);
        vm.expectRevert(); // 会触发 sourceChainIdError()
        sourcePoolManager.BridgeInitiateLocalNFT(
            9999, // 错误链id
            2222,
            address(nftCollection),
            address(nftCollection),
            2,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试2：目标链不支持 ==========
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 3);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 3);
        vm.expectRevert(); // ChainIdIsNotSupported
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            3333, // 未开启支持
            address(nftCollection),
            address(nftCollection),
            3,
            seek
        );
        vm.stopPrank();

        // ========== ✅ 测试3：collectionBridgeFee为0，fallback到默认baseFee ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setCollectionBridgeFee(address(nftCollection), 0);
        vm.stopPrank();

        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 4);

        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 4);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        uint256 beforeFee2 = erc20Token.balanceOf(cat);

        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(nftCollection),
            4,
            seek
        );

        assertEq(erc20Token.balanceOf(cat), beforeFee2 - 1 ether);
        vm.stopPrank();

        // ========== ❌ 测试4：手续费代币余额不足 ==========
        vm.prank(address(sourcePoolManager));
        nftCollection.mint(bridge_cat, 5);
        vm.startPrank(bridge_cat);
        nftCollection.approve(address(sourcePoolManager), 5);

        // 这里不给 bridge_cat 足够的余额
        vm.expectRevert();
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(nftCollection),
            5,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试5：手续费过低（人为设置更低的baseFee） ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setNFTBridgeBaseFee(1 ether);
        sourcePoolManager.setCollectionBridgeFee(
            address(nftCollection),
            0.5 ether
        );
        vm.stopPrank();

        vm.prank(address(sourcePoolManager));
        nftCollection.mint(cat, 6);
        vm.startPrank(cat);
        nftCollection.approve(address(sourcePoolManager), 6);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        vm.expectRevert("Fee too low");
        sourcePoolManager.BridgeInitiateLocalNFT(
            block.chainid,
            2222,
            address(nftCollection),
            address(nftCollection),
            6,
            seek
        );
        vm.stopPrank();
    }

    function test_BridgeInitiateMirrorNFT_AllPaths() public {
        uint256 tokenId = 10;
        uint256 customFee = 1.5 ether;

        // ========== 准备：配置参数 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(2222, true);
        sourcePoolManager.setNftFeeToken(address(erc20Token));
        sourcePoolManager.setCollectionBridgeFee(address(mirrorNft), customFee);
        sourcePoolManager.setNFTBridgeBaseFee(1 ether);
        vm.stopPrank();

        // mint 镜像NFT给cat，授权bridge
        vm.prank(address(sourcePoolManager));
        mirrorNft.mint(cat, tokenId);
        vm.startPrank(cat);
        mirrorNft.approve(address(sourcePoolManager), tokenId);

        // 给cat一些手续费token并授权
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        uint256 beforeUserFee = erc20Token.balanceOf(cat);

        // ========== ✅ 正常路径：collectionFee存在 ==========
        sourcePoolManager.BridgeInitiateMirrorNFT(
            block.chainid,
            2222,
            address(mirrorNft),
            address(fakeMirrorNft),
            tokenId,
            seek
        );

        vm.stopPrank();

        // ✅ NFT 被成功销毁（ownerOf应revert）
        vm.expectRevert();
        mirrorNft.ownerOf(tokenId);

        // ✅ 手续费正确扣除
        assertEq(erc20Token.balanceOf(cat), beforeUserFee - customFee);

        // ✅ fee池更新正确
        assertEq(sourcePoolManager.NFTFeePool(address(erc20Token)), customFee);

        // ========== ❌ 测试1：错误的sourceChainId ==========
        vm.prank(address(sourcePoolManager));
        mirrorNft.mint(cat, 11);
        vm.startPrank(cat);
        mirrorNft.approve(address(sourcePoolManager), 11);
        vm.expectRevert(); // sourceChainIdError
        sourcePoolManager.BridgeInitiateMirrorNFT(
            9999,
            2222,
            address(mirrorNft),
            address(fakeMirrorNft),
            11,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试2：目标链不支持 ==========
        vm.prank(address(sourcePoolManager));
        mirrorNft.mint(cat, 12);
        vm.startPrank(cat);
        mirrorNft.approve(address(sourcePoolManager), 12);
        vm.expectRevert(); // ChainIdIsNotSupported
        sourcePoolManager.BridgeInitiateMirrorNFT(
            block.chainid,
            3333,
            address(mirrorNft),
            address(fakeMirrorNft),
            12,
            seek
        );
        vm.stopPrank();

        // ========== ✅ 测试3：collectionBridgeFee为0，fallback到默认baseFee ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setCollectionBridgeFee(address(mirrorNft), 0);
        vm.stopPrank();

        vm.prank(address(sourcePoolManager));
        mirrorNft.mint(cat, 13);

        vm.startPrank(cat);
        mirrorNft.approve(address(sourcePoolManager), 13);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        uint256 beforeFee2 = erc20Token.balanceOf(cat);

        sourcePoolManager.BridgeInitiateMirrorNFT(
            block.chainid,
            2222,
            address(mirrorNft),
            address(fakeMirrorNft),
            13,
            seek
        );

        // ✅ fee按baseFee扣除
        assertEq(erc20Token.balanceOf(cat), beforeFee2 - 1 ether);
        vm.stopPrank();

        // ========== ❌ 测试4：手续费代币余额不足 ==========
        vm.prank(address(sourcePoolManager));
        mirrorNft.mint(bridge_cat, 14);
        vm.startPrank(bridge_cat);
        mirrorNft.approve(address(sourcePoolManager), 14);
        vm.expectRevert(); // ERC20转账失败
        sourcePoolManager.BridgeInitiateMirrorNFT(
            block.chainid,
            2222,
            address(mirrorNft),
            address(fakeMirrorNft),
            14,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试5：手续费过低（人为设置更低的baseFee） ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setNFTBridgeBaseFee(1 ether);
        sourcePoolManager.setCollectionBridgeFee(address(mirrorNft), 0.5 ether);
        vm.stopPrank();

        vm.prank(address(sourcePoolManager));
        mirrorNft.mint(cat, 15);
        vm.startPrank(cat);
        mirrorNft.approve(address(sourcePoolManager), 15);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        vm.expectRevert("Fee too low");
        sourcePoolManager.BridgeInitiateMirrorNFT(
            block.chainid,
            2222,
            address(mirrorNft),
            address(fakeMirrorNft),
            15,
            seek
        );
        vm.stopPrank();

        // ========== ❌ 测试6：NFT非Burnable（应revert） ==========
        // 部署一个不带burn的NFT
        NonBurnNFT nonBurnableNFT = new NonBurnNFT(
            "NonBurnable",
            "NBNFT",
            address(sourcePoolManager)
        );

        vm.prank(address(sourcePoolManager));
        nonBurnableNFT.mint(cat, 99);

        vm.startPrank(cat);
        nonBurnableNFT.approve(address(sourcePoolManager), 99);
        erc20Token.approve(address(sourcePoolManager), 10 ether);
        vm.expectRevert(); // burn函数不存在
        sourcePoolManager.BridgeInitiateMirrorNFT(
            block.chainid,
            2222,
            address(nonBurnableNFT),
            address(fakeMirrorNft),
            99,
            seek
        );
        vm.stopPrank();
    }

    function test_BridgeFinalizeMirrorNFT_AllPaths() public {
        uint256 tokenId = 500;
        uint256 feeAmount = 1 ether;
        uint256 nonce = 1;

        // ========== 准备：配置参数 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, true); // 假设源链是 Sepolia
        sourcePoolManager.setNftFeeToken(address(erc20Token));
        sourcePoolManager.setNFTBridgeBaseFee(1 ether);
        sourcePoolManager.setCollectionBridgeFee(address(mirrorNft), 1.5 ether);
        vm.stopPrank();

        vm.prank(ReLayer);
        sourcePoolManager.BridgeFinalizeMirrorNFT(
            11155111, // sourceChainId
            block.chainid, // destChainId
            address(mirrorNft),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId,
            feeAmount,
            nonce
        );

        // ✅ 检查 NFT 被正确 mint 给目标用户
        assertEq(fakeMirrorNft.ownerOf(tokenId), seek);

        // ========== ❌ 测试1：destChainId 错误 ==========
        vm.prank(ReLayer);
        vm.expectRevert(); // sourceChainIdError
        sourcePoolManager.BridgeFinalizeMirrorNFT(
            11155111,
            9999, // 错误的目标链 ID
            address(mirrorNft),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId + 1,
            feeAmount,
            nonce + 1
        );

        // ========== ❌ 测试2：sourceChainId 不被支持 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, false); // 取消支持源链
        vm.stopPrank();

        vm.prank(ReLayer);
        vm.expectRevert(); // ChainIdIsNotSupported
        sourcePoolManager.BridgeFinalizeMirrorNFT(
            11155111,
            block.chainid,
            address(mirrorNft),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId + 2,
            feeAmount,
            nonce + 2
        );

        // 恢复源链支持
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, true);
        vm.stopPrank();

        // ========== ❌ 测试3：非ReLayer调用 ==========
        vm.prank(cat);
        vm.expectRevert(
            "TreasureManager:onlyReLayer only relayer call this function"
        );
        sourcePoolManager.BridgeFinalizeMirrorNFT(
            11155111,
            block.chainid,
            address(mirrorNft),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId + 3,
            feeAmount,
            nonce + 3
        );

        // ========== ❌ 测试4：目标合约 mint 异常 ==========
        // 部署一个不含 mint 的普通NFT，用来测试mint失败分支
        NonMintNFT nonMintableNFT = new NonMintNFT(
            "NoMint",
            "NMNFT",
            address(sourcePoolManager)
        );

        vm.prank(ReLayer);
        vm.expectRevert(); // IWrappedERC721.mint 调用失败
        sourcePoolManager.BridgeFinalizeMirrorNFT(
            11155111,
            block.chainid,
            address(mirrorNft),
            address(nonMintableNFT),
            cat,
            seek,
            tokenId + 4,
            feeAmount,
            nonce + 4
        );
    }

    function test_BridgeFinalizeLocalNFT_AllPaths() public {
        uint256 tokenId = 600;
        uint256 feeAmount = 1 ether;
        uint256 nonce = 1;

        // ========== 准备：配置参数 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, true); // 源链支持
        sourcePoolManager.setNftFeeToken(address(erc20Token));
        sourcePoolManager.setNFTBridgeBaseFee(1 ether);
        sourcePoolManager.setCollectionBridgeFee(
            address(nftCollection),
            1.5 ether
        );
        vm.stopPrank();

        // ========== ✅ 情况1：桥内已有NFT，直接转给用户 ==========
        // mint 一个NFT到桥合约中，模拟“之前锁过”
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

        // ✅ 验证 NFT 从桥合约转移给用户
        assertEq(fakeMirrorNft.ownerOf(tokenId), seek);

        // ========== ✅ 情况2：桥没有NFT（第一次跨链，需要mint） ==========
        uint256 newTokenId = 601;
        vm.prank(ReLayer);
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            newTokenId,
            feeAmount,
            nonce + 1
        );

        // ✅ NFT 应该被mint出来并属于用户
        assertEq(fakeMirrorNft.ownerOf(newTokenId), seek);

        // ========== ❌ 测试1：destChainId错误 ==========
        vm.prank(ReLayer);
        vm.expectRevert(); // sourceChainIdError
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            9999,
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId + 10,
            feeAmount,
            nonce + 2
        );

        // ========== ❌ 测试2：sourceChainId不支持 ==========
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, false);
        vm.stopPrank();

        vm.prank(ReLayer);
        vm.expectRevert(); // ChainIdIsNotSupported
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(nftCollection),
            address(fakeMirrorNft),
            cat,
            seek,
            tokenId + 11,
            feeAmount,
            nonce + 3
        );

        // 恢复支持
        vm.startPrank(ReLayer);
        sourcePoolManager.setValidChainId(11155111, true);
        vm.stopPrank();

        // ========== ❌ 测试3：非ReLayer调用 ==========
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
            tokenId + 12,
            feeAmount,
            nonce + 4
        );

        // ========== ❌ 测试4：mint异常分支（目标NFT不支持mint） ==========
        NonMintNFT nonMintableNFT = new NonMintNFT(
            "NoMintLocal",
            "NMLNFT",
            address(sourcePoolManager)
        );

        vm.prank(ReLayer);
        vm.expectRevert(); // mint 调用失败
        sourcePoolManager.BridgeFinalizeLocalNFT(
            11155111,
            block.chainid,
            address(nonMintableNFT),
            address(nonMintableNFT),
            cat,
            seek,
            tokenId + 13,
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
