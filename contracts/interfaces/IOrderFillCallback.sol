// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title OrderFillCallback interface
/// @notice Callback for updating token balances
interface IOrderFillCallback {
    /// @notice Transfer tokens from the contract to the user
    /// @param token The token to transfer
    /// @param account The user to transfer to
    /// @param amount The amount to transfer
    /// @param otherToken The other token in the order book, used to identify
    /// the order book
    /// @param tokenOrder True if token is token0 in the order book, false if
    /// token is token1 in the order book
    function addBalanceCallback(
        IERC20Metadata token,
        address account,
        uint256 amount,
        IERC20Metadata otherToken,
        bool tokenOrder
    ) external;

    /// @notice Transfer tokens from the user to the contract
    /// @param token The token to transfer
    /// @param account The user to transfer from
    /// @param amount The amount to transfer
    /// @param otherToken The other token in the order book, used to identify
    /// the order book
    /// @param tokenOrder True if token is token0 in the order book, false if
    /// token is token1 in the order book
    function subtractBalanceCallback(
        IERC20Metadata token,
        address account,
        uint256 amount,
        IERC20Metadata otherToken,
        bool tokenOrder
    ) external;
}
