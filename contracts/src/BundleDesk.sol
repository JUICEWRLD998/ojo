// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BundleDesk
/// @notice How a guest gets notes. A vendor deposits stablecoin, sells the guest a voucher for naira off-chain, and the
///         guest's page claims it. The naira side is ordinary P2P trade and is the vendor's responsibility.
/// @dev A voucher is a one-time bearer key. The vendor signs `Voucher(vendor, token, amount, voucher, expiry)` where
///      `voucher` is the address of a fresh key printed in the QR. To claim, that key signs `Claim(voucherDigest, to)`.
///      Binding `to` to the voucher key means a relayer or mempool watcher cannot redirect the payout.
///      A vendor can withdraw before a voucher is claimed; that voucher then fails with InsufficientBalance.
contract BundleDesk is EIP712 {
    using SafeERC20 for IERC20;

    bytes32 public constant VOUCHER_TYPEHASH =
        keccak256("Voucher(address vendor,address token,uint256 amount,address voucher,uint256 expiry)");
    bytes32 public constant CLAIM_TYPEHASH = keccak256("Claim(bytes32 voucherDigest,address to)");

    address public immutable AUSD;
    address public immutable USDC;

    mapping(address vendor => mapping(address token => uint256)) public balanceOf;
    mapping(bytes32 voucherDigest => bool) public claimed;

    event Deposited(address indexed vendor, address indexed token, uint256 amount);
    event Withdrawn(address indexed vendor, address indexed token, uint256 amount);
    event Claimed(address indexed vendor, address indexed to, address indexed token, uint256 amount, address voucher);

    error UnsupportedToken();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error AlreadyClaimed();
    error Expired();
    error BadVendorSig();
    error BadClaimSig();

    constructor(address ausd, address usdc) EIP712("BundleDesk", "1") {
        if (ausd == address(0) || usdc == address(0)) revert ZeroAddress();
        AUSD = ausd;
        USDC = usdc;
    }

    /// @notice Vendor deposits `amount` (needs a prior ERC-20 approval to this contract).
    function deposit(address token, uint256 amount) external {
        _checkToken(token);
        if (amount == 0) revert ZeroAmount();
        balanceOf[msg.sender][token] += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    /// @notice Vendor takes back unclaimed balance.
    function withdraw(address token, uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        uint256 bal = balanceOf[msg.sender][token];
        if (bal < amount) revert InsufficientBalance();
        balanceOf[msg.sender][token] = bal - amount;
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, token, amount);
    }

    /// @notice Pay a voucher to `to`. Relayed: the voucher key signs `Claim(voucherDigest, to)`.
    function claim(
        address vendor,
        address token,
        uint256 amount,
        address voucher,
        uint256 expiry,
        address to,
        bytes calldata vendorSig,
        bytes calldata claimSig
    ) external {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp > expiry) revert Expired();

        bytes32 voucherDigest =
            _hashTypedDataV4(keccak256(abi.encode(VOUCHER_TYPEHASH, vendor, token, amount, voucher, expiry)));
        if (claimed[voucherDigest]) revert AlreadyClaimed();
        if (!_signedBy(voucherDigest, vendorSig, vendor)) revert BadVendorSig();

        bytes32 claimDigest = _hashTypedDataV4(keccak256(abi.encode(CLAIM_TYPEHASH, voucherDigest, to)));
        if (!_signedBy(claimDigest, claimSig, voucher)) revert BadClaimSig();

        uint256 bal = balanceOf[vendor][token];
        if (bal < amount) revert InsufficientBalance();

        claimed[voucherDigest] = true;
        balanceOf[vendor][token] = bal - amount;
        IERC20(token).safeTransfer(to, amount);

        emit Claimed(vendor, to, token, amount, voucher);
    }

    function _checkToken(address token) private view {
        if (token != AUSD && token != USDC) revert UnsupportedToken();
    }

    /// True only when `sig` is a well-formed signature by `signer` (never reverts on a malformed signature).
    function _signedBy(bytes32 digest, bytes calldata sig, address signer) private pure returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
        return err == ECDSA.RecoverError.NoError && recovered == signer && signer != address(0);
    }
}
