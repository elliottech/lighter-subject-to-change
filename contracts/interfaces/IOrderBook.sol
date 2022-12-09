// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../library/LinkedList.sol";

/// @title Order Book Interface
/// @notice An order book facilitates placing limit and market orders to trade
/// two assets which conform to the ERC20 specification. token0 is the asset
/// traded in the order book, and token1 is the asset paid/received for trading
/// token0
interface IOrderBook {
    /// @notice Create a limit order in the order book. The order will be
    /// filled by existing orders if there is a price overlap. If the order
    /// is not fully filled, it will be added to the order book
    /// @param amount0Base The amount of token0 in the limit order in terms
    /// of number of sizeTicks. The actual amount of token0 in the order will
    /// be amount0Base * sizeTick
    /// @param priceBase The price of the token0 in terms of token1 and size
    /// and price ticks. The actual amount of token1 in the order will be
    /// priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param isAsk Whether the order is an ask order. isAsk = true means
    /// the order sells token0 for token1
    /// @param from The address of the order sender
    /// @param hintId Where to insert the order in the order book. Meant to
    /// be calculated off-chain using the getMockIndexToInsert function
    /// @return The id of the order
    function createLimitOrder(
        uint256 amount0Base,
        uint256 priceBase,
        bool isAsk,
        address from,
        uint32 hintId
    ) external returns (uint32);

    /// @notice Update an existing limit order in the order book. The updated
    /// order will be filled by existing orders if there is a price overlap.
    /// If the order is not fully filled, it will be added to the order book
    /// @param id The id of the order to update
    /// @param newAmount0Base The amount of token0 in the updated limit order
    /// in terms of number of sizeTicks. The actual amount of token0 in the
    /// order will be newAmount0Base * sizeTick
    /// @param newPriceBase The price of the token0 in terms of token1 and size
    /// and price ticks. The actual amount of token1 in the order will be
    /// priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param from The address of the order sender
    // @param hintId Where to insert the order in the order book. Meant to
    /// be calculated off-chain using the getMockIndexToInsert function
    /// @return Whether the order was successfully updated
    function updateLimitOrder(
        uint32 id,
        uint256 newAmount0Base,
        uint256 newPriceBase,
        address from,
        uint32 hintId
    ) external returns (bool);

    /// @notice Cancel an existing limit order in the order book. Refunds the
    /// remaining tokens in the order to the owner
    /// @param id The id of the order to cancel
    /// @param from The address of the order sender
    /// @return Whether the order was successfully canceled
    function cancelLimitOrder(uint32 id, address from) external returns (bool);

    /// @notice Create a market order in the order book. The order will be
    /// filled by existing orders if there is a price overlap. If the order
    /// is not fully filled, it will NOT be added to the order book
    /// @param amount0Base The amount of token0 in the limit order in terms
    /// of number of sizeTicks. The actual amount of token0 in the order will
    /// be amount0Base * sizeTick
    /// @param priceBase The price of the token0 in terms of token1 and size
    /// and price ticks. The actual amount of token1 in the order will be
    /// priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param isAsk Whether the order is an ask order. isAsk = true means
    /// the order sells token0 for token1
    /// @param from The address of the order sender
    function createMarketOrder(
        uint256 amount0Base,
        uint256 priceBase,
        bool isAsk,
        address from
    ) external;

    /// @notice Get the order details of all limit orders in the order book.
    /// Each returned list contains the details of ask orders first, followed
    /// by bid orders
    /// @return The ids of the orders
    /// @return The addresses of the orders' owners
    /// @return The amount of token0 remaining in the orders
    /// @return The amount of token1 remaining in the orders
    /// @return Whether each order is an ask order
    function getLimitOrders()
        external
        view
        returns (
            uint32[] memory,
            address[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory
        );

    /// @notice Get the order details of the ask order with the lowest price
    /// in the order book
    /// @return LimitOrder data struct of the best ask order
    function getBestAsk() external view returns (LimitOrder memory);

    /// @notice Get the order details of the bid order with the highest price
    /// in the order book
    /// @return LimitOrder data struct of the best bid order
    function getBestBid() external view returns (LimitOrder memory);

    /// @notice Return whether an order is active
    /// @param id The id of the order
    /// @return True if the order is active, false otherwise
    function isOrderActive(uint32 id) external view returns (bool);

    /// @notice Find the order id to the left of where the new order
    /// should be inserted. Meant to be used off-chain to find the
    /// hintId for the createLimitOrder and updateLimitOrder functions
    /// @param amount0 The amount of token0 in the new order
    /// @param amount1 The amount of token1 in the new order
    /// @param isAsk Whether the new order is an ask order
    /// @return The id of the order to the left of where the new order
    /// should be inserted
    function getMockIndexToInsert(
        uint256 amount0,
        uint256 amount1,
        bool isAsk
    ) external view returns (uint32);

    /// @notice Return the unique identifier of an order book
    function orderBookId() external view returns (uint8);

    /// @notice The base token
    /// @return The token contract
    function token0() external view returns (IERC20Metadata);

    /// @notice The quote token
    /// @return The token contract
    function token1() external view returns (IERC20Metadata);

    /// @notice Return the sizeTick of the order book
    function sizeTick() external view returns (uint256);

    /// @notice Return the priceTick of the order book
    function priceTick() external view returns (uint256);
}
