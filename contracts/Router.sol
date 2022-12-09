// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/IOrderBook.sol";
import "./interfaces/IOrderFillCallback.sol";
import "./interfaces/IFactory.sol";

import "./library/FullMath.sol";

/// @title Router
/// @notice Router for interacting with order books. The user can specify the
/// token pair or the orderBookId of the order book to interact with, and the
/// router will interact with the contract address for that order book
contract Router is IOrderFillCallback {
    IFactory public immutable factory;

    constructor(address factoryAddress) {
        factory = IFactory(factoryAddress);
    }

    /// @notice Returns the order book contract address for a given token pair.
    /// The order book contract may or may not exist.
    function getOrderBook(address token0, address token1)
        private
        view
        returns (IOrderBook)
    {
        return IOrderBook(factory.getOrderBook(token0, token1));
    }

    /// @notice Returns the order book given the orderBookId of that order book.
    /// The order book contract may or may not exist.
    /// @param orderBookId The id of the order book to lookup
    function getOrderBook(uint8 orderBookId) private view returns (IOrderBook) {
        address orderBookAddress = factory.getOrderBook(orderBookId);
        require(orderBookAddress != address(0), "Invalid orderBookId");
        return IOrderBook(orderBookAddress);
    }

    /// @notice Create multiple limit orders in the order book
    /// @param orderBookId The unique identifier of the order book
    /// @param size The number of limit orders to create. The size of each
    /// argument array must be equal to this size
    /// @param amount0Base The amount of token0 for each limit order in terms
    /// of number of sizeTicks. The actual amount of token0 in order i will
    /// be amount0Base[i] * sizeTick
    /// @param priceBase The price of the token0 for each limit order
    /// in terms of token1 and size and price ticks. The actual amount of token1
    /// in the order will be priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param isAsk Whether each order is an ask order. isAsk = true means
    /// the order sells token0 for token1
    /// @param hintId Where to insert each order in the order book. Meant to
    /// be calculated off-chain using the getMockIndexToInsert function
    /// @return orderIds The ids of each created order
    function createLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint64[] memory amount0Base,
        uint64[] memory priceBase,
        uint8[] memory isAsk,
        uint32[] memory hintId
    ) public returns (uint32[] memory orderIds) {
        IOrderBook orderBook = getOrderBook(orderBookId);
        orderIds = new uint32[](size);
        for (uint256 i = 0; i < size; i++) {
            orderIds[i] = orderBook.createLimitOrder(
                amount0Base[i],
                priceBase[i],
                isAsk[i] == 1 ? true : false,
                msg.sender,
                hintId[i]
            );
        }
    }

    /// @notice Create limit order in the order book
    /// @param orderBookId The unique identifier of the order book
    /// @param amount0Base The amount of token0 in terms of number of sizeTicks.
    /// The actual amount of token0 in the order will be newAmount0Base * sizeTick
    /// @param priceBase The price of the token0 in terms of token1 and size
    /// and price ticks. The actual amount of token1 in the order will be
    /// priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param isAsk isAsk = true means the order sells token0 for token1
    /// @param hintId Where to insert order in the order book. Meant to
    /// be calculated off-chain using the getMockIndexToInsert function
    /// @return orderId The id of the creataed order
    function createLimitOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        uint8 isAsk,
        uint32 hintId
    ) public returns (uint32 orderId) {
        IOrderBook orderBook = getOrderBook(orderBookId);
        orderId = orderBook.createLimitOrder(
            amount0Base,
            priceBase,
            isAsk == 1,
            msg.sender,
            hintId
        );
    }

    /// @notice Update multiple limit orders in the order book
    /// @param orderBookId The unique identifier of the order book
    /// @param size The number of limit orders to update. The size of each
    /// argument array must be equal to this size
    /// @param orderId The ids of the orders to update
    /// @param newAmount0Base The amount of token0 for each updated limit order
    /// in terms of number of sizeTicks. The actual amount of token0 in the
    /// order will be newAmount0Base * sizeTick
    /// @param newPriceBase The price of the token0 for each limit order
    /// in terms of token1 and size and price ticks. The actual amount of token1
    /// in the order will be priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param hintId Where to insert each order in the order book. Meant to
    /// be calculated off-chain using the getMockIndexToInsert function
    /// @return isUpdated List of bools indicating whether each order was successfully
    /// updated
    function updateLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint32[] memory orderId,
        uint64[] memory newAmount0Base,
        uint64[] memory newPriceBase,
        uint32[] memory hintId
    ) public returns (bool[] memory isUpdated) {
        isUpdated = new bool[](size);
        IOrderBook orderBook = getOrderBook(orderBookId);
        for (uint256 i = 0; i < size; i++) {
            isUpdated[i] = orderBook.updateLimitOrder(
                orderId[i],
                newAmount0Base[i],
                newPriceBase[i],
                msg.sender,
                hintId[i]
            );
        }
    }

    /// @notice Update limit order in the order book
    /// @param orderBookId The unique identifier of the order book
    /// @param orderId The id of the order to update
    /// @param newAmount0Base The amount of token0 in terms of number of sizeTicks.
    /// The actual amount of token0 in the order will be newAmount0Base * sizeTick
    /// @param newPriceBase The price of the token0 in terms of token1 and size
    /// and price ticks. The actual amount of token1 in the order will be
    /// priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param hintId Where to insert order in the order book. Meant to
    /// be calculated off-chain using the getMockIndexToInsert function
    function updateLimitOrder(
        uint8 orderBookId,
        uint32 orderId,
        uint64 newAmount0Base,
        uint64 newPriceBase,
        uint32 hintId
    ) public returns (bool) {
        IOrderBook orderBook = getOrderBook(orderBookId);
        return
            orderBook.updateLimitOrder(
                orderId,
                newAmount0Base,
                newPriceBase,
                msg.sender,
                hintId
            );
    }

    /// @notice Cancel multiple limit orders in the order book
    /// @dev Including an inactive order in the batch cancelation does not
    /// revert. This is to make it easier for market markers to cancel
    /// @param orderBookId The unique identifier of the order book
    /// @param size The number of limit orders to update. The size of each
    /// argument array must be equal to this size
    /// @param orderId The ids of the orders to cancel
    /// @return isCanceled List of bools indicating whether each order was successfully
    /// canceled
    function cancelLimitOrderBatch(
        uint8 orderBookId,
        uint8 size,
        uint32[] memory orderId
    ) public returns (bool[] memory isCanceled) {
        IOrderBook orderBook = getOrderBook(orderBookId);
        isCanceled = new bool[](size);
        for (uint256 i = 0; i < size; i++) {
            isCanceled[i] = orderBook.cancelLimitOrder(orderId[i], msg.sender);
        }
    }

    /// @notice Cancel single limit order in the order book
    /// @param orderBookId The unique identifier of the order book
    /// @param orderId The id of the orders to cancel
    /// @return Whether the order was successfully canceled
    function cancelLimitOrder(uint8 orderBookId, uint32 orderId)
        public
        returns (bool)
    {
        IOrderBook orderBook = getOrderBook(orderBookId);
        return orderBook.cancelLimitOrder(orderId, msg.sender);
    }

    /// @notice Create a market order in the order book
    /// @param orderBookId The unique identifier of the order book
    /// @param amount0Base The amount of token0 in the limit order in terms
    /// of number of sizeTicks. The actual amount of token0 in the order will
    /// be amount0Base * sizeTick
    /// @param priceBase The price of the token0 in terms of token1 and size
    /// and price ticks. The actual amount of token1 in the order will be
    /// priceBase * amount0Base * priceTick * sizeTick / dec0
    /// @param isAsk Whether the order is an ask order. isAsk = true means
    /// the order sells token0 for token1
    function createMarketOrder(
        uint8 orderBookId,
        uint64 amount0Base,
        uint64 priceBase,
        uint8 isAsk
    ) public {
        IOrderBook orderBook = getOrderBook(orderBookId);
        orderBook.createMarketOrder(
            amount0Base,
            priceBase,
            isAsk == 1,
            msg.sender
        );
    }

    /// @inheritdoc IOrderFillCallback
    function addBalanceCallback(
        IERC20Metadata token,
        address account,
        uint256 amount,
        IERC20Metadata otherToken,
        bool tokenOrder
    ) external override {
        if (tokenOrder) {
            require(
                msg.sender ==
                    address(getOrderBook(address(token), address(otherToken)))
            );
        } else {
            require(
                msg.sender ==
                    address(getOrderBook(address(otherToken), address(token)))
            );
        }
        token.transfer(account, amount);
    }

    /// @inheritdoc IOrderFillCallback
    function subtractBalanceCallback(
        IERC20Metadata token,
        address account,
        uint256 amount,
        IERC20Metadata otherToken,
        bool tokenOrder
    ) external override {
        if (tokenOrder) {
            require(
                msg.sender ==
                    address(getOrderBook(address(token), address(otherToken)))
            );
        } else {
            require(
                msg.sender ==
                    address(getOrderBook(address(otherToken), address(token)))
            );
        }
        uint256 balance = token.balanceOf(account);
        require(
            amount <= balance,
            "Insufficient funds associated with sender's address"
        );
        token.transferFrom(account, address(this), amount);
    }

    /// @notice Get the order details of all limit orders in the order book.
    /// Each returned list contains the details of ask orders first, followed
    /// by bid orders
    /// @param orderBookId The id of the order book to lookup
    /// @return The ids of the orders
    /// @return The addresses of the orders' owners
    /// @return The amount of token0 remaining in the orders
    /// @return The amount of token1 remaining in the orders
    /// @return Whether each order is an ask order
    function getLimitOrders(uint8 orderBookId)
        external
        view
        returns (
            uint32[] memory,
            address[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory
        )
    {
        IOrderBook orderBook = getOrderBook(orderBookId);
        return orderBook.getLimitOrders();
    }

    /// @notice Get the order details of the ask order with the lowest price
    /// in the order book
    /// @param orderBookId The id of the order book to lookup
    /// @return LimitOrder data struct of the best ask order
    function getBestAsk(uint8 orderBookId)
        external
        view
        returns (LimitOrder memory)
    {
        IOrderBook orderBook = getOrderBook(orderBookId);
        return orderBook.getBestAsk();
    }

    /// @notice Get the order details of the bid order with the highest price
    /// in the order book
    /// @param orderBookId The id of the order book to lookup
    /// @return LimitOrder data struct of the best bid order
    function getBestBid(uint8 orderBookId)
        external
        view
        returns (LimitOrder memory)
    {
        IOrderBook orderBook = getOrderBook(orderBookId);
        return orderBook.getBestBid();
    }

    /// @notice Find the order id to the left of where the new order
    /// should be inserted. Meant to be used off-chain to find the
    /// hintId for the createLimitOrder and updateLimitOrder functions
    /// @param orderBookId The id of the order book to lookup
    /// @param amount0 The amount of token0 in the new order
    /// @param amount1 The amount of token1 in the new order
    /// @param isAsk Whether the new order is an ask order
    /// @return The id of the order to the left of where the new order
    /// should be inserted
    function getMockIndexToInsert(
        uint8 orderBookId,
        uint256 amount0,
        uint256 amount1,
        uint8 isAsk
    ) external view returns (uint32) {
        IOrderBook orderBook = getOrderBook(orderBookId);

        return orderBook.getMockIndexToInsert(amount0, amount1, isAsk == 1);
    }

    /// @dev Get the uint value from msg.data starting from a specific byte
    /// @param startByte The starting byte
    /// @param length The number of bytes to read
    function calldataVal(uint256 startByte, uint256 length)
        private
        pure
        returns (uint256)
    {
        uint256 _retVal;

        require(length < 0x21, "calldataVal length limit is 32 bytes");

        require(
            length + startByte <= msg.data.length,
            "calldataVal trying to read beyond calldatasize"
        );

        assembly {
            _retVal := calldataload(startByte)
        }

        _retVal = _retVal >> (256 - length * 8);

        return _retVal;
    }

    /// @notice This function is called when no other router function is
    /// called. The data should be passed in msg.data.
    /// The first byte of msg.data should be the function selector
    /// 1 = createLimitOrder
    /// 2 = updateLimitOrder
    /// 3 = cancelLimitOrder
    /// 4 = createMarketOrder
    /// The next byte should be the orderBookId of the order book
    /// The next byte should be the number of orders to batch. This is ignored
    /// for the createMarketOrder function
    /// Then, for data for each order is read in a loop
    fallback() external {
        uint256 _func;

        _func = calldataVal(0, 1);
        uint8 orderBookId = uint8(calldataVal(1, 1));
        uint8 batchSize = uint8(calldataVal(2, 1));
        uint256 currentByte = 3;
        uint64[] memory amount0 = new uint64[](batchSize);
        uint64[] memory amount1 = new uint64[](batchSize);
        uint32[] memory hintId = new uint32[](batchSize);
        uint32[] memory orderId = new uint32[](batchSize);

        // createLimitOrder
        if (_func == 1) {
            uint8[] memory isAsk = new uint8[](batchSize);
            for (uint256 i = 0; i < batchSize; i++) {
                amount0[i] = uint64(calldataVal(currentByte, 8));
                amount1[i] = uint64(calldataVal(currentByte + 8, 8));
                isAsk[i] = uint8(calldataVal(currentByte + 16, 1));
                hintId[i] = uint32(calldataVal(currentByte + 17, 4));
                currentByte += 21;
            }
            createLimitOrderBatch(
                orderBookId,
                batchSize,
                amount0,
                amount1,
                isAsk,
                hintId
            );
        }

        // updateLimitOrder
        if (_func == 2) {
            for (uint256 i = 0; i < batchSize; i++) {
                orderId[i] = uint32(calldataVal(currentByte, 4));
                amount0[i] = uint64(calldataVal(currentByte + 4, 8));
                amount1[i] = uint64(calldataVal(currentByte + 12, 8));
                hintId[i] = uint32(calldataVal(currentByte + 20, 4));
                currentByte += 24;
            }
            updateLimitOrderBatch(
                orderBookId,
                batchSize,
                orderId,
                amount0,
                amount1,
                hintId
            );
        }

        // cancelLimitOrder
        if (_func == 3) {
            for (uint256 i = 0; i < batchSize; i++) {
                orderId[i] = uint32(calldataVal(currentByte, 4));
                currentByte += 4;
            }
            cancelLimitOrderBatch(orderBookId, batchSize, orderId);
        }

        // createMarketOrder
        if (_func == 4) {
            createMarketOrder(
                orderBookId,
                uint64(calldataVal(2, 8)),
                uint64(calldataVal(10, 8)),
                uint8(calldataVal(18, 1))
            );
        }
    }
}
